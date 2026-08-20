import SwiftUI

// First-launch panel that teaches the user the remote trigger. Shown
// only when the host app opts in via
// `Issuetracker.configure(showOnboarding: true)` AND the trigger is
// enabled. Persisted via OnboardingStore so we never nag the same
// install twice — unless the host app calls
// `Issuetracker.showOnboarding()` explicitly.
//
// tvOS has exactly one gesture to teach (hold Play/Pause), so this is
// a single-tile panel. SF Symbols only — no bundled illustrations, so
// the package keeps zero resource overhead.
struct OnboardingView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top brand bar — same shield+title pattern as ReportView,
            // so the panel feels like the same product.
            BrandHeader(
                title: "Report bugs from anywhere",
                subtitle: "One button is all it takes"
            )
            .padding(.horizontal, Tokens.Space.s6)
            .padding(.top, Tokens.Space.s6)
            .padding(.bottom, Tokens.Space.s5)

            triggerTile
                .padding(.horizontal, Tokens.Space.s6)

            BrandButton("Got it", variant: .primary, action: onDismiss)
                .frame(maxWidth: 340)
                .padding(.top, Tokens.Space.s6)
                .padding(.bottom, Tokens.Space.s6)
        }
        .frame(maxWidth: 1100)
        .background(Tokens.surfaceApp)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusLg, style: .continuous))
        .shadow(color: Color.black.opacity(0.35), radius: 60, x: 0, y: 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var triggerTile: some View {
        HStack(alignment: .center, spacing: Tokens.Space.s5) {
            // accentStrong: the glyph restates "the Play/Pause button",
            // so it's a meaningful graphic — #1FA2E8 on surface1 is
            // 2.47:1, below the 3:1 minimum (1.4.11); #1577AD is 4.3:1.
            // Redundant with the adjacent text, so hidden from VoiceOver.
            Image(systemName: "playpause.fill")
                .brandFont(64, relativeTo: .title)
                .foregroundStyle(Tokens.accentStrong)
                .frame(width: 160, height: 160)
                .background(Tokens.surface1)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusMd))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text("Hold Play/Pause on your remote")
                    .brandFont(Tokens.TypeScale.title, .semibold, relativeTo: .title)
                    .foregroundStyle(Tokens.fg1)
                Text("Hold the button for 2 seconds to open the reporter — from any screen in the app.")
                    .brandFont(Tokens.TypeScale.body, relativeTo: .body)
                    .foregroundStyle(Tokens.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        // One logical statement — read as a single element instead of
        // three stops (VoiceOver reading order, 1.3.2).
        .accessibilityElement(children: .combine)
        .padding(Tokens.Space.s5)
        .background(Tokens.surfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.radiusMd)
                .stroke(Tokens.line, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusMd))
    }
}
