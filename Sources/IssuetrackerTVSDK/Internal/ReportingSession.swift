import SwiftUI
import UIKit

// Orchestrates the "show reporter → submit → dismiss" flow. Owns the
// hosting controller while it's on-screen so it doesn't get dropped.
//
// tvOS presentation: `.blurOverFullScreen` with a clear hosting view,
// so the SDK surfaces render as a focused panel over a blurred
// snapshot of the host app — the screenshot being reported stays
// visible as context behind the form. No sheets/detents on this
// platform.
enum ReportingSession {
    @MainActor
    private static var presented = false
    // Preserves in-progress draft data across the "Not you?" name
    // re-prompt so the user doesn't lose what they'd already typed —
    // on TV re-entering text is expensive.
    @MainActor
    private static var pendingDraft: ReportDraft?

    @MainActor
    static func present(runtime: Runtime) {
        // ADR-0003 Decision 9 pre-flight gate. When the SDK has been
        // terminated (project deleted, key revoked, workspace
        // suspended), every trigger that lands here shows the terminal
        // message instead of the report form — no retry, no error
        // code, no link back to our service. Survives app launches via
        // LifecycleStore's UserDefaults persistence.
        if LifecycleStore.shared.isTerminated {
            presentTerminated(strings: runtime.terminatedUI)
            return
        }
        if ReporterIdentity.name == nil {
            presentNamePrompt(runtime: runtime, resumingDraft: nil)
        } else {
            presentInternal(runtime: runtime, draft: nil, initialScreenshot: nil)
        }
    }

    @MainActor
    private static func presentTerminated(strings: TerminatedUiStrings?) {
        guard !presented else { return }
        presented = true

        let view = TerminatedView(
            strings: strings,
            onClose: {
                topViewController()?.dismiss(animated: true) {
                    presented = false
                }
            }
        )
        present(rootView: AnyView(view))
    }

    // Shown before the report UI on first use (or when the user picks
    // "Not you?" on an in-progress report). `resumingDraft` carries
    // the in-progress report forward across the re-prompt so the user
    // doesn't lose what they'd already typed.
    @MainActor
    private static func presentNamePrompt(runtime: Runtime, resumingDraft: ReportDraft?) {
        guard !presented else { return }
        presented = true
        pendingDraft = resumingDraft

        let view = NamePromptView(
            onContinue: { name in
                ReporterIdentity.setName(name)
                topViewController()?.dismiss(animated: true) {
                    presented = false
                    let draft = pendingDraft
                    pendingDraft = nil
                    presentInternal(
                        runtime: runtime,
                        draft: draft,
                        initialScreenshot: draft?.screenshot
                    )
                }
            },
            onCancel: {
                pendingDraft = nil
                topViewController()?.dismiss(animated: true) {
                    presented = false
                }
            }
        )
        present(rootView: AnyView(view))
    }

    @MainActor
    private static func changeReporterName(runtime: Runtime, draft: ReportDraft) {
        ReporterIdentity.clearName()
        topViewController()?.dismiss(animated: true) {
            presented = false
            presentNamePrompt(runtime: runtime, resumingDraft: draft)
        }
    }

    @MainActor
    private static func presentInternal(
        runtime: Runtime,
        draft: ReportDraft?,
        initialScreenshot: UIImage?
    ) {
        guard !presented else { return }
        presented = true

        // Capture BEFORE our own UI goes up — the report should show
        // the host app, not the reporter. If we're coming back from
        // the name prompt, the draft already carries the screenshot.
        let screenshot = initialScreenshot ?? draft?.screenshot ?? ScreenshotCapture.captureCurrentWindow()

        let view = ReportView(
            screenshot: screenshot,
            initialDraft: draft,
            reporterName: ReporterIdentity.name ?? "",
            submit: { title, description, type, includeScreenshot, onState in
                await submit(
                    runtime: runtime,
                    title: title,
                    description: description,
                    type: type,
                    screenshot: includeScreenshot ? screenshot : nil,
                    onState: onState
                )
            },
            onChangeName: { capturedDraft in
                changeReporterName(runtime: runtime, draft: capturedDraft)
            },
            onClose: { dismiss() }
        )
        present(rootView: AnyView(view))
    }

    @MainActor
    private static func present(rootView: AnyView) {
        let host = UIHostingController(rootView: rootView)
        host.modalPresentationStyle = .blurOverFullScreen
        // Clear hosting view so the system blur shows through around
        // the SDK's centered panel.
        host.view.backgroundColor = .clear

        guard let presenter = topViewController() else {
            presented = false
            return
        }
        presenter.present(host, animated: true)
    }

    @MainActor
    private static func dismiss() {
        topViewController()?.dismiss(animated: true)
        presented = false
        pendingDraft = nil
    }

