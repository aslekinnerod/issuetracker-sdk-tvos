import IssuetrackerTVSDK
import SwiftUI

@main
struct IssuetrackerTVExampleApp: App {
    init() {
        let env = ProcessInfo.processInfo.environment
        // Real keys are injected via the environment (Xcode scheme or
        // the UI-test runner) so they never land in git. The it_dev_
        // fallback fails open on attestation, so the triggers work for
        // local poking even without a real key — submits will fail.
        Issuetracker.configure(
            apiKey: env["ISSUETRACKER_API_KEY"] ?? "it_dev_example_key",
            showOnboarding: true
        )
        // E2E hook: pre-identify so the UI tests exercise the form
        // without the name-prompt keyboard round-trip in every test.
        // The name-prompt path itself is covered by the dedicated test
        // that launches without this variable.
        if let name = env["ISSUETRACKER_E2E_NAME"], !name.isEmpty {
            Issuetracker.identify(name: name)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
