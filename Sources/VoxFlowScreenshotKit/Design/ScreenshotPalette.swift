import AppKit
import SwiftUI

/// Screenshot-kit palette mirroring the app's Claude Design System tokens
/// (`Sources/VoxFlowApp/DesignSystemBridges/CDSTokens.swift`).
///
/// `VoxFlowScreenshotKit` cannot import the app target, so the clay brand ramp
/// is restated here. Keep these values in sync with `CDS`; the selection overlay,
/// annotation ink and capture HUDs all read from this file so no cold green
/// leaks into user-visible chrome.
///
/// `danger` deliberately stays the system red: recording/stop affordances are a
/// platform convention, and `ScreenRecordingHUDPanelTests` pins that contract.
public enum ScreenshotPalette {
    /// Clay brand accent.
    public static var clay: NSColor { NSColor(cdsHex: 0xD97757) }
    public static var clayHover: NSColor { NSColor(cdsHex: 0xCC5A36) }
    public static var clayStrong: NSColor { NSColor(cdsHex: 0xC25124) }
    public static var clayWash: NSColor { NSColor(cdsHex: 0xFBF3EF) }

    /// Recording / destructive emphasis (platform red, see note above).
    public static var danger: NSColor { .systemRed }
    /// Secondary capture emphasis (scrolling capture HUD).
    public static var warning: NSColor { NSColor(cdsHex: 0xC97C2A) }

    /// Neutral hairline stroke.
    public static var hairline: NSColor { NSColor(white: 0, alpha: 0.10) }

    /// SwiftUI bridge for annotation selection outlines.
    public static var clayColor: Color { Color(nsColor: clay) }
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
