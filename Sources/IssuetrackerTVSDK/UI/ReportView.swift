import SwiftUI
import UIKit

// Panel shown when the user holds Play/Pause (or the host calls
// report() explicitly). Deliberately minimal — title, optional
// description, type picker, screenshot preview, submit. No
// priority/assignee/labels from the SDK; server-side everything
// defaults (priority=none, unassigned, state=todo, source=sdk).
//
// TV layout: a centered card over the system blur, two columns —
// form on the left, screenshot preview on the right — so the 16:9
// capture gets real estate without pushing the form off-screen.
// Text entry is expensive with the remote, so only the title is
// required; everything else is optional or pre-filled.
//
// Draft state survives the "Not you?" name re-prompt. Everything's
// optional so the initial panel can pass nil.
struct ReportDraft {
    var title: String = ""
    var description: String = ""
    var type: IssueReportType = .bug
    var screenshot: UIImage?
}

struct ReportView: View {
    let screenshot: UIImage?
    let initialDraft: ReportDraft?
    let reporterName: String
    let submit: (
        _ title: String,
        _ description: String,
        _ type: IssueReportType,
        _ includeScreenshot: Bool,
        _ onState: @MainActor @escaping (IssueProgressState) -> Void
    ) async -> Result<Void, Error>
    let onChangeName: (ReportDraft) -> Void
    let onClose: () -> Void

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var type: IssueReportType = .bug
    @State private var error: String?
    @State private var includeScreenshot: Bool = true
    @State private var progressState: IssueProgressState?

    private var isSubmitting: Bool {
        guard let p = progressState else { return false }
        switch p.phase {
        case .idle, .uploading, .processing, .stalled: return true
        case .done, .error: return false
        }
    }

    var body: some View {
        ZStack {
            if let progressState {
                sendingContent(state: progressState)
            } else {
                formPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard let d = initialDraft else { return }
            if title.isEmpty { title = d.title }
            if description.isEmpty { description = d.description }
            type = d.type
        }
    }

    // MARK: - Form

    private var formPanel: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Tokens.Space.s5)
                .padding(.vertical, Tokens.Space.s4)
            Divider().background(Tokens.lineFaint)

            HStack(alignment: .top, spacing: Tokens.Space.s6) {
                formColumn
                if let screenshot {
                    screenshotColumn(screenshot: screenshot)
                }
            }
            .padding(Tokens.Space.s5)

