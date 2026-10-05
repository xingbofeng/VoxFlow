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
    /// HUD 文本 label 的字体。测量与渲染必须共用同一个字体，否则「装得下」的判断会和实际排版不一致。
    ///
    /// 用计算属性而不是 `static let`：`NSFont` 不是 `Sendable`，存成全局常量在 Swift 6 下会被拒绝，
    /// 而 `NSFont.systemFont` 本身有缓存，每次取回同一个实例。
    static var textFont: NSFont { NSFont.systemFont(ofSize: 15, weight: .semibold) }
    static let streamingTextWidth = minimumTextWidth
    static let streamingTextHeight: CGFloat = 38
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

    /// 一段文本在给定宽度下排出来的高度。
    static func renderedTextHeight(
        _ text: String,
        font: NSFont = textFont,
        width: CGFloat = streamingTextWidth
    ) -> CGFloat {
        (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).height
    }

    /// 取能完整放进 `width × maxHeight` 的末尾若干字符，前面拼 `prefix`。
    ///
    /// 为什么必须量、不能按字符数猜：15pt 下一个中文字符约占 15pt（240pt 一行只放得下约 16 个），
    /// 一个 ASCII 字符约占 7.5pt（一行约 32 个）。同一个「两行」预算，中文只够约 32 字，
    /// 英文能到约 56 字。任何固定的字符数上限都会在其中一种语言下溢出。
    ///
    /// 高度随字符数单调不减，所以二分找最长可行后缀。上界取 `maximumVisibleCharacters`，
    /// 让候选串始终很短，避免长 partial 上反复量整段文本。
    private static func fittingTail(
        of text: String,
        prefix: String,
        font: NSFont,
        width: CGFloat,
        maxHeight: CGFloat
    ) -> String {
        let characters = Array(text)
        var low = 0
        var high = min(characters.count, maximumVisibleCharacters)
        while low < high {
            let mid = (low + high + 1) / 2
            let candidate = prefix + String(characters[(characters.count - mid)...])
            if renderedTextHeight(candidate, font: font, width: width) <= maxHeight {
                low = mid
            } else {
                high = mid - 1
            }
        }
        // 至少留一个字：宁可略微溢出，也不要让 HUD 变成只有一个省略号。
        let keep = max(min(low, characters.count), 1)
        return prefix + String(characters[(characters.count - keep)...])
    }

    private static func needsTruncation(
        _ text: String,
        width: CGFloat,
        maxHeight: CGFloat
    ) -> Bool {
        text.count > maximumVisibleCharacters
            || renderedTextHeight(text, width: width) > maxHeight
    }

    /// 口述时显示的末尾文本：能放进文本框就原样显示，放不下就取末尾并加 `…` 表示前面被省略。
    ///
    /// `truncatesLastVisibleLine = false` 意味着 label 自己**不会**画省略号，超出的行是静默裁掉的，
    /// 所以「可见量」必须在这里算准——否则被裁掉的正好是最新说的内容。
    static func visibleTranscriptionText(
        _ text: String,
        width: CGFloat = streamingTextWidth,
        maxHeight: CGFloat = streamingTextHeight
    ) -> String {
        guard needsTruncation(text, width: width, maxHeight: maxHeight) else {
            return text
        }
        return fittingTail(
            of: text,
            prefix: "…",
            font: textFont,
            width: width,
            maxHeight: maxHeight
        )
    }

    /// 记事流的不加省略号版本；长度预算与口述一致。
    static func visibleNotesStreamingText(
        _ text: String,
        width: CGFloat = streamingTextWidth,
        maxHeight: CGFloat = streamingTextHeight
    ) -> String {
        guard needsTruncation(text, width: width, maxHeight: maxHeight) else {
            return text
        }
        return fittingTail(
            of: text,
            prefix: "",
            font: textFont,
            width: width,
            maxHeight: maxHeight
        )
    }

    static func shouldShowTemporaryMessage(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
