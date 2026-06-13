import SwiftUI

enum AppTheme {
    enum Radius {
        static let card: CGFloat = 12
        static let control: CGFloat = 8
        static let row: CGFloat = 10
        static let icon: CGFloat = 10
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
        static let pageBackground = Color(red: 0.965, green: 0.975, blue: 0.970)
        static let panelBackground = Color(red: 0.992, green: 0.995, blue: 0.992)
        static let controlBackground = Color(red: 0.948, green: 0.960, blue: 0.955)
        static let panelStroke = Color(red: 0.790, green: 0.835, blue: 0.815).opacity(0.58)
        static let subtleStroke = Color(red: 0.870, green: 0.900, blue: 0.888).opacity(0.72)
        static let primaryText = Color(nsColor: .labelColor)
        static let secondaryText = Color(nsColor: .secondaryLabelColor)
        static let accent = Color(red: 0.055, green: 0.420, blue: 0.345)
        static let accentSoft = Color(red: 0.890, green: 0.946, blue: 0.925)
        static let progressTrack = Color(red: 0.855, green: 0.885, blue: 0.872)
        static let accentDark = Color(red: 0.16, green: 0.56, blue: 0.48)
        static let sidebarBackground = Color(red: 0.940, green: 0.955, blue: 0.950)
        static let sidebarText = Color(nsColor: .labelColor).opacity(0.82)
        static let selectionBackground = accent.opacity(0.12)
        static let selectionBorder = accent.opacity(0.26)
        static let hoverBackground = Color(red: 0.925, green: 0.940, blue: 0.935)
    }
}

extension View {
    func appPanel(cornerRadius: CGFloat = AppTheme.Radius.card) -> some View {
        background(AppTheme.ColorToken.panelBackground)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.ColorToken.panelStroke, lineWidth: AppTheme.Border.panelLineWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: AppTheme.ColorToken.accent.opacity(AppTheme.Shadow.cardOpacity),
                radius: AppTheme.Shadow.cardRadius,
                y: AppTheme.Shadow.cardYOffset
            )
    }

    func appControlSurface(cornerRadius: CGFloat = AppTheme.Radius.control) -> some View {
        background(AppTheme.ColorToken.controlBackground)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
