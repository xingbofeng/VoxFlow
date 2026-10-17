import AppKit
import SwiftUI

/// Claude Design System (CDS) design tokens, derived from
/// https://github.com/Caho1/open-claude-ui code-examples/cds-theme.css.
///
/// The palette is intentionally warm and low-contrast: a clay / terracotta accent
/// (#d97757 light, #e08264 dark), warm gray surfaces (Surface 0-3) and hairline
/// strokes instead of elevation shadows. Cold greens, neon accents and pure
/// black/white backgrounds are not part of this system.
enum CDS {
    // MARK: - Brand

    /// Clay / terracotta brand accent.
    enum Clay {
        static let base = adaptive(light: 0xD97757, dark: 0xE08264)
        static let hover = adaptive(light: 0xCC5A36, dark: 0xEF9878)
        static let strong = adaptive(light: 0xC25124, dark: 0xF4AE94)
        static let wash = adaptive(light: 0xFBF3EF, dark: 0x2C1A13)

        /// Sequential ramp for heat maps and activity grids.
        enum Ramp {
            static let level0 = adaptive(light: 0xEFEEE9, dark: 0x2A2A26)
            static let level1 = adaptive(light: 0xF7D8CB, dark: 0x4B1B08)
            static let level2 = adaptive(light: 0xF3C5B2, dark: 0x712B0F)
            static let level3 = adaptive(light: 0xF09978, dark: 0x993D19)
            static let level4 = adaptive(light: 0xD97757, dark: 0xF09978)
        }
    }

    // MARK: - Surfaces

    /// Four-step, low-contrast warm gray surface ladder.
    enum Surface {
        static let level0 = adaptive(light: 0xF9F9F7, dark: 0x1B1B19)
        static let level1 = adaptive(light: 0xFCFCFB, dark: 0x21211E)
        static let level2 = adaptive(light: 0xFFFFFF, dark: 0x282824)
        static let level3 = adaptive(light: 0xFFFFFF, dark: 0x32322D)
        static let segmentTrack = alpha(0.06)
        static let segmentThumb = adaptive(light: 0xFFFFFF, dark: 0x3A3A34)
    }

    // MARK: - Strokes and fills

    enum Stroke {
        static let hairline = alpha(0.10)
        static let strong = alpha(0.18)
        static let heavy = alpha(0.28)
    }

    enum Fill {
        static let ghostHover = alpha(0.05)
        static let ghostSelected = alpha(0.08)
        static let secondaryHover = alpha(0.13)
    }

    // MARK: - Text

    enum Text {
        static let primary = adaptive(light: 0x151515, dark: 0xF5F4F1)
        static let secondary = adaptive(light: 0x525252, dark: 0xB8B5AE)
        static let muted = adaptive(light: 0x8A8A8A, dark: 0x8C8981)
    }

    // MARK: - Semantic

    enum Semantic {
        static let messageTint = adaptive(light: 0xF0F4F8, dark: 0x1E2A36)
        static let success = adaptive(light: 0x2E7D4F, dark: 0x7BC29A)
        static let warning = adaptive(light: 0x9A5B12, dark: 0xE0A45C)
        static let danger = adaptive(light: 0xB3261E, dark: 0xE88A83)
    }

    // MARK: - Geometry

    enum Radius {
        static let xs: CGFloat = 2
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 8
        static let panel: CGFloat = 10
        static let xl: CGFloat = 12
        static let xl2: CGFloat = 16
        static let bubble: CGFloat = 18
        static let composer: CGFloat = 20
        static let pill: CGFloat = 999
    }

    // MARK: - Typography

    /// Editorial type scale: restrained weights, tight tracking on display sizes.
    enum Typography {
        /// Page title ("首页", "设置").
        static let pageTitle = Font.system(size: 26, weight: .semibold)
        /// Section title inside a page.
        static let sectionTitle = Font.system(size: 17, weight: .semibold)
        /// Card / group title.
        static let cardTitle = Font.system(size: 15, weight: .semibold)
        /// Body copy.
        static let body = Font.system(size: 13.5)
        /// Secondary / supporting copy.
        static let caption = Font.system(size: 12)
        /// Numeric metric display.
        static let metric = Font.system(size: 28, weight: .semibold, design: .rounded)
    }

    // MARK: - Motion

