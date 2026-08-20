import IssuetrackerTVSDK
import SwiftUI

@main
struct IssuetrackerTVExampleApp: App {
    init() {
        // Dev key so the trigger fails open without attestation.
        // Replace with your own key from the Issuetracker web UI.
        Issuetracker.configure(apiKey: "it_dev_example_key")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
