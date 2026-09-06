import XCTest
@testable import IssuetrackerTVSDK

// ADR-0003 Decision 9 end-to-end contract tests.
//
// The ADR's implementation status says plainly: "integration tests
// against the Firebase callable surface are deferred to a future
// test-infra workstream". This file closes that gap for tvOS by
// driving real server responses through the real transport
// (`APIClient` on `URLSession`, intercepted by a `URLProtocol` stub)
// into the real dispatch site (`AttestationStore.refreshRemoteConfig`)
// and the real state machine (`LifecycleStore`). Nothing here
// re-implements the dispatch rule in the test — that would assert
// only that the test agrees with itself.
//
// Scope note: ADR-0003 Decision 9 enumerates five SDKs and predates
// this repo (ADR dated 2026-05-08; the tvOS SDK landed 2026-08-20).
// `sdk-spec/TV_TRIGGERS.md` is the binding statement for TV:
// "The TERMINATED lifecycle (ADR-0003 Decision 9) and tester
// attestation (ADR-0005) apply on TV exactly as on mobile."
//
// The central rule under test: **dispatch is on `details.error` /
// `details.recoverable`, never on the HTTP status.** Several cases
// below therefore pair a terminal reason with a non-terminal status
// (and vice versa) so a status-sniffing implementation fails.
//
// Sibling suites: sdk-ios, sdk-android, sdk-web/src/lifecycle.test.ts.
@MainActor
final class TerminationContractTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "io.issuetracker.sdk.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        StubURLProtocol.reset()
        URLProtocol.registerClass(StubURLProtocol.self)
    }

    override func tearDown() async throws {
        URLProtocol.unregisterClass(StubURLProtocol.self)
        StubURLProtocol.reset()
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    // MARK: - Fixtures

    /// Every reason the server may send, with the HTTP status ADR-0003
    /// Decision 9 maps it to, and whether it must flip the SDK into
    /// one-way TERMINATED.
    private static let contract: [(reason: String, status: Int, terminal: Bool)] = [
        ("project_deleted", 404, true),
        ("project_not_found", 404, true),
        ("api_key_revoked", 403, true),
        ("workspace_suspended", 403, true),
        ("invalid_api_key", 401, true),
        ("quota_exceeded", 429, false),
        ("transient", 503, false),
        // ADR-0005: non-recoverable but explicitly NOT terminal.
        ("tester_attestation_required", 403, false),
        ("tester_token_invalid", 403, false),
    ]

    private func runtime(
        apiKey: String = "it_dev_contracttests",
        onConfigurationError: ((SdkErrorReason) -> Void)? = nil
    ) -> Runtime {
        Runtime(
            apiKey: apiKey,
            endpoint: URL(string: "https://stub.invalid/v1")!,
            onConfigurationError: onConfigurationError,
            terminatedUI: nil
        )
    }

    /// Firebase callable error envelope, as the SDK sees it on the wire.
    private func callableErrorBody(
        reason: String,
        recoverable: Bool,
        extra: [String: Any] = [:]
    ) -> Data {
        var details: [String: Any] = ["error": reason, "recoverable": recoverable]
        details.merge(extra) { _, new in new }
        let body: [String: Any] = [
            "error": [
                "message": "server said \(reason)",
                "status": "FAILED_PRECONDITION",
                "details": details,
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    private func stub(status: Int, body: Data) {
        StubURLProtocol.handler = { _ in .success((status, body)) }
    }

    // MARK: - Wire parsing: details, not status

    func testTerminalReasonIsReadFromDetailsEvenOnANonTerminalStatus() async {
        // A status-sniffing SDK sees 429 and backs off forever. The
        // contract says `details.error` decides: this is terminal.
        stub(
            status: 429,
            body: callableErrorBody(reason: "project_deleted", recoverable: false)
        )
        let err = await expectCallableError()
        XCTAssertEqual(err?.status, 429)
        XCTAssertEqual(err?.sdkErrorReason, .projectDeleted)
        XCTAssertEqual(err?.sdkErrorReason?.isTerminal, true)
    }

    func testRecoverableReasonIsReadFromDetailsEvenOnATerminalLookingStatus() async {
        // The mirror image: 404 looks like project_deleted to a
        // status-sniffer, but the payload says quota. Must NOT be
        // terminal.
        stub(
            status: 404,
            body: callableErrorBody(reason: "quota_exceeded", recoverable: true)
        )
        let err = await expectCallableError()
        XCTAssertEqual(err?.status, 404)
        XCTAssertEqual(err?.sdkErrorReason, .quotaExceeded)
        XCTAssertEqual(err?.sdkErrorReason?.isTerminal, false)
    }

    func testEveryContractReasonParsesOffTheWireWithItsMandatedStatus() async {
        for entry in Self.contract {
            stub(
                status: entry.status,
                body: callableErrorBody(
                    reason: entry.reason,
                    recoverable: !entry.terminal && entry.reason != "tester_attestation_required"
                        && entry.reason != "tester_token_invalid"
                )
            )
            let err = await expectCallableError()
            XCTAssertEqual(
                err?.sdkErrorReason?.rawValue, entry.reason,
                "wire value \(entry.reason) did not round-trip"
            )
            XCTAssertEqual(
                err?.sdkErrorReason?.isTerminal, entry.terminal,
                "terminality of \(entry.reason) diverged from ADR-0003 Decision 9"
            )
        }
    }

    func testProjectDeletedCarriesDeletedAtOffTheWire() async {
        let millis: Double = 1_747_000_000_000
        stub(
            status: 404,
            body: callableErrorBody(
                reason: "project_deleted",
                recoverable: false,
                extra: ["deletedAt": millis]
            )
        )
        let err = await expectCallableError()
        XCTAssertEqual(
            err?.details?.deletedAt?.timeIntervalSince1970 ?? 0,
            millis / 1000,
            accuracy: 0.001
        )
    }

    func testQuotaExceededCarriesRetryAfterSecondsOffTheWire() async {
        stub(
            status: 429,
            body: callableErrorBody(
                reason: "quota_exceeded",
                recoverable: true,
                extra: ["retryAfterSeconds": 30]
            )
        )
        let err = await expectCallableError()
        XCTAssertEqual(err?.details?.retryAfterSeconds, 30)
    }

    func testErrorEnvelopeWithoutDetailsYieldsNoTypedReason() async {
        // Legacy / non-SDK callables send no `details`. The SDK must
        // degrade to a plain error rather than guessing from the 404.
        let body = try! JSONSerialization.data(withJSONObject: [
            "error": ["message": "not found", "status": "NOT_FOUND"],
        ])
        stub(status: 404, body: body)
        let err = await expectCallableError()
        XCTAssertEqual(err?.status, 404)
        XCTAssertNil(err?.sdkErrorReason)
    }

    // MARK: - Dispatch: config fetch → lifecycle transition

    func testEveryNonRecoverableReasonTerminatesViaTheConfigFetch() async {
        for entry in Self.contract where entry.terminal {
            let scratch = UserDefaults(suiteName: "\(suiteName!).\(entry.reason)")!
            defer { scratch.removePersistentDomain(forName: "\(suiteName!).\(entry.reason)") }

            let lifecycle = LifecycleStore(defaults: scratch)
            let store = AttestationStore(defaults: scratch, lifecycle: lifecycle)
            var received: [SdkErrorReason] = []

            stub(
                status: entry.status,
                body: callableErrorBody(reason: entry.reason, recoverable: false)
            )
            await store.refreshRemoteConfig(
                runtime: runtime(onConfigurationError: { received.append($0) })
            )

            XCTAssertTrue(
                lifecycle.isTerminated,
                "\(entry.reason) must transition the SDK to TERMINATED"
            )
            XCTAssertEqual(
                received.map(\.rawValue), [entry.reason],
                "onConfigurationError must fire exactly once, with \(entry.reason)"
            )
            XCTAssertEqual(
                scratch.string(forKey: "io.issuetracker.sdk.terminatedReason"), entry.reason,
                "\(entry.reason) must be persisted, not just held in memory"
            )
        }
    }

    func testQuotaExceededDoesNotTerminate() async {
        let lifecycle = LifecycleStore(defaults: defaults)
        let store = AttestationStore(defaults: defaults, lifecycle: lifecycle)
        var received: [SdkErrorReason] = []

        stub(
            status: 429,
            body: callableErrorBody(
                reason: "quota_exceeded",
                recoverable: true,
                extra: ["retryAfterSeconds": 30]
            )
        )
        await store.refreshRemoteConfig(
            runtime: runtime(onConfigurationError: { received.append($0) })
        )

        XCTAssertFalse(lifecycle.isTerminated)
        XCTAssertTrue(received.isEmpty)
        XCTAssertNil(defaults.string(forKey: "io.issuetracker.sdk.terminatedReason"))
    }

    func testTransientDoesNotTerminate() async {
        let lifecycle = LifecycleStore(defaults: defaults)
        let store = AttestationStore(defaults: defaults, lifecycle: lifecycle)

        stub(status: 503, body: callableErrorBody(reason: "transient", recoverable: true))
        await store.refreshRemoteConfig(runtime: runtime())

        XCTAssertFalse(lifecycle.isTerminated)
    }

    func testTesterGatingReasonsDoNotTerminate() async {
        // ADR-0005: the project is alive and the key is valid; only
        // this install lacks attestation. Terminating here would brick
        // a healthy integration.
        for reason in ["tester_attestation_required", "tester_token_invalid"] {
            let lifecycle = LifecycleStore(defaults: defaults)
            let store = AttestationStore(defaults: defaults, lifecycle: lifecycle)

            stub(status: 403, body: callableErrorBody(reason: reason, recoverable: false))
            await store.refreshRemoteConfig(runtime: runtime())

            XCTAssertFalse(lifecycle.isTerminated, "\(reason) must not be terminal")
        }
    }

    func testNetworkFailureDoesNotTerminate() async {
        // Offline is not "your project is gone". A deployed cohort on a
        // flaky network must never latch into the one-way state.
        let lifecycle = LifecycleStore(defaults: defaults)
        let store = AttestationStore(defaults: defaults, lifecycle: lifecycle)

        StubURLProtocol.handler = { _ in .failure(URLError(.notConnectedToInternet)) }
        await store.refreshRemoteConfig(runtime: runtime())

        XCTAssertFalse(lifecycle.isTerminated)
    }

    func testUnparseableErrorBodyDoesNotTerminate() async {
        let lifecycle = LifecycleStore(defaults: defaults)
        let store = AttestationStore(defaults: defaults, lifecycle: lifecycle)

        stub(status: 500, body: Data("<html>gateway error</html>".utf8))
        await store.refreshRemoteConfig(runtime: runtime())

        XCTAssertFalse(lifecycle.isTerminated)
    }

    // MARK: - Persistence and one-wayness

    func testTerminatedSurvivesASimulatedProcessRestart() async {
        // The invariant no manual test exercises. Terminate through the
        // real network path, then throw the store away and rebuild it
        // over the same on-disk defaults — that is what app relaunch
        // does.
        let first = LifecycleStore(defaults: defaults)
        let store = AttestationStore(defaults: defaults, lifecycle: first)
        stub(status: 404, body: callableErrorBody(reason: "project_deleted", recoverable: false))
        await store.refreshRemoteConfig(runtime: runtime())
        XCTAssertTrue(first.isTerminated)

        let afterRelaunch = LifecycleStore(defaults: defaults)
        XCTAssertTrue(afterRelaunch.isTerminated, "TERMINATED must survive a process restart")
    }

    func testCallbackDoesNotRefireOnEveryRelaunch() async {
        // onConfigurationError is a transition callback, not a state
        // callback. A host forwarding it to Sentry must not receive one
        // event per app launch for the rest of the install's life.
        let first = LifecycleStore(defaults: defaults)
        first.transitionToTerminated(reason: .apiKeyRevoked, callback: nil)

        var fired = 0
        let afterRelaunch = LifecycleStore(defaults: defaults)
        afterRelaunch.transitionToTerminated(reason: .apiKeyRevoked, callback: { _ in fired += 1 })
        XCTAssertEqual(fired, 0)
    }

    func testTerminationIsOneWayAcrossALaterSuccessfulCall() async {
        // Project restored inside the 30-day window, or a server-side
        // blip. ADR-0003:147 — a TERMINATED SDK never returns to OK on
        // its own, and specifically not by polling until it gets a 200.
        let lifecycle = LifecycleStore(defaults: defaults)
        let store = AttestationStore(defaults: defaults, lifecycle: lifecycle)

        stub(status: 404, body: callableErrorBody(reason: "project_deleted", recoverable: false))
        await store.refreshRemoteConfig(runtime: runtime())
        XCTAssertTrue(lifecycle.isTerminated)

        let ok = try! JSONSerialization.data(withJSONObject: [
            "result": ["requireTesterAttestation": false],
        ])
        stub(status: 200, body: ok)
        await store.refreshRemoteConfig(runtime: runtime())

        XCTAssertTrue(lifecycle.isTerminated, "a 200 must not resurrect a TERMINATED SDK")
        XCTAssertEqual(
            defaults.string(forKey: "io.issuetracker.sdk.terminatedReason"), "project_deleted"
        )
    }

    func testTerminationIsOneWayAcrossAReconfigureWithADifferentApiKey() async {
        // configure() may be called again with a new key. The lifecycle
        // marker is not key-scoped (unlike the attestation cache), so
        // termination is per install and outlives the key that caused
        // it. Recorded here because it is the behaviour most likely to
        // be reported as a bug; see the audit note on LifecycleStore's
        // un-scoped defaults keys.
        let lifecycle = LifecycleStore(defaults: defaults)
        let store = AttestationStore(defaults: defaults, lifecycle: lifecycle)

        stub(status: 403, body: callableErrorBody(reason: "api_key_revoked", recoverable: false))
        await store.refreshRemoteConfig(runtime: runtime(apiKey: "it_dev_oldkey"))
        XCTAssertTrue(lifecycle.isTerminated)

        let reconfigured = AttestationStore(defaults: defaults, lifecycle: lifecycle)
        reconfigured.install(runtime: runtime(apiKey: "it_dev_brandnewkey"))
        XCTAssertTrue(lifecycle.isTerminated)
        XCTAssertTrue(LifecycleStore(defaults: defaults).isTerminated)
    }

    func testTerminationSurvivesAClockChange() {
        // `terminatedAt` is diagnostic only — nothing may gate on it.
        // A device whose clock jumps backwards past the marker (or
        // forwards past any plausible expiry) stays terminated.
        for stamp in [0.0, -1.0, 1.0, 4_102_444_800.0] {
            let scratch = UserDefaults(suiteName: "\(suiteName!).clock\(stamp)")!
            defer { scratch.removePersistentDomain(forName: "\(suiteName!).clock\(stamp)") }
            scratch.set("workspace_suspended", forKey: "io.issuetracker.sdk.terminatedReason")
            scratch.set(stamp, forKey: "io.issuetracker.sdk.terminatedAt")
            XCTAssertTrue(
                LifecycleStore(defaults: scratch).isTerminated,
                "clock value \(stamp) must not un-terminate the SDK"
            )
        }
    }

    func testTerminatedRehydratesEvenWithNoTimestampAtAll() {
        // Half-written marker (process killed between the two
        // UserDefaults writes). The reason alone must be enough — the
        // fail-safe direction is "stay terminated".
        defaults.set("invalid_api_key", forKey: "io.issuetracker.sdk.terminatedReason")
        XCTAssertTrue(LifecycleStore(defaults: defaults).isTerminated)
    }

    // MARK: - Queue and credential purge (ADR-0003 Decision 9 §6)

    func testNoReportSurvivesTerminationBecauseThereIsNoOfflineQueue() {
        // tvOS deliberately ships no offline report queue: a submit is
        // in-session only (`ReportingSession.submit` fires one request
        // and surfaces failure to the user), so §6's "drop the queue
        // atomically" is satisfied by construction rather than by code.
        // This test pins that structural fact — if a queue is ever
        // added, it must be purged on the terminal transition and this
        // test must be replaced, not deleted.
        let sdkFiles = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            .map { $0.appendingPathComponent("Issuetracker", isDirectory: true) }
            .flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
        XCTAssertFalse(
            sdkFiles.contains { $0.lowercased().contains("queue") },
            "an on-disk report queue appeared; ADR-0003 Decision 9 §6 now needs a purge on terminate"
        )
    }

    func testTerminationDoesNotPurgeThePersistedTesterToken_KNOWN_GAP() async {
        // GAP (audit finding): the `itt_` tester token is a live ingest
        // credential for the very project the server has just declared
        // deleted / revoked / suspended, and it outlives termination in
        // UserDefaults. ADR-0003 Decision 9 §6's intent is that no
        // report-bearing state survives the terminal signal.
        //
        // This asserts CURRENT behaviour so the gap is executable. When
        // `transitionToTerminated` learns to purge, invert it.
        let lifecycle = LifecycleStore(defaults: defaults)
        let store = AttestationStore(defaults: defaults, lifecycle: lifecycle)
        store.setTesterToken("itt_livecredential", expiresAt: nil)

        stub(status: 403, body: callableErrorBody(reason: "workspace_suspended", recoverable: false))
        await store.refreshRemoteConfig(runtime: runtime())

        XCTAssertTrue(lifecycle.isTerminated)
        XCTAssertEqual(
            store.testerToken, "itt_livecredential",
            "documents the un-purged credential; flip this assertion when the gap is closed"
        )
    }

    func testTerminatedSdkStillCallsTheConfigEndpointOnRelaunch_KNOWN_GAP() async {
        // GAP (audit finding): ADR-0005 states the invariant outright —
        // "a TERMINATED SDK never attempts attestation" — and ADR-0003
        // Decision 9 §2 requires TERMINATED to disable all background
        // tasks. `Issuetracker.configure()` calls
        // `refreshRemoteConfig` unconditionally, and
        // `refreshRemoteConfig` has no `isTerminated` guard, so every
        // terminated install hits `getSdkConfig` once per app launch,
        // forever. That is precisely the deployed-cohort hammering
        // Decision 9 exists to cap.
        //
        // Asserts CURRENT behaviour. When the guard lands, this becomes
        // `XCTAssertEqual(StubURLProtocol.requestCount, before)`.
        let lifecycle = LifecycleStore(defaults: defaults)
        lifecycle.transitionToTerminated(reason: .projectDeleted, callback: nil)

        let afterRelaunch = LifecycleStore(defaults: defaults)
        XCTAssertTrue(afterRelaunch.isTerminated)

        let store = AttestationStore(defaults: defaults, lifecycle: afterRelaunch)
        stub(status: 200, body: try! JSONSerialization.data(withJSONObject: [
            "result": ["requireTesterAttestation": false],
        ]))
        let before = StubURLProtocol.requestCount
        await store.refreshRemoteConfig(runtime: runtime())

        XCTAssertEqual(
            StubURLProtocol.requestCount, before + 1,
            "documents the un-gated config fetch; assert no-increment once TERMINATED gates it"
        )
    }

    // MARK: - Helpers

    /// Drives a real `APIClient` call through the stub and returns the
    /// `CallableError` it threw.
    private func expectCallableError(
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> APIClient.CallableError? {
        struct Ignored: Decodable {}
        do {
            let _: Ignored = try await APIClient.call(
                endpoint: URL(string: "https://stub.invalid/v1")!,
                function: "createIssueFromSdk",
                payload: ["apiKey": "it_dev_contracttests"]
            )
            XCTFail("expected the call to throw", file: file, line: line)
            return nil
        } catch let err as APIClient.CallableError {
            return err
        } catch {
            XCTFail("expected CallableError, got \(error)", file: file, line: line)
            return nil
        }
    }
}

// MARK: - URLProtocol stub

/// Intercepts `URLSession.shared` and `.default`-configured sessions so
/// the SDK's real transport runs against scripted server responses.
final class StubURLProtocol: URLProtocol {
    typealias Scripted = (status: Int, body: Data)

    private static let lock = NSLock()
    private static var _handler: ((URLRequest) -> Result<Scripted, Error>)?
    private static var _requestCount = 0

    static var handler: ((URLRequest) -> Result<Scripted, Error>)? {
        get { lock.lock(); defer { lock.unlock() }; return _handler }
        set { lock.lock(); _handler = newValue; lock.unlock() }
    }

    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }; return _requestCount
    }

    static func reset() {
        lock.lock()
        _handler = nil
        _requestCount = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self._requestCount += 1
        let handler = Self._handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        switch handler(request) {
        case let .success(scripted):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: scripted.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: scripted.body)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
