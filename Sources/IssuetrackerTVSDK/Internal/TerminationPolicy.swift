import Foundation

/// The single termination predicate for this platform (ITD-163).
///
/// ADR-0003 Decision 9 requires every dispatch site in an SDK to decide
/// terminality the same way. There are exactly two on tvOS — the config
/// fetch (``AttestationStore/refreshRemoteConfig(runtime:)``) and the
/// submit path (`ReportingSession.submit`) — and both go through here,
/// so they cannot drift apart the way `sdk-web`'s two paths did.
///
/// The rule is the reason, never the transport and never
/// `details.recoverable`: ADR-0005's tester-gating reasons
/// (`tester_attestation_required`, `tester_token_invalid`) are
/// `recoverable: false` but deliberately NOT terminal — the project is
/// alive and the key is valid, only this install lacks attestation.
/// Dispatching on recoverability would permanently brick a healthy
/// integration. The HTTP status is not consulted either: the server may
/// pair a terminal reason with a 429 (Decision 9 §1).
///
/// Swift spells the predicate ``SdkErrorReason/isTerminal``, matching
/// sdk-ios; the wire values are the shared `SdkErrorReasonSchema`.
enum TerminationPolicy {
    /// The reason to terminate on, or `nil` to stay in the current
    /// state. `nil` for every non-callable error too — offline is not
    /// "your project is gone".
    static func terminalReason(for error: Error) -> SdkErrorReason? {
        guard
            let callable = error as? APIClient.CallableError,
            let reason = callable.sdkErrorReason,
            reason.isTerminal
        else {
            return nil
        }
        return reason
    }
}
