import SwiftUI

struct ProviderInitialBadge: View {
    nonisolated static let metadataSize: CGFloat = 32

    let text: String?
    var tint: Color = AppTheme.ColorToken.accent
    var background: Color = AppTheme.ColorToken.controlBackground
    var size: CGFloat = ProviderInitialBadge.metadataSize
    var isMuted = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(background)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
            )
            .overlay {
                Text(Self.initial(from: text))
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(isMuted ? AppTheme.ColorToken.secondaryText : tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityHidden(true)
    }

    nonisolated static func initial(from text: String?) -> String {
        guard let first = text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .first else {
            return "?"
        }
        return String(first).uppercased()
    }
}