    enum Spring {
        static let bouncy = Animation.spring(response: 0.22, dampingFraction: 0.612)
        static let snappy = Animation.spring(response: 0.30, dampingFraction: 0.78)
        static let gentle = Animation.spring(response: 0.45, dampingFraction: 0.55)
        static let heavySnap = Animation.spring(response: 0.35, dampingFraction: 1.0)
    }

    enum Easing {
        static let swift = Animation.timingCurve(0.16, 1.0, 0.3, 1.0)
        static let enter = Animation.timingCurve(0.22, 1.0, 0.36, 1.0)
        static let out = Animation.timingCurve(0.165, 0.84, 0.44, 1.0)
        static let snap = Animation.timingCurve(0.32, 0.72, 0.0, 1.0)
        static let overshoot = Animation.timingCurve(0.34, 1.3, 0.64, 1.0)
        static let pulse = Animation.timingCurve(0.4, 0.0, 0.2, 1.0)
    }

    // MARK: - Scroll fade

    static let scrollFadeStops: [(location: Double, alpha: Double)] = [
        (0.15, 0.051),
        (0.30, 0.149),
        (0.45, 0.302),
        (0.60, 0.502),
        (0.75, 0.702),
        (0.87, 0.851),
    ]
    static let scrollFadeSize: CGFloat = 28

    // MARK: - Helpers

    static func adaptive(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(cdsHex: dark)
                : NSColor(cdsHex: light)
        })
    }

    static func alpha(_ opacity: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: opacity)
                : NSColor(white: 0, alpha: opacity)
        })
    }
}

extension NSColor {
    convenience init(cdsHex hex: Int) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}

// MARK: - AppKit bridges

extension CDS {
    static func nsColor(_ color: Color) -> NSColor {
        NSColor(color)
    }
}

extension CDS.Clay {
    static var baseNSColor: NSColor { NSColor(cdsHex: 0xD97757) }
    static var hoverNSColor: NSColor { NSColor(cdsHex: 0xCC5A36) }
    static var strongNSColor: NSColor { NSColor(cdsHex: 0xC25124) }
}

extension CDS.Surface {
    static var level0NSColor: NSColor { .cdsDynamic(light: 0xF9F9F7, dark: 0x1B1B19) }
    static var level1NSColor: NSColor { .cdsDynamic(light: 0xFCFCFB, dark: 0x21211E) }
    static var level2NSColor: NSColor { .cdsDynamic(light: 0xFFFFFF, dark: 0x282824) }
    static var level3NSColor: NSColor { .cdsDynamic(light: 0xFFFFFF, dark: 0x32322D) }
}

extension CDS.Stroke {
    static var hairlineNSColor: NSColor { .cdsNeutral(0.10) }
    static var strongNSColor: NSColor { .cdsNeutral(0.18) }
    static var heavyNSColor: NSColor { .cdsNeutral(0.28) }
}

extension CDS.Fill {
    static var ghostHoverNSColor: NSColor { .cdsNeutral(0.05) }
    static var ghostSelectedNSColor: NSColor { .cdsNeutral(0.08) }
}

extension CDS.Text {
    static var primaryNSColor: NSColor { .cdsDynamic(light: 0x151515, dark: 0xF5F4F1) }
    static var secondaryNSColor: NSColor { .cdsDynamic(light: 0x525252, dark: 0xB8B5AE) }
    static var mutedNSColor: NSColor { .cdsDynamic(light: 0x8A8A8A, dark: 0x8C8981) }
}

extension CDS.Semantic {
    static var successNSColor: NSColor { .cdsDynamic(light: 0x2E7D4F, dark: 0x7BC29A) }
    static var warningNSColor: NSColor { .cdsDynamic(light: 0x9A5B12, dark: 0xE0A45C) }
    static var dangerNSColor: NSColor { .cdsDynamic(light: 0xB3261E, dark: 0xE88A83) }
}

extension NSColor {
    /// Appearance-aware color resolved from a light and dark sRGB hex pair.
    static func cdsDynamic(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(cdsHex: dark)
                : NSColor(cdsHex: light)
        }
    }

    /// Neutral overlay: black in light mode, white in dark mode.
    static func cdsNeutral(_ opacity: Double) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: opacity)
                : NSColor(white: 0, alpha: opacity)
        }
    }
}

