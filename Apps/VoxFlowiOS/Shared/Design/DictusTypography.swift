// DictusCore/Sources/DictusCore/Design/DictusTypography.swift
// Typography system using SF Pro Rounded for headings and SF Pro Text for body.
import SwiftUI

/// Typography scale for Dictus.
///
/// WHY system text styles instead of fixed sizes:
/// System text styles (`.title`, `.body`, `.caption`) automatically scale with
/// Dynamic Type -- Apple's accessibility feature that lets users set their preferred
/// text size. Using these styles means Dictus respects the user's accessibility
/// preferences without any extra code.
///
/// WHY SF Pro Rounded for headings:
/// Rounded fonts feel friendlier and more approachable. SF Pro Rounded is Apple's
/// system rounded font, so it's available on all iOS devices without bundling a
/// custom font. Body text uses the default SF Pro Text for readability.
public extension Font {
    /// Large heading -- SF Pro Rounded Bold
    static let dictusHeading: Font = .system(.title, design: .rounded, weight: .bold)

    /// Section subheading -- SF Pro Rounded Semibold
    static let dictusSubheading: Font = .system(.title3, design: .rounded, weight: .semibold)

    /// Body text -- SF Pro Text (system default)
    static let dictusBody: Font = .system(.body)

    /// Caption text -- SF Pro Text small
    static let dictusCaption: Font = .system(.caption)
}
