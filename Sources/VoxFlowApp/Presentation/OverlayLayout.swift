import AppKit

enum OverlayLayout {
    static let horizontalPadding: CGFloat = 14
    static let indicatorSize: CGFloat = 30
    static let waveformWidth: CGFloat = 24
    static let waveformHeight: CGFloat = 22
    static let interSpacing: CGFloat = 10
    static let statusChipWidth: CGFloat = 72
    static let minimumTextWidth: CGFloat = 240
    static let minimumCapsuleHeight: CGFloat = 52
    static let maximumTextWidth: CGFloat = 420
    static let capsuleHeight: CGFloat = minimumCapsuleHeight
    static let maximumCapsuleHeight: CGFloat = 76
    static let verticalPadding: CGFloat = 8
    static let cornerRadius: CGFloat = 12
    static let bottomOffset: CGFloat = 40
    static let maximumVisibleCharacters = 48
    /// Maximum number of visible text lines; text beyond this scrolls or fades
    static let maxVisibleLines = 2
    static let textLineBreakMode: NSLineBreakMode = .byCharWrapping
    static let truncatesLastVisibleLine = false

    static func clampedTextWidth(_ width: CGFloat) -> CGFloat {
        max(minimumTextWidth, min(maximumTextWidth, width))
    }

    static func windowWidth(textWidth: CGFloat) -> CGFloat {
        horizontalPadding
            + indicatorSize
            + interSpacing
            + clampedTextWidth(textWidth)
            + interSpacing
            + statusChipWidth
            + horizontalPadding
    }

    static func windowHeight(textHeight: CGFloat) -> CGFloat {
        let contentHeight = max(waveformHeight, textHeight)
        let padded = contentHeight + 2 * verticalPadding
        return max(minimumCapsuleHeight, min(maximumCapsuleHeight, padded))
    }

    static func visibleTranscriptionText(_ text: String) -> String {
        guard text.count > maximumVisibleCharacters else {
            return text
        }
        return "…" + String(text.suffix(maximumVisibleCharacters))
    }

    static func shouldShowTemporaryMessage(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
