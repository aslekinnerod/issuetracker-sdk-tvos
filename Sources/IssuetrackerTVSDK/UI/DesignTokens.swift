import SwiftUI
import UIKit

// Trace design tokens lifted from `colors_and_type.css` — same colour
// values as sdk-ios. Type and control sizes are re-derived for the
// 10-foot UI: tvOS points map 1:1 to 1080p pixels and the viewer sits
// ~3 m away, so everything sits roughly at 2× the handheld scale
// (tvOS HIG body is 29pt). SF is the system font here too.
enum Tokens {
    // ---------- Surface ----------
    static let surfaceApp = Color(hex: 0xF4F7FA)
    static let surfaceCard = Color.white
    static let surface1 = Color(hex: 0xEAF0F6)
    static let surface2 = Color(hex: 0xDCE4ED)
    static let surfaceInverse = Color(hex: 0x0E1A2B)

    // ---------- Ink ----------
    static let fg1 = Color(hex: 0x0E1A2B)
    static let fg2 = Color(hex: 0x43536B)
    // #6E7E94 lands at 4.14:1 on white / 3.85:1 on surfaceApp — below
    // WCAG AA 4.5:1 for text (1.4.3). #5A6B82 gives 5.4:1 on white and
    // 5.1:1 on surfaceApp; the 10-foot UI wants the extra headroom
    // anyway. Same replacement class as web/sdk-web/sdk-android/sdk-ios.
    static let fg3 = Color(hex: 0x5A6B82)
    static let fg4 = Color(hex: 0xA8B3C2)

    // ---------- Lines ----------
    static let line = Color(hex: 0xDCE4ED)
    static let lineFaint = Color(hex: 0xECF1F6)

    // ---------- Brand ----------
    static let accent = Color(hex: 0x1FA2E8)
    // Darker accent for text-on-white, white-on-fill, and focus-ring
    // uses where #1FA2E8 fails WCAG AA (2.84:1 against white). #1577AD
    // gives ~4.9:1 — same value as web, sdk-web, sdk-android, sdk-ios.
    // Keep `accent` for decorative/soft uses only.
    static let accentStrong = Color(hex: 0x1577AD)
    static let accent2 = Color(hex: 0x22D3C5)
    static let accent3 = Color(hex: 0x0D7C8A)
    static let accentSoft = Color(hex: 0xDDF2FB)
    static let accentHover = Color(hex: 0x1A8FCF)

    // ---------- Status ----------
    static let critical = Color(hex: 0xE03A4E)
    static let criticalSoft = Color(hex: 0xFBE3E7)
    static let warning = Color(hex: 0xE9A23B)
    // On-white variant of `warning` for text (#E9A23B is 2.17:1 on
    // white; #8A6116 passes 4.5:1). Same value as the other SDKs.
    static let warningStrong = Color(hex: 0x8A6116)
    static let warningSoft = Color(hex: 0xFBEFD9)
    static let success = Color(hex: 0x1F9E72)
    static let successSoft = Color(hex: 0xDCF1E9)

    // ---------- Disabled controls ----------
    // Distinct disabled style instead of dropping opacity on the whole
    // button (opacity 0.4 pushed label contrast below 1.5:1 — critical
    // at 3-metre viewing distance). Same values as sdk-ios.
    static let disabledFill = Color(hex: 0xC7D0D9)
    static let disabledFg = Color(hex: 0x5B6B80)

    // ---------- Radius ----------
    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 16
    static let radiusLg: CGFloat = 24

    // ---------- Type (10-foot scale) ----------
    enum TypeScale {
        static let title: CGFloat = 34
        static let subtitle: CGFloat = 23
        static let label: CGFloat = 23
        static let body: CGFloat = 27
        static let control: CGFloat = 27
        static let caption: CGFloat = 21
    }

    // ---------- Spacing ----------
    enum Space {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 16
        static let s4: CGFloat = 24
        static let s5: CGFloat = 32
        static let s6: CGFloat = 48
        static let s7: CGFloat = 64
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// ---------- Type scaling ----------

// Fixed .system(size:) fonts ignore the user's text-size setting.
// tvOS exposes a narrower Dynamic Type range than iOS, but the
// UIFontMetrics API exists and Larger Text is a real setting under
// Settings → Accessibility — so every SDK font routes through this
// modifier (1.4.4), same as sdk-ios.
struct BrandScaledFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let size: CGFloat
    let weight: Font.Weight
    let textStyle: Font.TextStyle
    let design: Font.Design