    // Submit-failure → terminal handoff. Dismisses any presented
    // reporter / name-prompt UI, lets the system modal transition
    // settle, and presents the terminal view. Used by submit()'s
    // non-recoverable-error path so the user's next sight is the
    // authoritative TERMINATED state rather than a stale form with a
    // generic error message.
    @MainActor
    private static func dismissAndPresentTerminated(strings: TerminatedUiStrings?) async {
        topViewController()?.dismiss(animated: true)
        presented = false
        pendingDraft = nil
        try? await Task.sleep(nanoseconds: 350_000_000)
        presentTerminated(strings: strings)
    }

    @MainActor
    private static func submit(
        runtime: Runtime,
        title: String,
        description: String,
        type: IssueReportType,
        screenshot: UIImage?,
        onState: @MainActor @escaping (IssueProgressState) -> Void
    ) async -> Result<Void, Error> {
        struct CreateResult: Decodable { let issueId: String }
        let machine = UploadProgressMachine(onState: onState)
        do {
            var payload: [String: Any] = [
                "apiKey": runtime.apiKey,
                "title": title,
                "type": type.rawValue,
                "context": ContextCollector.collect(),
                "reporter": ReporterIdentity.payload(),
            ]
            if !description.isEmpty {
                payload["description"] = description
            }
            // Attach attestation whenever we hold a token — in open
            // mode it still stamps the report with the tester's
            // identity (ADR-0005 Decision 5); in testers-only mode
            // it's what gets us past ingest.
            if let testerToken = AttestationStore.shared.testerToken {
                payload["testerToken"] = testerToken
            }
            if let screenshot,
               let data = screenshot.jpegData(compressionQuality: 0.85) {
                payload["screenshot"] = [
                    "base64": data.base64EncodedString(),
                    "contentType": "image/jpeg",
                    "name": "screenshot-\(Int(Date().timeIntervalSince1970)).jpg",
                ]
            }
            let crumbs = BreadcrumbStore.shared.snapshot()
            if !crumbs.isEmpty {
                payload["breadcrumbs"] = crumbs.map { b -> [String: Any] in
                    var dict: [String: Any] = [
                        "timestamp": Int(b.timestamp.timeIntervalSince1970 * 1000),
                        "action": b.action,
                    ]
                    if let metadata = b.metadata {
                        dict["metadata"] = metadata
                    }
                    return dict
                }
            }
            machine.reportStart()
            let result: CreateResult = try await APIClient.uploadWithProgress(
                endpoint: runtime.endpoint,
                function: "createIssueFromSdk",
                payload: payload,
                onProgress: { fraction in machine.reportProgress(fraction) },
                onProcessing: { machine.reportProcessing() }
            )
            machine.reportDone(issueId: result.issueId)
            return .success(())
        } catch let err as APIClient.CallableError {
            // Tester-gating rejections (ADR-0005) are non-recoverable
            // but NOT terminal — the project is alive, this install
            // just lacks valid attestation. Show a human message,
            // drop any stale token, and re-pull config so the remote
            // trigger goes inert instead of leading users back into
            // this dead end.
            if let reason = err.sdkErrorReason, reason.isTesterGating {
                if reason == .testerTokenInvalid {
                    AttestationStore.shared.clearTesterToken()
                }
                Task { @MainActor in
                    await AttestationStore.shared.refreshRemoteConfig(runtime: runtime)
                }
                machine.reportError("Reporting on this project is limited to enrolled testers.")
                return .failure(err)
            }
            // ADR-0003 Decision 9: terminal failures flip the SDK
            // into one-way TERMINATED. Replace the in-progress
            // submit panel with TerminatedView so the user lands on
            // the authoritative end-state immediately — no need to
            // dismiss and re-trigger to discover bug reporting is gone.
            if let reason = err.sdkErrorReason, reason.isTerminal {
                LifecycleStore.shared.transitionToTerminated(
                    reason: reason,
                    callback: runtime.onConfigurationError
                )
                Task { @MainActor [terminatedUI = runtime.terminatedUI] in
                    await dismissAndPresentTerminated(strings: terminatedUI)
                }
            }
            machine.reportError(err.localizedDescription)
            return .failure(err)
        } catch {
            machine.reportError(error.localizedDescription)
            return .failure(error)
        }
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        guard
            let scene = keyWindowScene(),
            let root = scene.windows
                .first(where: { $0.isKeyWindow })?.rootViewController
                ?? scene.windows.first?.rootViewController
        else {
            return nil
        }
        var current = root
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }

    @MainActor
    private static func keyWindowScene() -> UIWindowScene? {
        return UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first
    }
}
