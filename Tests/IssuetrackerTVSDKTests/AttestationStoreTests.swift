import XCTest
@testable import IssuetrackerTVSDK

// AttestationStore is a singleton in production, but exposes an
// internal init that takes UserDefaults so tests can run against a
// throwaway suite for isolation. Must stay in lockstep with the
// sdk-ios suite and sdk-web/src/attestation.test.ts.
@MainActor
final class AttestationStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "io.issuetracker.sdk.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    private func runtime(apiKey: String) -> Runtime {
        Runtime(
            apiKey: apiKey,
            endpoint: URL(string: "https://example.invalid/v1")!,
            onConfigurationError: nil,
            terminatedUI: nil
        )
    }

    func testFailsClosedForProdKeysWithNoCache() {
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_abcdef1234567890"))
        XCTAssertFalse(store.canTriggerReport)
    }

    func testFailsOpenForDevAndStagingKeys() {
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_dev_abcdef1234567890"))
        XCTAssertTrue(store.canTriggerReport)

        store.install(runtime: runtime(apiKey: "it_staging_abcdef1234567890"))
        XCTAssertTrue(store.canTriggerReport)
    }

    func testPrefersCachedConfigOverFailModeDefault() {
        let seeded = AttestationStore(defaults: defaults)
        seeded.adopt(requireTesterAttestation: false, apiKey: "it_abcdef1234567890")

        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_abcdef1234567890"))
        XCTAssertTrue(store.canTriggerReport)
    }

    func testIgnoresCachedConfigForDifferentKey() {
        let seeded = AttestationStore(defaults: defaults)
        seeded.adopt(requireTesterAttestation: false, apiKey: "it_otherkey")

        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_abcdef1234567890"))
        XCTAssertFalse(store.canTriggerReport)
    }

    func testAdoptedServerValueBeatsFailOpenDefault() {
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_dev_abcdef1234567890"))
        XCTAssertTrue(store.canTriggerReport)
        store.adopt(requireTesterAttestation: true, apiKey: "it_dev_abcdef1234567890")
        XCTAssertFalse(store.canTriggerReport)
    }

    func testTokenUnlocksTestersOnlyMode() {
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_abcdef1234567890"))
        XCTAssertFalse(store.canTriggerReport)

        store.setTesterToken("itt_sometoken", expiresAt: nil)
        XCTAssertTrue(store.canTriggerReport)

        store.clearTesterToken()
        XCTAssertFalse(store.canTriggerReport)
    }

    func testExpiredTokenIsTreatedAsAbsent() {
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_abcdef1234567890"))
        store.setTesterToken("itt_sometoken", expiresAt: Date(timeIntervalSinceNow: -1))
        XCTAssertNil(store.testerToken)
        XCTAssertFalse(store.canTriggerReport)
    }

    func testFutureExpiryIsHonoured() {
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_abcdef1234567890"))
        store.setTesterToken("itt_sometoken", expiresAt: Date(timeIntervalSinceNow: 60))
        XCTAssertEqual(store.testerToken, "itt_sometoken")
    }

    func testFailModeDefaultPerPrefix() {
        XCTAssertTrue(AttestationStore.failModeDefault(for: "it_abc"))
        XCTAssertFalse(AttestationStore.failModeDefault(for: "it_dev_abc"))
        XCTAssertFalse(AttestationStore.failModeDefault(for: "it_staging_abc"))
    }

    // MARK: - apiKey binding (ADR-0005 Decision 9)

    func testATokenSetBeforeConfigureIsAdoptedByTheFirstConfigure() {
        // On tvOS this is the COMMON case, not the exception: there is
        // no companion app, so every token arrives through the host,
        // and a host that sets one at launch may well beat configure().
        let store = AttestationStore(defaults: defaults)
        store.setTesterToken("itt_injected", expiresAt: nil)
        store.install(runtime: runtime(apiKey: "it_dev_abcdef1234"))
        store.adopt(requireTesterAttestation: true, apiKey: "it_dev_abcdef1234")
        XCTAssertEqual(store.testerToken, "itt_injected")
        XCTAssertTrue(store.canTriggerReport)
    }

    func testATokenBoundToAnotherKeyIsClearedRatherThanCarriedForward() {
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_dev_first00000"))
        store.setTesterToken("itt_first", expiresAt: nil)
        XCTAssertEqual(store.testerToken, "itt_first")

        store.install(runtime: runtime(apiKey: "it_dev_second0000"))
        XCTAssertNil(store.testerToken)
    }

    // MARK: - The unified expiry rule (ADR-0005 Decision 10)

    func testZeroAndNegativeExpiriesMeanNoLocalExpiry() {
        // This store used to read a stored 0 as Date(1970) — therefore
        // expired — which is the opposite of Android and web.
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_dev_abcdef1234"))

        store.setTesterToken("itt_zero", expiresAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(store.testerToken, "itt_zero")

        store.setTesterToken("itt_negative", expiresAt: Date(timeIntervalSince1970: -5))
        XCTAssertEqual(store.testerToken, "itt_negative")
    }

    func testAnExpiredTokenIsNotJustHiddenButCleared() {
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_dev_abcdef1234"))
        store.setTesterToken("itt_stale", expiresAt: Date(timeIntervalSinceNow: -1))

        XCTAssertNil(store.testerToken)
        XCTAssertNil(defaults.string(forKey: "io.issuetracker.sdk.testerToken"))
        XCTAssertNil(defaults.object(forKey: "io.issuetracker.sdk.testerTokenExpiresAt"))
        XCTAssertNil(defaults.string(forKey: "io.issuetracker.sdk.testerTokenApiKey"))
    }

    // MARK: - Renew-on-use

    func testTheServerExtendedExpiryIsAdoptedButOnlyForwards() {
        // Load-bearing on tvOS in a way it is not on iOS: with no
        // companion to re-mint from, a token allowed to lapse can only
        // be replaced by the host app calling setTesterToken again.
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_dev_abcdef1234"))
        let soon = Date(timeIntervalSinceNow: 60)
        store.setTesterToken("itt_live", expiresAt: soon)

        let later = Date(timeIntervalSinceNow: 3600).timeIntervalSince1970
        store.adoptRenewedExpiry(millisecondsSince1970: later * 1000)
        XCTAssertEqual(defaults.double(forKey: "io.issuetracker.sdk.testerTokenExpiresAt"), later, accuracy: 0.001)

        store.adoptRenewedExpiry(millisecondsSince1970: soon.timeIntervalSince1970 * 1000)
        XCTAssertEqual(defaults.double(forKey: "io.issuetracker.sdk.testerTokenExpiresAt"), later, accuracy: 0.001)
    }

    func testARenewalForATokenThatIsGoneDoesNotResurrectTheSlot() {
        let store = AttestationStore(defaults: defaults)
        store.install(runtime: runtime(apiKey: "it_dev_abcdef1234"))
        store.adoptRenewedExpiry(millisecondsSince1970: Date(timeIntervalSinceNow: 3600).timeIntervalSince1970 * 1000)
        XCTAssertNil(defaults.object(forKey: "io.issuetracker.sdk.testerTokenExpiresAt"))
    }
}