    func body(content: Content) -> some View {
        let traits = UITraitCollection(
            preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory
        )
        let scaled = UIFontMetrics(forTextStyle: textStyle.uiTextStyle)
            .scaledValue(for: size, compatibleWith: traits)
        content.font(.system(size: scaled, weight: weight, design: design))
    }
}

extension View {
    /// System font of `size` at the default text size, scaling with
    /// Dynamic Type relative to `style` — the SwiftUI equivalent of
    /// `UIFontMetrics(forTextStyle:).scaledFont(for:)`.
    func brandFont(
        _ size: CGFloat,
        _ weight: Font.Weight = .regular,
        relativeTo style: Font.TextStyle,
        design: Font.Design = .default
    ) -> some View {
        modifier(BrandScaledFont(size: size, weight: weight, textStyle: style, design: design))
    }
}

extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        // UIFont.TextStyle.largeTitle does not exist on tvOS.
        case .largeTitle: return .title1
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}

extension DynamicTypeSize {
    var uiContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

// ---------- Reusable styled components ----------

// Branded button — primary / secondary / ghost / danger variants
// matching the Trace JSX reference. On tvOS the buttons are focus
// targets: focus lifts the control (scale + shadow + accent border)
// since there's no hover and PlainButtonStyle renders no focus
// visuals of its own.
struct BrandButton: View {
    enum Variant { case primary, secondary, ghost, danger }
    let title: String
    let icon: String?
    let variant: Variant
    let isDisabled: Bool
    let isLoading: Bool
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        variant: Variant = .secondary,
        isDisabled: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.variant = variant
        self.isDisabled = isDisabled
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .tint(variant == .primary ? .white : Tokens.fg1)
                } else if let icon {
                    Image(systemName: icon).brandFont(Tokens.TypeScale.label, .medium, relativeTo: .headline)
                }
                Text(title)
                    .brandFont(Tokens.TypeScale.control, .medium, relativeTo: .body)
                    .tracking(-0.2)
            }
            .frame(minHeight: 64)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Tokens.Space.s5)
        }
        .buttonStyle(BrandButtonStyle(variant: variant, isInactive: isDisabled || isLoading))
        .disabled(isDisabled || isLoading)
    }
}

private struct BrandButtonStyle: ButtonStyle {
    let variant: BrandButton.Variant
    let isInactive: Bool

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, variant: variant, isInactive: isInactive)
    }

    private struct Styled: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyle.Configuration
        let variant: BrandButton.Variant
        let isInactive: Bool

        var body: some View {
            configuration.label
                .background(bg)
                .foregroundStyle(fg)
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.radiusSm)
                        .stroke(border, lineWidth: isFocused ? 3 : 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSm))
                .scaleEffect(pressedOrFocusedScale)
                .shadow(
                    color: Color.black.opacity(isFocused ? 0.25 : 0),
                    radius: 18, x: 0, y: 10
                )
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }

        private var pressedOrFocusedScale: CGFloat {
            if configuration.isPressed { return 1.0 }
            return isFocused ? 1.05 : 1.0
        }

        // Disabled: a distinct still-readable style instead of dimming
        // the whole button below usable contrast (the old opacity-0.4
        // treatment landed around 1.5:1 — unreadable at 3 metres).
        private var bg: Color {
            if isInactive {
                return variant == .ghost ? .clear : Tokens.disabledFill
            }
            switch variant {
            // accentStrong, not accent: white-on-#1FA2E8 is 2.84:1
            // (fails 1.4.3); white-on-#1577AD is ~4.9:1. Focus is
            // carried by the white ring + scale + shadow, so the fill
            // no longer changes on focus.
            case .primary: return Tokens.accentStrong
            case .secondary, .danger: return Tokens.surfaceCard
            case .ghost: return isFocused ? Tokens.surface1 : .clear
            }
        }
        private var fg: Color {
            if isInactive { return Tokens.disabledFg }
            switch variant {
            case .primary: return .white
            case .secondary, .ghost: return Tokens.fg1
            case .danger: return Tokens.critical
            }
        }
        private var border: Color {
            if isInactive { return .clear }
            // Focus rings use accentStrong: #1FA2E8 against a white
            // card is 2.84:1, below the 3:1 non-text minimum (1.4.11)
            // — a focus indicator the viewer can't see is fatal on TV.
            switch variant {
            case .primary: return isFocused ? .white.opacity(0.9) : .clear
            case .ghost: return isFocused ? Tokens.accentStrong : .clear
            case .secondary, .danger: return isFocused ? Tokens.accentStrong : Tokens.line
            }
        }
    }
}

// Pill-style chip used for the type picker. Mirrors the JSX `Chip`
// primitive — soft cyan tint when active, neutral when not; focus
// lifts it like BrandButton.
struct BrandChip: View {
    let title: String
    let icon: String?
    let isActive: Bool
    let action: () -> Void

