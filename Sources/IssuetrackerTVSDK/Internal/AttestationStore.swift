import Foundation

/// Tester attestation + remote config (ADR-0005). The server owns one
/// flag today — `requireTesterAttestation` — which decides whether the
/// report trigger works for everyone (open mode) or only on installs
/// holding a valid tester token (testers-only mode).
///
/// Fail-mode (ADR-0005 Decision 4): the last cached value wins when
/// the config fetch fails. With no cache at all, prod-prefixed keys
/// fail CLOSED (trigger inert until the first successful fetch says
/// open) and dev/staging-prefixed keys fail OPEN. Conservative where
/// real end users are, frictionless where people develop and QA.
///
/// The token itself arrives from the companion-app handshake (phase
/// 2); until that lands, hosts can inject one programmatically via
/// ``Issuetracker/setTesterToken(_:expiresAt:)``.
@MainActor
final class AttestationStore {
    static let shared = AttestationStore()

    private let defaults: UserDefaults
    // Injected for the same reason `defaults` is: `LifecycleStore` is a
    // one-way state machine on a process-wide singleton, so a test that
    // exercised the real termination path against `.shared` would
    // poison every test that ran after it. Production always gets
    // `.shared` via the default argument.
    private let lifecycle: LifecycleStore
    private let configApiKeyKey = "io.issuetracker.sdk.remoteConfig.apiKey"
    private let configRequireKey = "io.issuetracker.sdk.remoteConfig.requireTesterAttestation"
    private let tokenKey = "io.issuetracker.sdk.testerToken"
    private let tokenExpiresKey = "io.issuetracker.sdk.testerTokenExpiresAt"
    // ADR-0005 Decision 9: the token slot is apiKey-bound, mirroring
    // the config cache line for line. Without this a token minted for
    // one project survives a reconfigure onto another and gets
    // attached to reports it has no business attesting — which the
    // server rejects, so the visible symptom is a tester whose
    // trigger works and whose reports silently fail.
    private let tokenApiKeyKey = "io.issuetracker.sdk.testerTokenApiKey"

    private var currentApiKey: String?
    // nil = no fetched/cached value for the current key; fall back to
    // the per-prefix fail-mode default.
    private var known: Bool?

    // `lifecycle` defaults to nil rather than to `.shared` directly:
    // default-argument expressions are evaluated in a nonisolated
    // context, and `LifecycleStore.shared` is @MainActor.
    init(defaults: UserDefaults = .standard, lifecycle: LifecycleStore? = nil) {
        self.defaults = defaults
        self.lifecycle = lifecycle ?? .shared
        // ADR-0003 Decision 9 §6. tvOS ships no offline report queue,
        // but the tester token is report-bearing state all the same: a
        // live ingest credential for the very project the server has
        // just declared deleted / revoked / suspended. It goes with the
        // (empty) queue on the terminal signal, and on any later launch
        // that finds the marker already set.
        self.lifecycle.onTerminate(id: "attestation") { [weak self] in
            self?.clearTesterToken()
        }
    }

    /// Synchronous part of configure(): seed the in-memory value from
    /// the cache so the very first trigger fires against real data
    /// when we have any. The caller kicks the async refresh.
    func install(runtime: Runtime) {
        currentApiKey = runtime.apiKey
        if defaults.string(forKey: configApiKeyKey) == runtime.apiKey,
           defaults.object(forKey: configRequireKey) != nil {
            known = defaults.bool(forKey: configRequireKey)
        } else {
            // Reconfigured with a different key — a cached flag for the
            // old key must not leak onto the new project.
            known = nil
        }
        bindToken(apiKey: runtime.apiKey)
    }

    /// Resolves the stored token against the key now in force
    /// (ADR-0005 Decision 9).
    ///
    /// A token written BEFORE `configure()` — which
    /// ``Issuetracker/setTesterToken(_:expiresAt:)`` permits — is
    /// stored unbound and adopted here. A token bound to a different
    /// key is cleared, never carried forward.
    ///
    /// tvOS has no companion app and never will (ADR-0005 Decision
    /// 11), so every token here arrives through the host app. That
    /// makes the unbound-adopt case the common one rather than the
    /// exception it is on iOS.
    func bindToken(apiKey: String) {
        guard defaults.string(forKey: tokenKey) != nil else { return }
        switch defaults.string(forKey: tokenApiKeyKey) {
        case apiKey:
            break
        case nil:
            defaults.set(apiKey, forKey: tokenApiKeyKey)
        default:
            clearTesterToken()
        }
    }

