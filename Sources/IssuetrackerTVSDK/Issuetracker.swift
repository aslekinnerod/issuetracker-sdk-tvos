import Foundation
import UIKit

// Public facade for the Issuetracker tvOS SDK. Apps integrate by
// calling `configure(apiKey:)` once at launch; everything else is
// driven by the Siri Remote long-press trigger plus the optional
// programmatic `report()` trigger. The type is `enum` with static
// members so there's no instance to retain — same shape as the iOS
// SDK and Firebase's own SDKs.
//
// Deliberately absent relative to sdk-ios:
//  - shake trigger (no accelerometer in the trigger model on TV)
//  - crash reporting (MetricKit does not exist on tvOS)
//  - video recording + screenshot editor (touch-dependent flows)
public enum Issuetracker {
    @MainActor
    private static var runtime: Runtime?

    /// Call once, as early as possible (e.g. `App.init`). The key is
    /// stored for the lifetime of the app; subsequent calls replace
    /// the configuration.
    ///
    /// - Parameters:
    ///   - apiKey: Raw API key created in the Issuetracker web UI.
    ///     The environment (production vs. staging) is derived from
    ///     the key prefix — there is no endpoint to configure.
    ///   - longPressToReport: If `true` (default), pressing and
    ///     holding Play/Pause on the Siri Remote for 2 seconds brings
    ///     up the reporter from anywhere in the app. Same flag name
    ///     as the long-press trigger on the other SDKs so entitlement
    ///     matrices and docs stay consistent. The Menu/Back button is
    ///     never intercepted — that's system navigation.
    ///   - onConfigurationError: Optional callback invoked once when the
    ///     SDK transitions to the terminated state because the server
    ///     signalled a non-recoverable failure (project deleted, API
    ///     key revoked, workspace suspended, etc. — see
    ///     ``SdkErrorReason``). Default behaviour is silent in
    ///     production; host apps may forward this to their own
    ///     telemetry. Once invoked, the SDK will not call the report
    ///     endpoint again for the lifetime of this install — recovery
    ///     requires a fresh `configure(apiKey:)` (typically an app
    ///     relaunch). See ADR-0003 Decision 9.
    ///   - showOnboarding: If `true`, presents a one-time panel on
    ///     first launch that teaches the user the remote trigger
    ///     (hold Play/Pause for 2 seconds). Persisted per install via
    ///     UserDefaults, so the panel never appears twice unless the
    ///     host app calls ``Issuetracker/showOnboarding()`` explicitly.
    ///     With `longPressToReport` disabled the panel is silently
    ///     skipped — there's nothing to teach. Defaults to `false` so
    ///     existing integrators are unaffected. Same semantics as the
    ///     iOS SDK's flag.
    @MainActor
    public static func configure(
        apiKey: String,
        longPressToReport: Bool = true,
        onConfigurationError: ((SdkErrorReason) -> Void)? = nil,
        showOnboarding: Bool = false,
        terminatedUI: TerminatedUiStrings? = nil
    ) {
        let rt = Runtime(
            apiKey: apiKey,
            endpoint: Runtime.resolveEndpoint(for: apiKey),
            onConfigurationError: onConfigurationError,
            terminatedUI: terminatedUI
        )
        runtime = rt
        // Seed remote config (testers-only gating, ADR-0005) from the
        // UserDefaults cache before the observer installs, so the very
        // first press consults real data when we have any. The network
        // refresh runs async below.
        AttestationStore.shared.install(runtime: rt)
        // The remote trigger is gated per-fire rather than at install
        // time: config can flip while the app runs, and a fire-time
        // check reconciles instantly with no uninstall plumbing. In
        // testers-only mode without a token the press is silently
        // inert (ADR-0005 invariant 5). The programmatic report() is
        // deliberately ungated — a host app's own button should
        // surface the attestation message instead.
        if longPressToReport {
            RemotePressObserver.install {
                guard AttestationStore.shared.canTriggerReport else { return }
                Self.report()
            }
        }
        Task { @MainActor in
            await AttestationStore.shared.refreshRemoteConfig(runtime: rt)
            // Onboarding waits for the config refresh so we never
            // advertise a trigger that is gated off for this install —
            // and never wrongly suppress it on a prod key's first
            // launch just because the fail-closed default was still in
            // effect.
            if showOnboarding, AttestationStore.shared.canTriggerReport {
                OnboardingPresenter.presentIfNeeded(
                    longPressEnabled: longPressToReport
                )
            }
        }
    }

    /// Re-presents the onboarding panel regardless of whether it has
    /// been shown before on this install. Intended for a "Show
    /// introduction again"-style row in the host app's own settings
    /// screen. Calling this with the trigger disabled is a no-op —
    /// there is nothing to teach. Must be called after
    /// ``configure(apiKey:longPressToReport:onConfigurationError:showOnboarding:terminatedUI:)``.
    @MainActor
    public static func showOnboarding() {
        guard runtime != nil else {
            assertionFailure("Issuetracker.showOnboarding() called before configure()")
            return
        }
        // The trigger state is re-derived from the installed observer
        // rather than threading another flag through Runtime, so a
        // single source of truth governs both runtime behaviour and
        // onboarding content. Same pattern as sdk-ios.
        OnboardingPresenter.presentForced(
            longPressEnabled: RemotePressObserver.isInstalled
        )
    }

