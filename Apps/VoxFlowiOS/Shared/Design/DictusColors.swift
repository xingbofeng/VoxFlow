// DictusCore/Sources/DictusCore/Design/DictusColors.swift
// Brand color system with hex initializer and light/dark mode support.
import SwiftUI

/// Brand color palette for Dictus.
///
/// WHY Color(hex:) instead of Asset Catalog:
/// The project has no .xcassets directory yet for DictusApp. Using hex initializers
/// provides exact brand colors from the brand kit without needing asset catalog setup.
/// Colors adapt to light/dark mode via the colorScheme-aware static properties.
///
/// WHY static computed properties returning adaptive colors:
/// SwiftUI re-evaluates computed properties when colorScheme changes, so the colors
/// automatically adapt to light/dark mode without manual observation.
public extension Color {
    // MARK: - Brand Colors (fixed, non-adaptive)

    /// Primary Mashangxie accent green (#16A34A).
    static let dictusAccent = Color(hex: 0x16A34A)

    /// Lighter accent highlight (#4ADE80).
    static let dictusAccentHighlight = Color(hex: 0x4ADE80)

    /// Recording state red (#EF4444)
    static let dictusRecording = Color(hex: 0xEF4444)

    /// Success state green (#22C55E)
    static let dictusSuccess = Color(hex: 0x22C55E)

    /// Smart mode purple (#8B5CF6)
    static let dictusSmartMode = Color(hex: 0x8B5CF6)

    // MARK: - Adaptive Colors (light/dark mode)

    /// Background color: #0A1628 dark / system background light
    static var dictusBackground: Color {
        Color(light: Color(hex: 0xF2F2F7), dark: Color(hex: 0x0A1628))
    }

    /// Surface color for cards: #161C2C dark / secondary system background light
    static var dictusSurface: Color {
        Color(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x161C2C))
    }

    // MARK: - Gradient Colors (for BrandWaveform)

    /// Gradient start for center bar (#86EFAC).
    static let dictusGradientStart = Color(hex: 0x86EFAC)

    /// Gradient end for center bar (#15803D).
    static let dictusGradientEnd = Color(hex: 0x15803D)

    // MARK: - Hex Initializer

    /// Create a Color from a hex integer value (e.g., 0x3D7EFF).
    ///
    /// WHY UInt rather than String:
    /// Compile-time validation -- a typo in a hex literal causes a build error.
    /// String parsing would silently fail at runtime.
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    /// Create an adaptive Color that switches between light and dark variants.
    ///
    /// WHY UIColor bridge:
    /// SwiftUI's Color doesn't have a built-in light/dark initializer on iOS 16.
    /// UIColor.init(dynamicProvider:) handles trait collection changes automatically,
    /// then we wrap it back in SwiftUI Color.
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
        #else
        self = dark
        #endif
    }
}