    func refreshRemoteConfig(runtime: Runtime) async {
        // ADR-0003 Decision 9 §2: TERMINATED disables all background
        // tasks; ADR-0005 states it for this call specifically ("a
        // TERMINATED SDK never attempts attestation"). Without this
        // gate every terminated install POSTs `getSdkConfig` once per
        // app launch, forever, across an unbounded deployed cohort —
        // the exact hammering Decision 9 exists to cap, and invisible
        // because it happens in the background.
        //
        // The gate is on TERMINATED and nothing else: a healthy SDK
        // still refreshes on every launch, and a SUSPENDED /
        // tester-gated one still re-pulls config after a rejection.
        guard !lifecycle.isTerminated else { return }

        struct ConfigResult: Decodable { let requireTesterAttestation: Bool }
        do {
            let result: ConfigResult = try await APIClient.call(
                endpoint: runtime.endpoint,
                function: "getSdkConfig",
                payload: ["apiKey": runtime.apiKey]
            )
            adopt(requireTesterAttestation: result.requireTesterAttestation, apiKey: runtime.apiKey)
        } catch {
            // A terminal signal on the config fetch (key revoked,
            // project deleted, …) is as authoritative as one on
            // submission — flip to TERMINATED here too so a dead
            // cohort stops before it ever reaches the report endpoint.
            // Anything else (offline, transient, tester-gating) leaves
            // the cached / fail-mode value in charge.
            //
            // Same predicate as the submit path, by construction
            // (ITD-163) — see ``TerminationPolicy``.
            if let reason = TerminationPolicy.terminalReason(for: error) {
                lifecycle.transitionToTerminated(
                    reason: reason,
                    callback: runtime.onConfigurationError
                )
            }
        }
    }

    /// Internal seam for tests and for refreshRemoteConfig.
    func adopt(requireTesterAttestation: Bool, apiKey: String) {
        known = requireTesterAttestation
        defaults.set(apiKey, forKey: configApiKeyKey)
        defaults.set(requireTesterAttestation, forKey: configRequireKey)
    }

    /// The assumed `requireTesterAttestation` value with no data at
    /// all. Prod keys are exactly the ones without an env infix.
    nonisolated static func failModeDefault(for apiKey: String) -> Bool {
        !apiKey.hasPrefix("it_dev_") && !apiKey.hasPrefix("it_staging_")
    }

    private var requireAttestation: Bool {
        if let known { return known }
        guard let currentApiKey else { return false } // not configured yet
        return Self.failModeDefault(for: currentApiKey)
    }

    /// Valid (non-expired) tester token, or nil.
    ///
    /// The expiry rule is unified across all four SDK stores
    /// (ADR-0005 Decision 10): **absent or `<= 0` means no local
    /// expiry; a positive expiry in the past means treat as absent
    /// AND clear.** This store previously read a stored `0` as
    /// `Date(timeIntervalSince1970: 0)` — 1970, therefore expired —
    /// which is the opposite of what Android and web have always done
    /// with the same value.
    ///
    /// The clear is a write from a getter, which is unusual enough to
    /// justify: it is the only self-healing path for a stale token.
    /// Without it an expired token sits on disk forever, keeps being
    /// attached to reports, and keeps being rejected — and the
    /// renew-on-use extension that would have prevented the expiry
    /// only fires on a token the server still accepts.
    var testerToken: String? {
        guard let token = defaults.string(forKey: tokenKey) else { return nil }
        if let expires = defaults.object(forKey: tokenExpiresKey) as? Double,
           expires > 0,
           expires <= Date().timeIntervalSince1970 {
            clearTesterToken()
            return nil
        }
        return token
    }

    func setTesterToken(_ token: String, expiresAt: Date?) {
        // Storing an ingest credential on a terminated install would
        // re-create exactly the state the purge just removed — the host
        // app's companion handshake has no way of knowing the SDK is
        // dead. Silently ignored (ADR-0003 Decision 9 §6).
        guard !lifecycle.isTerminated else { return }
        defaults.set(token, forKey: tokenKey)
        // Bound when a key is in force, unbound when the host called
        // this before `configure()`. An unbound token is adopted by
        // the next `install(runtime:)`.
        if let currentApiKey {
            defaults.set(currentApiKey, forKey: tokenApiKeyKey)
        } else {
            defaults.removeObject(forKey: tokenApiKeyKey)
        }
        if let expiresAt {
            defaults.set(expiresAt.timeIntervalSince1970, forKey: tokenExpiresKey)
        } else {
            defaults.removeObject(forKey: tokenExpiresKey)
        }
    }

    /// Adopts a server-extended expiry (renew-on-use, ADR-0005
    /// Decision 10). The server slides `expiresAt` out on any use
    /// inside the renewal window and hands the new value back on the
    /// ingest response; a client that ignored it would keep its old
    /// expiry and treat a live token as dead.
    ///
    /// This matters more on tvOS than anywhere else: there is no
    /// companion app to re-mint from, so a token that is allowed to
    /// lapse can only be replaced by the host app calling
    /// `setTesterToken` again.
    ///
    /// Only ever moves the expiry FORWARD, and only for a token that
    /// is still there: a response arriving after a purge or a
    /// reconfigure must not resurrect a slot that was cleared.
    func adoptRenewedExpiry(millisecondsSince1970 ms: Double) {
        guard ms > 0, defaults.string(forKey: tokenKey) != nil else { return }
        let seconds = ms / 1000
        let current = defaults.object(forKey: tokenExpiresKey) as? Double
        guard current == nil || seconds > (current ?? 0) else { return }
        defaults.set(seconds, forKey: tokenExpiresKey)
    }

    func clearTesterToken() {
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: tokenExpiresKey)
        defaults.removeObject(forKey: tokenApiKeyKey)
    }

    /// Remote-trigger gate. In testers-only mode without a token the
    /// trigger is silently inert — no UI, no hint the SDK exists
    /// (ADR-0005 invariant 5). The programmatic `report()` path is
    /// deliberately NOT gated on this: a host app's own "report a
    /// bug" row should surface the attestation error message rather
    /// than dying silently.
    var canTriggerReport: Bool {
        if !requireAttestation { return true }
        return testerToken != nil
    }
}
