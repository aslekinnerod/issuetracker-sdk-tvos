import SwiftUI

/// Shown in place of the report form when the SDK is in the
/// `.terminated` state — the server has signalled that the bound
/// project is gone, the API key is revoked, or the workspace is
/// suspended. No retry button, no raw error code, no link back to our
/// service. ADR-0003 Decision 9.
///
/// Strings come from ``Issuetracker/configure(apiKey:longPressToReport:onConfigurationError:showOnboarding:terminatedUI:)``'s
/// `terminatedUI` argument; English defaults apply for any field the
/// host doesn't override. Sister i18n hooks exist on the other SDKs.
struct TerminatedView: View {
    let strings: TerminatedUiStrings?
    let onClose: () -> Void

    private static let defaultTitle = "Bug reporting is no longer available."
    private static let defaultSubtitle = "Contact your team."
    private static let defaultCloseLabel = "Close"

    var body: some View {
        VStack(spacing: Tokens.Space.s5) {
            // Decorative — hidden from VoiceOver (1.1.1).
            Image(systemName: "exclamationmark.bubble")
                .brandFont(88, .light, relativeTo: .title)
                .foregroundStyle(Tokens.fg3)
                .accessibilityHidden(true)

            VStack(spacing: Tokens.Space.s3) {
                Text(strings?.title ?? Self.defaultTitle)
                    .brandFont(Tokens.TypeScale.title, .semibold, relativeTo: .title)
                    .foregroundStyle(Tokens.fg1)
                    .multilineTextAlignment(.center)

                Text(strings?.subtitle ?? Self.defaultSubtitle)
                    .brandFont(Tokens.TypeScale.body, relativeTo: .body)
                    .foregroundStyle(Tokens.fg2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Tokens.Space.s6)

            BrandButton(strings?.closeLabel ?? Self.defaultCloseLabel, variant: .secondary) {
                onClose()
            }
            .frame(maxWidth: 300)
            .padding(.top, Tokens.Space.s4)
        }
        .padding(Tokens.Space.s7)
        .frame(maxWidth: 1100)
        .background(Tokens.surfaceApp)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusLg, style: .continuous))
        .shadow(color: Color.black.opacity(0.35), radius: 60, x: 0, y: 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
