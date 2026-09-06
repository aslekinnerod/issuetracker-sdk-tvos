import XCTest

/// On-device E2E for the TV trigger contract (sdk-spec/TV_TRIGGERS.md):
/// a short Play/Pause tap must do nothing; a 2-second hold must open
/// the reporter. `XCUIRemote.press(_:forDuration:)` is the only way to
/// produce a genuine timed hold on the simulator.
///
/// The submission round-trip needs a real key. xcodebuild strips the
/// `TEST_RUNNER_` prefix when injecting environment into the UI-test
/// runner process, so pass it prefixed and read it unprefixed here:
///   TEST_RUNNER_ISSUETRACKER_API_KEY=it_dev_... xcodebuild test ...
/// Without one the round-trip test skips locally. The trigger tests need
/// a real key too: on the baked-in it_dev_ placeholder the backend
/// answers with a terminal error, the SDK goes TERMINATED and the
/// reporter never opens, so both hold tests fail.
///
/// A skip must never stand in for coverage in CI — xcodebuild reports a
/// skipped test as a non-failure, so a missing, expired or rotated key
/// would silently delete the only end-to-end verification and the run
/// would still go green. Set TEST_RUNNER_REQUIRE_E2E_KEY=1 (CI does) to
/// turn a key that never arrives into a failure instead.
final class RemoteHoldE2ETests: XCTestCase {

    private var apiKey: String? {
        ProcessInfo.processInfo.environment["ISSUETRACKER_API_KEY"]
    }

    /// Set as TEST_RUNNER_REQUIRE_E2E_KEY=1 wherever a missing key must be
    /// a failure rather than a skip.
    private var requiresAPIKey: Bool {
        ProcessInfo.processInfo.environment["REQUIRE_E2E_KEY"] == "1"
    }

    private func launchApp(identified: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        if let apiKey, !apiKey.isEmpty {
            app.launchEnvironment["ISSUETRACKER_API_KEY"] = apiKey
        }
        if identified {
            app.launchEnvironment["ISSUETRACKER_E2E_NAME"] = "E2E Bot"
        }
        app.launch()
        dismissOnboardingIfPresent(app)
        return app
    }

    private func dismissOnboardingIfPresent(_ app: XCUIApplication) {
        let gotIt = app.buttons["Got it"]
        if gotIt.waitForExistence(timeout: 4) {
            XCUIRemote.shared.press(.select)
        }
        _ = app.staticTexts["Issuetracker tvOS example"].waitForExistence(timeout: 4)
    }

    private func reporterVisible(_ app: XCUIApplication) -> Bool {
        app.staticTexts["Tell us what broke"].exists ||
            app.staticTexts["One thing first"].exists
    }

    /// ADR-0003 terminal state. A terminated install makes every
    /// other assertion meaningless — fail loudly instead of letting
    /// tests half-pass against the terminal screen. (A submit against
    /// a key whose allowedClients whitelist excludes this bundle id
    /// terminates the SDK with invalid_api_key — reset the app and
    /// use a key provisioned for no.issuetracker.example.tv.)
    private func failIfTerminated(_ app: XCUIApplication) {
        if app.staticTexts["Bug reporting is no longer available."].exists {
            XCTFail(
                "SDK is TERMINATED on this install — delete the app " +
                "from the simulator and verify the API key's client whitelist"
            )
        }
    }

    private func focusedLabel(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasFocus == true"))
            .firstMatch.label
    }

    /// D-pad walk that READS the focused element after every press —
    /// `element.hasFocus` polling proved unreliable for SwiftUI
    /// buttons on tvOS, but the focused-element query is authoritative.
    private func navigate(
        toLabel label: String,
        via directions: [XCUIRemote.Button],
        app: XCUIApplication
    ) -> Bool {
        if focusedLabel(app) == label { return true }
        for direction in directions {
            for _ in 0..<10 {
                XCUIRemote.shared.press(direction)
                Thread.sleep(forTimeInterval: 0.35)
                let focused = focusedLabel(app)
                print("DIAG walk \(direction): focused='\(focused)'")
                if focused == label { return true }
            }
        }
        return false
    }