    /// Programmatically triggers the reporter — useful for a "report
    /// a bug" row in your app's settings screen (often the more
    /// discoverable entry point on TV).
    @MainActor
    public static func report() {
        guard let runtime else {
            assertionFailure("Issuetracker.report() called before configure()")
            return
        }
        ReportingSession.present(runtime: runtime)
    }

    /// Sets the display name shown on reports submitted from this
    /// install. Call this if your app already knows who the user is
    /// (e.g. after login) — the SDK will skip the "What should we
    /// call you?" prompt the first time a user triggers a report.
    /// On TV this matters more than on mobile: text entry with the
    /// remote is slow, so pre-identifying spares the user a painful
    /// keyboard round-trip. Safe to call before `configure()`.
    public static func identify(name: String) {
        ReporterIdentity.setName(name)
    }

    /// Clears the stored display name. The next report will re-prompt
    /// the user. The anonymous install ID is preserved so the server
    /// can still group reports from this install.
    public static func clearIdentity() {
        ReporterIdentity.clearName()
    }

    /// Stores a tester attestation token (ADR-0005). On projects in
    /// testers-only mode this is what unlocks the report trigger and
    /// gets reports past the server; in open mode it stamps reports
    /// with the tester's identity. The token normally arrives via the
    /// companion-app enrollment handshake; this API is the manual
    /// injection point until that ships (and for integration tests).
    @MainActor
    public static func setTesterToken(_ token: String, expiresAt: Date? = nil) {
        AttestationStore.shared.setTesterToken(token, expiresAt: expiresAt)
    }

    /// Removes the stored tester token. On testers-only projects the
    /// remote trigger goes inert again from the next press.
    @MainActor
    public static func clearTesterToken() {
        AttestationStore.shared.clearTesterToken()
    }

    /// Records a single user action. The SDK keeps the most recent 5
    /// and attaches them to any report the user submits.
    ///
    /// Safe to call before `configure()` — breadcrumbs are persisted
    /// locally and will be included in the next report.
    ///
    /// - Parameters:
    ///   - action: Short identifier — e.g. `"playback_started"` or
    ///     `"opened_details"`. Truncated to 80 chars.
    ///   - metadata: Optional string:string pairs for richer context.
    ///     Truncated to 5 entries, 64-char keys, 256-char values.
    public static func recordAction(
        _ action: String,
        metadata: [String: String]? = nil
    ) {
        BreadcrumbStore.shared.record(action, metadata: metadata)
    }
}

/// Strings shown when the SDK has been terminated and a test-cohort
/// user opens the reporting surface. ADR-0003 Decision 9 mandates a
/// localised terminal message; English is the built-in default, and
/// host apps may inject translations via ``Issuetracker/configure(apiKey:longPressToReport:onConfigurationError:showOnboarding:terminatedUI:)``.
///
/// Each field is optional — fields the host doesn't override fall
/// back to English. A missing entire struct falls back to all-English.
public struct TerminatedUiStrings: Sendable {
    /// Big headline. Default: `"Bug reporting is no longer available."`
    public let title: String?
    /// One-line follow-up. Default: `"Contact your team."`
    public let subtitle: String?
    /// Close-button label. Default: `"Close"`.
    public let closeLabel: String?

    public init(title: String? = nil, subtitle: String? = nil, closeLabel: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.closeLabel = closeLabel
    }
}

struct Runtime {
    let apiKey: String
    let endpoint: URL
    // Invoked exactly once, on the OK → TERMINATED transition. Stored
    // here (rather than in LifecycleStore) because it's a configure-
    // time setting that the user owns; the store is the state machine.
    let onConfigurationError: ((SdkErrorReason) -> Void)?
    let terminatedUI: TerminatedUiStrings?

    // Routing is derived from the key prefix so integrators never see
    // any URL — they just paste the key the web UI gave them.
    //   it_dev_*      → dev backend (internal use only)
    //   it_staging_*  → staging backend
    //   it_*          → production (brand-domain)
    static func resolveEndpoint(for apiKey: String) -> URL {
        if apiKey.hasPrefix("it_dev_") {
            return URL(string: "https://issuetracker-api-dev.web.app/v1")!
        }
        if apiKey.hasPrefix("it_staging_") {
            return URL(string: "https://issuetracker-api-staging.web.app/v1")!
        }
        return URL(string: "https://api.issuetracker.no/v1")!
    }
}

/// Issue classification sent to the server. Raw values match the
/// server-side `IssueType` enum so we can transmit over the wire as
/// plain strings without depending on the shared schema package.
public enum IssueReportType: String, CaseIterable, Sendable {
    case bug
    case task
    case story

    public var displayName: String {
        switch self {
        case .bug: return "Bug"
        case .task: return "Task"
        case .story: return "Story"
        }
    }

    public var icon: String {
        switch self {
        case .bug: return "ant.fill"
        case .task: return "checkmark.square"
        case .story: return "book.closed"
        }
    }
}