            Divider().background(Tokens.lineFaint)
            footer
        }
        .frame(maxWidth: 1480)
        .background(Tokens.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusLg, style: .continuous))
        .shadow(color: Color.black.opacity(0.35), radius: 60, x: 0, y: 30)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Tokens.Space.s4) {
            BrandHeader(
                title: "Tell us what broke",
                subtitle: "Goes to the team triaging this app."
            )
            if !reporterName.isEmpty {
                reportingAsChip
            }
        }
    }

    private var reportingAsChip: some View {
        HStack(spacing: 12) {
            Text("Reporting as \(reporterName)")
                .brandFont(Tokens.TypeScale.subtitle, relativeTo: .subheadline)
                .foregroundStyle(Tokens.fg3)
            Button("Not you?") {
                onChangeName(currentDraft())
            }
            .buttonStyle(InlineLinkButtonStyle())
            .disabled(isSubmitting)
        }
    }

    private var formColumn: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s5) {
            VStack(alignment: .leading, spacing: 12) {
                FieldLabel(title: "Title")
                BrandTextField(
                    value: $title,
                    placeholder: "Short summary, e.g. playback stalls on Continue Watching"
                )
            }
            VStack(alignment: .leading, spacing: 12) {
                FieldLabel(title: "Type")
                HStack(spacing: 12) {
                    ForEach(IssueReportType.allCases, id: \.self) { t in
                        BrandChip(
                            t.displayName,
                            icon: sfSymbol(for: t),
                            isActive: type == t
                        ) {
                            type = t
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                FieldLabel(title: "What happened? (optional)")
                BrandTextField(
                    value: $description,
                    placeholder: "What did you expect, and what happened instead?"
                )
            }
            if let error {
                Text(error)
                    .brandFont(Tokens.TypeScale.subtitle, relativeTo: .subheadline)
                    .foregroundStyle(Tokens.critical)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func screenshotColumn(screenshot: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldLabel(title: "Screenshot")
            Image(uiImage: screenshot)
                .resizable()
                .scaledToFit()
                .frame(width: 560)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusMd))
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.radiusMd)
                        .stroke(Tokens.line, lineWidth: 2)
                )
                .opacity(includeScreenshot ? 1 : 0.35)
                // Raw UIImage has no description; without this VoiceOver
                // reads it as "image" (1.1.1).
                .accessibilityLabel("Screenshot preview")
            BrandCheckRow(title: "Include screenshot", isOn: $includeScreenshot)
        }
        .frame(width: 560)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Spacer()
            BrandButton("Cancel", variant: .ghost, isDisabled: isSubmitting) {
                onClose()
            }
            .frame(maxWidth: 240)
            BrandButton(
                "Send report",
                icon: "paperplane.fill",
                variant: .primary,
                isDisabled: title.trimmingCharacters(in: .whitespaces).isEmpty,
                isLoading: isSubmitting
            ) {
                Task { await perform() }
            }
            .frame(maxWidth: 340)
        }
        .padding(Tokens.Space.s4)
        .background(Tokens.surfaceApp)
    }

    // MARK: - Actions

    private func perform() async {
        progressState = IssueProgressState(progress: 0, phase: .idle)
        error = nil
        // Tell VoiceOver the form was replaced by the progress card
        // (4.1.3) — the transition is otherwise silent.
        UIAccessibility.post(notification: .screenChanged, argument: "Sending report")

        let result = await submit(
            title.trimmingCharacters(in: .whitespaces),
            description,
            type,
            includeScreenshot && screenshot != nil,
            { state in
                progressState = state
            }
        )
        switch result {
        case .success:
            // Announce before the 2s auto-dismiss so VoiceOver users
            // hear the outcome (4.1.3).
            UIAccessibility.post(notification: .announcement, argument: "Report sent")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            onClose()
        case .failure(let submitError):
            // Progress state already carries phase=error from the upload
            // machine; UI shows retry/close from sendingContent. Surface
            // the failure to VoiceOver as well (3.3.1).
            UIAccessibility.post(
                notification: .announcement,
                argument: "Report failed. \(submitError.localizedDescription)"
            )
        }
    }

    @ViewBuilder
    private func sendingContent(state: IssueProgressState) -> some View {
        VStack(spacing: Tokens.Space.s6) {
            progressBar(for: type, state: state)
                .frame(maxWidth: 960)
            if state.phase == .error {
                HStack(spacing: 16) {
                    BrandButton("Close", variant: .ghost) { onClose() }
                        .frame(maxWidth: 240)
                    BrandButton("Retry", icon: "arrow.clockwise", variant: .primary) {
                        Task { await perform() }
                    }
                    .frame(maxWidth: 300)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func progressBar(for type: IssueReportType, state: IssueProgressState) -> some View {
        let displayTitle = title.trimmingCharacters(in: .whitespaces)
        switch type {
        case .bug:
            BugProgressBar(
                state: state,
                title: displayTitle.isEmpty ? "Bug report" : displayTitle
            )
        case .task:
            TaskProgressBar(
                state: state,
                title: displayTitle.isEmpty ? "Task" : displayTitle
            )
        case .story:
            StoryProgressBar(
                state: state,
                title: displayTitle.isEmpty ? "Story" : displayTitle
            )
        }
    }

    private func currentDraft() -> ReportDraft {
        ReportDraft(
            title: title,
            description: description,
            type: type,
            screenshot: screenshot
        )
    }

    private func sfSymbol(for type: IssueReportType) -> String {
        // Map IssueReportType to an SF Symbol that's roughly equivalent
        // to the Lucide icons in the design system reference (`bug`,
        // `checkmark.square`, `book.closed`).
        switch type {
        case .bug: return "ladybug.fill"
        case .task: return "checklist"
        case .story: return "book.closed.fill"
        }
    }
}

// Small inline text button ("Not you?") — link-styled, focus shown
// via underline + accent.
struct InlineLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyle.Configuration

        var body: some View {
            configuration.label
                .brandFont(Tokens.TypeScale.subtitle, .medium, relativeTo: .subheadline)
                // accentStrong, not accent: #1FA2E8 link text on white
                // is 2.84:1 (fails 1.4.3). ~4.9:1 on white, ~4.2:1 on
                // the focused accentSoft background.
                .foregroundStyle(Tokens.accentStrong)
                .underline(isFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isFocused ? Tokens.accentSoft : .clear)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSm))
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}