    /// D-pad walk until `element.hasFocus`, trying downs then rights —
    /// deterministic enough for the example app's small focus graph.
    private func moveFocus(to element: XCUIElement, app: XCUIApplication) -> Bool {
        for direction in [XCUIRemote.Button.down, .right, .up, .left] {
            for _ in 0..<8 {
                if element.exists && element.hasFocus { return true }
                XCUIRemote.shared.press(direction)
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        return element.exists && element.hasFocus
    }

    func testShortTapDoesNotOpenReporter() {
        let app = launchApp(identified: true)
        XCUIRemote.shared.press(.playPause)
        Thread.sleep(forTimeInterval: 3.5)
        XCTAssertFalse(
            reporterVisible(app),
            "reporter opened on a short tap — violates TV_TRIGGERS.md"
        )
        // The assertion above passes for free whenever the trigger is dead
        // — a TERMINATED install, an unregistered observer, a broken key —
        // so on its own it is not evidence that short taps are being
        // ignored. Prove the trigger was live in this very session before
        // trusting the negative.
        XCUIRemote.shared.press(.playPause, forDuration: 2.3)
        failIfTerminated(app)
        XCTAssertTrue(
            app.staticTexts["Tell us what broke"].waitForExistence(timeout: 5) ||
                app.staticTexts["One thing first"].exists,
            "control failed: the hold trigger was not live, so 'short tap " +
            "did nothing' proves nothing"
        )
    }

    func testTwoSecondHoldOpensReporter() {
        let app = launchApp(identified: false)
        XCUIRemote.shared.press(.playPause, forDuration: 2.3)
        // Fresh identity state may show the name prompt first; an
        // identified install goes straight to the form. Accept either.
        let opened = app.staticTexts["Tell us what broke"]
            .waitForExistence(timeout: 5) ||
            app.staticTexts["One thing first"].exists
        failIfTerminated(app)
        XCTAssertTrue(opened, "reporter did not open after a 2.3 s hold")
    }

    /// Full round-trip against the real backend: hold → form → type a
    /// title → submit. Success signal: the form dismisses itself —
    /// ReportView only closes on a successful createIssueFromSdk
    /// response; failures keep it up with an inline error.
    func testFullSubmissionRoundTripSucceeds() throws {
        guard let apiKey, !apiKey.isEmpty else {
            if requiresAPIKey {
                XCTFail(
                    "REQUIRE_E2E_KEY is set but no ISSUETRACKER_API_KEY " +
                    "reached the test runner — pass it to xcodebuild as " +
                    "TEST_RUNNER_ISSUETRACKER_API_KEY (the prefix is " +
                    "stripped on injection)"
                )
                return
            }
            throw XCTSkip("no ISSUETRACKER_API_KEY in test-runner env")
        }
        let app = launchApp(identified: true)
        XCUIRemote.shared.press(.playPause, forDuration: 2.3)
        failIfTerminated(app)
        XCTAssertTrue(
            app.staticTexts["Tell us what broke"].waitForExistence(timeout: 5),
            "report form did not open"
        )

        let titleField = app.textFields.firstMatch
        XCTAssertTrue(moveFocus(to: titleField, app: app), "could not focus title field")
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: 1.0)
        app.typeText("E2E: tvOS remote trigger verification")
        // Leave the fullscreen keyboard; typed text commits live.
        XCUIRemote.shared.press(.menu)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(
            navigate(toLabel: "Send report", via: [.down, .right, .left], app: app),
            "could not focus Send report"
        )
        XCUIRemote.shared.press(.select)

        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.staticTexts["Tell us what broke"]
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [gone], timeout: 30),
            .completed,
            "submission did not complete (form still up after 30 s)"
        )
        // Form dismissal alone is AMBIGUOUS: a terminal server error
        // also tears down the form and hands off to TerminatedView
        // (after a ~350 ms settle). Only dismissal WITHOUT the
        // terminal screen is a genuine createIssueFromSdk success.
        Thread.sleep(forTimeInterval: 1.5)
        failIfTerminated(app)
    }
}
