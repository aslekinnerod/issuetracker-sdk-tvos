import SwiftUI
import XCTest

@testable import IssuetrackerTVSDK

// Accessibility regression tests (ISU-39): assert the WCAG 2.x
// contrast ratios that the design tokens claim in their source
// comments. The WCAG-audit fixes replaced several colours precisely
// to clear these thresholds (fg3 #6E7E94 -> #5A6B82, accent ->
// accentStrong for text/rings, warning -> warningStrong for text,
// StoryColor.graphic for meaningful story graphics) — a future token
// tweak that silently drops below the minimum must fail here.
//
// Thresholds: WCAG 1.4.3 (text) >= 4.5:1, WCAG 1.4.11 (non-text —
// focus rings, meaningful graphics, phase dots) >= 3:1. Assertions
// are margin-free `>=` against the actual token values resolved from
// `Tokens` / `ProgressTokens` via @testable import.
final class ContrastTests: XCTestCase {

    // MARK: - WCAG 2.x contrast math

    private struct SRGB {
        let red: Double
        let green: Double
        let blue: Double
    }

    /// Resolves a design-token `Color` to its sRGB components. All
    /// tokens are built with `Color(hex:)` (explicit .sRGB) or are
    /// `Color.white`, so the UIColor round-trip is exact.
    private func srgbComponents(
        _ color: Color,
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> SRGB {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        let converted = UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertTrue(converted, "\(name): not convertible to RGBA", file: file, line: line)
        // Contrast math assumes opaque colours; a translucent token
        // has no single ratio and must not be asserted here.
        XCTAssertEqual(a, 1, accuracy: 0.0001, "\(name): token is not opaque", file: file, line: line)
        return SRGB(red: Double(r), green: Double(g), blue: Double(b))
    }

    /// Relative luminance per WCAG 2.x: linearise each channel
    /// (c/12.92 below the 0.03928 threshold, ((c+0.055)/1.055)^2.4
    /// above), then L = 0.2126R + 0.7152G + 0.0722B.
    private func relativeLuminance(_ color: SRGB) -> Double {
        func linearised(_ channel: Double) -> Double {
            channel <= 0.03928
                ? channel / 12.92
                : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearised(color.red)
            + 0.7152 * linearised(color.green)
            + 0.0722 * linearised(color.blue)
    }

    /// Contrast ratio (L1 + 0.05) / (L2 + 0.05), lighter over darker.
    private func contrastRatio(
        _ foreground: Color,
        _ background: Color,
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Double {
        let lf = relativeLuminance(srgbComponents(foreground, name, file: file, line: line))
        let lb = relativeLuminance(srgbComponents(background, name, file: file, line: line))
        return (max(lf, lb) + 0.05) / (min(lf, lb) + 0.05)
    }

    // MARK: - Helper sanity check

    func testContrastHelperBlackOnWhiteIsTwentyOne() {
        let ratio = contrastRatio(.black, .white, "black vs white")
        XCTAssertEqual(ratio, 21.0, accuracy: 0.001)
        // Ratio is symmetric — order of the pair must not matter.
        XCTAssertEqual(
            contrastRatio(.white, .black, "white vs black"),
            ratio,
            accuracy: 0.000001
        )
    }

    // MARK: - Token contrast requirements

    private struct ContrastRequirement {
        let name: String
        let foreground: Color
        let background: Color
        let minimum: Double
    }

    /// Every WCAG claim a token file makes in a comment is pinned
    /// here. Source of truth:
    /// - Sources/IssuetrackerTVSDK/UI/DesignTokens.swift
    /// - Sources/IssuetrackerTVSDK/Progress/ProgressTokens.swift
    private var requirements: [ContrastRequirement] {
        [
            // --- Text, WCAG 1.4.3 (>= 4.5:1) ---

            // Primary button: white label on accentStrong #1577AD
            // (~4.9:1; plain `accent` #1FA2E8 was 2.84:1 and stays
            // decorative-only).
            ContrastRequirement(
                name: "white on accentStrong (primary button label)",
                foreground: .white,
                background: Tokens.accentStrong,
                minimum: 4.5
            ),
            // accentStrong also serves as text-on-white.
            ContrastRequirement(
                name: "accentStrong on surfaceCard (accent text on white)",
                foreground: Tokens.accentStrong,
                background: Tokens.surfaceCard,
                minimum: 4.5
            ),
            // fg3 #5A6B82 replaced #6E7E94 (4.14:1 on white) to clear
            // 4.5:1 on both surfaces it is used on.
            ContrastRequirement(
                name: "fg3 on surfaceCard (tertiary text on white)",
                foreground: Tokens.fg3,
                background: Tokens.surfaceCard,
                minimum: 4.5
            ),
            ContrastRequirement(
                name: "fg3 on surfaceApp (tertiary text on app surface)",
                foreground: Tokens.fg3,
                background: Tokens.surfaceApp,
                minimum: 4.5
            ),
            // warningStrong #8A6116 is the on-white text variant of
            // `warning` (#E9A23B is 2.17:1 and stays decorative).
            ContrastRequirement(
                name: "warningStrong on surfaceCard (warning text on white)",
                foreground: Tokens.warningStrong,
                background: Tokens.surfaceCard,
                minimum: 4.5
            ),

            // --- Non-text, WCAG 1.4.11 (>= 3:1) ---

            // Focus rings use accentStrong against white cards and
            // the surface1 fill of focused ghost/check rows.
            ContrastRequirement(
                name: "accentStrong focus ring on surface1",
                foreground: Tokens.accentStrong,
                background: Tokens.surface1,
                minimum: 3.0
            ),
            // Story progress bar: `graphic` #B87A17 carries the
            // meaningful graphics (icon glyph, indeterminate sweep
            // highlight, fill head cap) on every surface it meets;
            // accent/fillStart stay decorative.
            ContrastRequirement(
                name: "story graphic on paper (icon glyph, head cap)",
                foreground: ProgressTokens.StoryColor.graphic,
                background: ProgressTokens.NeutralColor.paper,
                minimum: 3.0
            ),
            ContrastRequirement(
                name: "story graphic on story soft (icon frame fill)",
                foreground: ProgressTokens.StoryColor.graphic,
                background: ProgressTokens.StoryColor.soft,
                minimum: 3.0
            ),
            ContrastRequirement(
                name: "story graphic on track (sweep highlight)",
                foreground: ProgressTokens.StoryColor.graphic,
                background: ProgressTokens.NeutralColor.track,
                minimum: 3.0
            ),
            // Stalled/upcoming phase dots — subtle is documented as
            // 3.44:1 vs paper.
            ContrastRequirement(
                name: "neutral subtle on paper (phase dots)",
                foreground: ProgressTokens.NeutralColor.subtle,
                background: ProgressTokens.NeutralColor.paper,
                minimum: 3.0
            ),
        ]
    }

    func testDesignTokenPairsMeetWCAGMinimums() {
        for requirement in requirements {
            let ratio = contrastRatio(
                requirement.foreground,
                requirement.background,
                requirement.name
            )
            XCTAssertGreaterThanOrEqual(
                ratio,
                requirement.minimum,
                "\(requirement.name): \(String(format: "%.2f", ratio)):1 "
                    + "is below the WCAG minimum \(requirement.minimum):1"
            )
        }
    }
}
