import Foundation

/// One-way SDK lifecycle state. See ADR-0003 Decision 9.
///
/// Starts in ``State/ok``. The first non-recoverable server error
/// transitions to ``State/terminated`` and the SDK stays there for
/// the lifetime of the install — recovery requires an explicit
/// host-app re-init, never a poll, so a deployed cohort cannot
/// hammer a dead endpoint regardless of scale.
///
/// ``State/suspended`` is reserved for a future per-report retry
/// queue (Phase B+/C) and is not produced today; recoverable
/// errors keep the SDK in ``State/ok`` and rely on the user
/// retrying via the existing UI.
@MainActor
final class LifecycleStore {
    static let shared = LifecycleStore()

    enum State: Sendable {
        case ok
        case suspended
        case terminated(reason: SdkErrorReason, at: Date)
    }

    private(set) var state: State

    private let defaults: UserDefaults
    private let reasonKey = "io.issuetracker.sdk.terminatedReason"
    private let atKey = "io.issuetracker.sdk.terminatedAt"

    // ADR-0003 Decision 9 §6: report-bearing local state is dropped on
    // the terminal signal. The state itself lives in the stores that
    // own it (attestation token, breadcrumbs), so each registers a
    // purge here rather than this type reaching into process-wide
    // singletons — which would also make the injectable test stores
    // clobber production state. Keyed so a repeated `configure()`
    // replaces its handler instead of stacking another copy.
    private var purgeHandlers: [String: () -> Void] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Restore from disk so a process restart doesn't re-attempt
        // delivery against an endpoint the server has already told us
        // is gone.
        if let raw = defaults.string(forKey: reasonKey),
           let reason = SdkErrorReason(rawValue: raw) {
            let at = defaults.double(forKey: atKey)
            self.state = .terminated(
                reason: reason,
                at: Date(timeIntervalSince1970: at)
            )
        } else {
            self.state = .ok
        }
    }

    var isTerminated: Bool {
        if case .terminated = state { return true }
        return false
    }

    /// Registers a purge of report-bearing local state, run inside the
    /// OK → TERMINATED transition (ADR-0003 Decision 9 §6).
    ///
    /// The handler also runs immediately when the store is *already*
    /// terminated. That covers the launch after a purge that never
    /// finished — the process was killed between the marker write and
    /// the purge — so the fail-safe direction is "terminated, and the
    /// state is gone" rather than "terminated, credential retained".
    /// Handlers must therefore be idempotent.
    func onTerminate(id: String, purge: @escaping () -> Void) {
        purgeHandlers[id] = purge
        if isTerminated { purge() }
    }

    /// Idempotent: re-terminating with a different reason keeps the
    /// first one. The first non-recoverable failure is authoritative;
    /// later failures should have been gated and only happen if a
    /// pre-flight check missed the state.
    func transitionToTerminated(
        reason: SdkErrorReason,
        callback: ((SdkErrorReason) -> Void)?
    ) {
        guard !isTerminated else { return }
        let now = Date()
        state = .terminated(reason: reason, at: now)
        // Marker before purge: if the process dies mid-transition the
        // next launch must still come up TERMINATED (and `onTerminate`
        // re-runs the purge then).
        defaults.set(reason.rawValue, forKey: reasonKey)
        defaults.set(now.timeIntervalSince1970, forKey: atKey)
        for purge in purgeHandlers.values { purge() }
        // Host callback last, so anything it inspects already reflects
        // the purged state.
        callback?(reason)
    }
}
