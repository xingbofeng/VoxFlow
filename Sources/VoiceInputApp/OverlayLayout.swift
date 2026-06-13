import AppKit

enum OverlayLayout {
    static let horizontalPadding: CGFloat = 16
    static let waveformWidth: CGFloat = 44
    static let waveformHeight: CGFloat = 32
    static let interSpacing: CGFloat = 12
    static let minimumTextWidth: CGFloat = 160
    static let minimumCapsuleHeight: CGFloat = 56
    static let maximumTextWidth: CGFloat = 480
    static let capsuleHeight: CGFloat = minimumCapsuleHeight
    static let maximumCapsuleHeight: CGFloat = 220
    static let verticalPadding: CGFloat = 12
    static let cornerRadius: CGFloat = 28
    /// Maximum number of visible text lines; text beyond this scrolls or fades
    static let maxVisibleLines = 6

    static func clampedTextWidth(_ width: CGFloat) -> CGFloat {
        max(minimumTextWidth, min(maximumTextWidth, width))
    }

    static func windowWidth(textWidth: CGFloat) -> CGFloat {
        horizontalPadding
            + waveformWidth
            + interSpacing
            + clampedTextWidth(textWidth)
            + horizontalPadding
    }

    static func windowHeight(textHeight: CGFloat) -> CGFloat {
        let contentHeight = max(waveformHeight, textHeight)
        let padded = contentHeight + 2 * verticalPadding
        return max(minimumCapsuleHeight, min(maximumCapsuleHeight, padded))
    }
}
