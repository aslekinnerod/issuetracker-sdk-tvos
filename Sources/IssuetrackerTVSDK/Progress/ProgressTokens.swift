import SwiftUI

// TV density: every geometry/type token is the handheld reference
// value (sdk-spec tokens.json) × 2, because tvOS points are 1:1 with
// 1080p pixels and the viewer sits 3 metres away. Ratios are
// preserved exactly; motion timings are untouched (spec §4 —
// behaviour rules are density-independent).
enum ProgressTokens {
    enum NeutralColor {
        static let ink = Color(hex: 0x0B0B0F)
        static let paper = Color.white
        static let track = Color(hex: 0xF1EEE8)
        static let muted = Color(hex: 0x6E6A62)
        // 3.44:1 vs paper (WCAG 1.4.11) — stalled/upcoming phase dots.
        static let subtle = Color(hex: 0x8F8A80)
        static let line = Color(.sRGB, red: 11.0/255, green: 11.0/255, blue: 15.0/255, opacity: 0.05)
        static let statusBody = Color(hex: 0x3A3A3A)
    }

    enum ErrorColor {
        static let accent = Color(hex: 0xC0392B)
        static let dark = Color(hex: 0x8A1F10)
        static let soft = Color(hex: 0xFBE0DC)
    }

    enum BugColor {
        static let accent = Color(hex: 0xE64A36)
        static let dark = Color(hex: 0xA8341F)
        static let soft = Color(hex: 0xFCE4DE)
    }

    enum TaskColor {
        static let accent = Color(hex: 0x3F4FE0)
        static let dark = Color(hex: 0x23308F)
        static let soft = Color(hex: 0xE5E8FB)
        static let fillEnd = Color(hex: 0x6675F0)
    }

    enum StoryColor {
        static let accent = Color(hex: 0xE0A23F)
        static let dark = Color(hex: 0x7D5614)
        static let soft = Color(hex: 0xFBEFD8)
        static let fillStart = Color(hex: 0xF4D38A)
        // WCAG 1.4.11 (non-text contrast ≥3:1) — meaningful graphics:
        // icon glyph, indeterminate sweep highlight, fill head cap.
        // accent/fillStart stay decorative (gradient body only).
        static let graphic = Color(hex: 0xB87A17)
    }

    enum Card {
        static let padding: CGFloat = 32
        static let radius: CGFloat = 36
        static let borderWidth: CGFloat = 2
    }

    enum Icon {
        static let frame: CGFloat = 72
        static let frameRadius: CGFloat = 20
        static let glyph: CGFloat = 44
    }

    enum Track {
        static let height: CGFloat = 20
        static let heightCompact: CGFloat = 12
        // WCAG 1.4.11 — minimum width of the fill head cap rendered in
        // the variant's graphic colour (spec: size.track.headCapMinWidth,
        // handheld reference 3 × 2 for TV density).
        static let headCapMinWidth: CGFloat = 6
    }

    enum Badge {
        static let paddingV: CGFloat = 10
        static let paddingH: CGFloat = 16
        static let radius: CGFloat = 16
        static let minWidth: CGFloat = 92
    }

    enum Gap {
        static let header: CGFloat = 24
        static let headerToTrack: CGFloat = 24
        static let trackToStatus: CGFloat = 24
    }

    enum TypeSize {
        static let kind: CGFloat = 20
        static let title: CGFloat = 30
        static let badge: CGFloat = 22
        static let status: CGFloat = 25
    }

    enum TypeWeight {
        static let kind: Font.Weight = .semibold
        static let title: Font.Weight = .semibold
        static let badge: Font.Weight = .semibold
        static let status: Font.Weight = .medium
    }

    enum Motion {
        static let fillDurationMs: Double = 120
        static let sweepDurationMs: Double = 1400
        static let sweepHighlightWidthFraction: Double = 0.4
        static let doneCheckmarkDurationMs: Double = 360
        static let phaseDotPulseDurationMs: Double = 1000
        static let iconWobblePeriodMs: Double = 754
        static let iconWobbleAmplitudeDeg: Double = 8
    }

    static let stallThresholdMs: Double = 3000
}
