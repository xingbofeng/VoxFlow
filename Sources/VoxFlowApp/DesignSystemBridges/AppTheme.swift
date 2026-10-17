import AppKit
import SwiftUI

/// App-level theme facade. All values resolve from `CDS` tokens so every view
/// (sidebar, cards, controls, HUDs) shares the Claude Design System palette.
enum AppTheme {
    enum Radius {
        static let card: CGFloat = CDS.Radius.xl
        static let control: CGFloat = CDS.Radius.lg
        static let row: CGFloat = CDS.Radius.panel
        static let icon: CGFloat = CDS.Radius.panel
    }

    enum Spacing {
        static let page: CGFloat = 28
        static let section: CGFloat = 18
        static let grid: CGFloat = 12
        static let card: CGFloat = 16
    }

    enum FontToken {
        static let heading = Font.system(size: 24, weight: .semibold)
        static let body = Font.system(size: 14)
        static let caption = Font.system(size: 12)
        static let title = Font.system(size: 18, weight: .semibold)
    }

    enum Border {
        static let panelLineWidth: CGFloat = 1
        static let selectedLineWidth: CGFloat = 1
    }

    enum Shadow {
        static let cardRadius: CGFloat = 8
        static let cardYOffset: CGFloat = 3
        static let cardOpacity: CGFloat = 0.045
    }

    enum ColorToken {
        /// Surface 1: page canvas.
        static let pageBackground = CDS.Surface.level1
        /// Surface 2: paged panels and cards.
        static let panelBackground = CDS.Surface.level2
        /// Surface 3: inputs, popovers, high layers.
        static let controlBackground = CDS.Surface.level3

        static let panelStroke = CDS.Stroke.hairline
        static let subtleStroke = CDS.Stroke.hairline
        static let divider = CDS.Stroke.hairline

        static let primaryText = CDS.Text.primary
        static let secondaryText = CDS.Text.secondary
        static let mutedText = CDS.Text.muted

        /// Clay / terracotta brand accent.
        static let accent = CDS.Clay.base
        static let accentHover = CDS.Clay.hover
        static let accentDark = CDS.Clay.strong
        static let accentSoft = CDS.Clay.wash

        static let progressTrack = CDS.Fill.ghostSelected

        static let success = CDS.Semantic.success
        static let warning = CDS.Semantic.warning
        static let danger = CDS.Semantic.danger

        /// Surface 0: sidebar base.
        static let sidebarBackground = CDS.Surface.level0
        static let sidebarText = CDS.Text.secondary

        /// Ghost selected fill, per CDS interactive states.
        static let selectionBackground = CDS.Fill.ghostSelected
        static let selectionBorder = CDS.Stroke.hairline
        static let hoverBackground = CDS.Fill.ghostHover

        static let segmentTrack = CDS.Surface.segmentTrack
        static let segmentThumb = CDS.Surface.segmentThumb
    }
}

extension View {
    /// Paged panel: surface 2 with a single hairline ring (no elevation shadow).
    /// Single-stroke discipline: never add a second border to nested content.
    func appPanel(cornerRadius: CGFloat = AppTheme.Radius.card) -> some View {
        appSurface(
            fill: AppTheme.ColorToken.panelBackground,
            stroke: AppTheme.ColorToken.panelStroke,
            cornerRadius: cornerRadius
        )
    }

    func appControlSurface(cornerRadius: CGFloat = AppTheme.Radius.control) -> some View {
        appSurface(
            fill: AppTheme.ColorToken.controlBackground,
            stroke: AppTheme.ColorToken.subtleStroke,
            cornerRadius: cornerRadius
        )
    }

    /// Single-closed-border surface used by the panel and control styles.
    /// The stroke is drawn on top of the clipped fill so corner anti-aliasing
    /// stays crisp on Retina displays.
    private func appSurface(fill: Color, stroke: Color, cornerRadius: CGFloat) -> some View {
        background(fill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
    }
}

extension AppTheme.ColorToken {
    static var accentNSColor: NSColor { .cdsHexColor(0xD97757) }
    static var successNSColor: NSColor { .cdsDynamic(light: 0x2E7D4F, dark: 0x7BC29A) }
    static var warningNSColor: NSColor { .cdsDynamic(light: 0x9A5B12, dark: 0xE0A45C) }
    static var dangerNSColor: NSColor { .cdsDynamic(light: 0xB3261E, dark: 0xE88A83) }
}

extension NSColor {
    static func cdsHexColor(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0,
                alpha: 1.0)
    }
}

