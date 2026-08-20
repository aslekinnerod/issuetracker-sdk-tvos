import IssuetrackerTVSDK
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 48) {
            Text("Issuetracker tvOS example")
                .font(.title)
            Text("Hold Play/Pause for 2 seconds to report an issue,\nor use the button below.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Report a bug") {
                Issuetracker.recordAction("report_button_pressed")
                Issuetracker.report()
            }
        }
        .padding(80)
        .onAppear {
            Issuetracker.recordAction("example_screen_appeared")
        }
    }
}