    init(_ title: String, icon: String? = nil, isActive: Bool, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isActive = isActive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isActive {
                    // Non-color selection cue (1.4.1) alongside the tint.
                    Image(systemName: "checkmark")
                        .brandFont(Tokens.TypeScale.caption, .semibold, relativeTo: .caption)
                        .accessibilityHidden(true)
                }
                if let icon {
                    Image(systemName: icon)
                        .brandFont(Tokens.TypeScale.label, .regular, relativeTo: .headline)
                        .accessibilityHidden(true)
                }
                Text(title).brandFont(Tokens.TypeScale.label, .medium, relativeTo: .headline).tracking(-0.2)
            }
            .frame(minHeight: 56)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Tokens.Space.s4)
        }
        .buttonStyle(BrandChipStyle(isActive: isActive))
        // Surface the selection state to VoiceOver (4.1.2/1.3.1) —
        // visually it's only carried by tint + checkmark.
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct BrandChipStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, isActive: isActive)
    }

    private struct Styled: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyle.Configuration
        let isActive: Bool

        var body: some View {
            configuration.label
                .background(isActive ? Tokens.accentSoft : Tokens.surfaceCard)
                .foregroundStyle(isActive ? Tokens.accent3 : Tokens.fg2)
                .overlay(
                    // accentStrong for both the focus ring and the
                    // active border — #1FA2E8 on white is 2.84:1,
                    // below the 3:1 non-text minimum (1.4.11).
                    RoundedRectangle(cornerRadius: Tokens.radiusSm)
                        .stroke(
                            isFocused ? Tokens.accentStrong : (isActive ? Tokens.accentStrong : Tokens.line),
                            lineWidth: isFocused ? 3 : 2
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSm))
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .shadow(color: Color.black.opacity(isFocused ? 0.2 : 0), radius: 14, x: 0, y: 8)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

// Focusable checkbox row — replaces UISwitch-style toggles, which
// don't translate well to the remote. One press flips it.
struct BrandCheckRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .brandFont(Tokens.TypeScale.control, .medium, relativeTo: .body)
                    .accessibilityHidden(true)
                Text(title)
                    .brandFont(Tokens.TypeScale.label, .medium, relativeTo: .headline)
                    .tracking(-0.2)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 56)
            .padding(.horizontal, Tokens.Space.s3)
        }
        .buttonStyle(BrandCheckRowStyle(isOn: isOn))
        // Read as a toggle, not a plain button: without this VoiceOver
        // announces the SF Symbol name and no state (4.1.2).
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
        .accessibilityAddTraits(.isToggle)
    }
}

private struct BrandCheckRowStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, isOn: isOn)
    }

    private struct Styled: View {
        @Environment(\.isFocused) private var isFocused
        let configuration: ButtonStyle.Configuration
        let isOn: Bool

        var body: some View {
            configuration.label
                .background(isFocused ? Tokens.surface1 : .clear)
                .foregroundStyle(isOn ? Tokens.accent3 : Tokens.fg2)
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.radiusSm)
                        // accentStrong: #1FA2E8 on the focused surface1 fill
                // is 2.47:1 — below the 3:1 focus-indicator minimum
                // (1.4.11).
                .stroke(isFocused ? Tokens.accentStrong : .clear, lineWidth: 3)
                )
                .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSm))
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

// Form-row label — caption above each input. Trace's "label" type
// style at 10-foot scale.
struct FieldLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .brandFont(Tokens.TypeScale.label, .medium, relativeTo: .headline)
            .foregroundStyle(Tokens.fg2)
    }
}

// Text input. tvOS TextFields open the system full-screen keyboard
// when selected, and the default style carries the platform focus
// appearance — we keep it and only set type + colors, rather than
// fighting the system with a bordered custom look that would hide
// the focus state.
struct BrandTextField: View {
    @Binding var value: String
    let placeholder: String

    var body: some View {
        TextField(placeholder, text: $value)
            .brandFont(Tokens.TypeScale.control, relativeTo: .body)
            .foregroundStyle(Tokens.fg1)
    }
}

// Header with the brand mark + a title and optional subtitle. Used
// at the top of ReportView and NamePromptView.
struct BrandHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(alignment: .center, spacing: Tokens.Space.s4) {
            // Decorative brand mark — hidden from VoiceOver (1.1.1).
            Image(systemName: "checkmark.shield.fill")
                .brandFont(44, .semibold, relativeTo: .title)
                .foregroundStyle(Tokens.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .brandFont(Tokens.TypeScale.title, .semibold, relativeTo: .title)
                    .foregroundStyle(Tokens.fg1)
                    .tracking(-0.5)
                if let subtitle {
                    Text(subtitle)
                        .brandFont(Tokens.TypeScale.subtitle, relativeTo: .subheadline)
                        .foregroundStyle(Tokens.fg3)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
