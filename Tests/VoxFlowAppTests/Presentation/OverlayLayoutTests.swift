import AppKit
import XCTest
@testable import VoxFlowApp

final class OverlayLayoutTests: XCTestCase {
    func testOverlayUsesCompactHeightAndRadius() {
        XCTAssertEqual(OverlayLayout.capsuleHeight, 52)
        XCTAssertEqual(OverlayLayout.cornerRadius, 12)
        XCTAssertEqual(OverlayLayout.bottomOffset, 40)
    }

    func testTextWidthIsClampedToRequiredRange() {
        XCTAssertEqual(OverlayLayout.clampedTextWidth(40), 240)
        XCTAssertEqual(OverlayLayout.clampedTextWidth(320), 320)
        XCTAssertEqual(OverlayLayout.clampedTextWidth(900), 420)
    }

    func testWindowWidthIncludesIndicatorTextAndStatusChip() {
        XCTAssertEqual(OverlayLayout.windowWidth(textWidth: 160), 390)
        XCTAssertEqual(OverlayLayout.windowWidth(textWidth: 420), 570)
    }

    func testWindowHeightExpandsForMultilineTextWithinMaximum() {
        XCTAssertEqual(OverlayLayout.windowHeight(textHeight: 20), 52)
        XCTAssertEqual(OverlayLayout.windowHeight(textHeight: 56), 72)
        XCTAssertEqual(OverlayLayout.windowHeight(textHeight: 400), 76)
    }

    func testLongTranscriptionKeepsTailVisible() {
        let text = String(repeating: "前", count: 160) + "当前内容"
        let visible = OverlayLayout.visibleTranscriptionText(text)

        XCTAssertTrue(visible.hasPrefix("…"))
        XCTAssertTrue(visible.hasSuffix("当前内容"))
        XCTAssertLessThanOrEqual(visible.count, 49)
        XCTAssertLessThan(visible.count, text.count)
    }

    func testNotesStreamingTextKeepsTailVisibleWithoutEllipsis() {
        let text = String(repeating: "前", count: 160) + "当前内容"
        let visible = OverlayLayout.visibleNotesStreamingText(text)

        XCTAssertFalse(visible.hasPrefix("…"))
        XCTAssertFalse(visible.contains("..."))
        XCTAssertTrue(visible.hasSuffix("当前内容"))
        XCTAssertLessThanOrEqual(visible.count, OverlayLayout.maximumVisibleCharacters)
        XCTAssertLessThan(visible.count, text.count)
    }

    /// 按 label 的真实约束量高度：`streamingTextWidth` 宽、15pt semibold、按字符换行。
    private func renderedHeight(_ text: String, width: CGFloat) -> CGFloat {
        (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold)]
        ).height
    }

    /// 线上回归：口述时文本区是 240pt × 38pt（两行 15pt）。
    ///
    /// 旧实现按「截到 48 个字符」处理，但 48 个中文字符排出来是 3 行 54pt，超过了 38pt；
    /// 又因为 `truncatesLastVisibleLine = false`，第三行被**静默裁掉**——而被裁掉的正好是
    /// 最新说的那句。表现就是「一直在说话，但 HUD 不再往后显示」。
    func testVisibleTranscriptionTextFitsTheStreamingTextBox() {
        let text = String(repeating: "这是一句很长的中文口述内容", count: 20) + "最后这句"
        let visible = OverlayLayout.visibleTranscriptionText(text)

        XCTAssertTrue(visible.hasPrefix("…"))
        XCTAssertTrue(visible.hasSuffix("最后这句"), "最新的内容必须可见，不能被裁掉")
        XCTAssertLessThanOrEqual(
            renderedHeight(visible, width: OverlayLayout.streamingTextWidth),
            OverlayLayout.streamingTextHeight,
            "可见文本超出了两行文本框，最新的字会被静默裁掉"
        )
    }

    /// 英文口述同样要落在这个盒子里（48 个 ASCII 字符约等于两行，所以旧实现在英文下看不出问题）。
    func testVisibleTranscriptionTextFitsTheStreamingTextBoxForLatinText() {
        let text = String(repeating: "this is a long english dictation ", count: 8) + "final words"
        let visible = OverlayLayout.visibleTranscriptionText(text)

        XCTAssertTrue(visible.hasPrefix("…"))
        XCTAssertTrue(visible.hasSuffix("final words"))
        XCTAssertLessThanOrEqual(
            renderedHeight(visible, width: OverlayLayout.streamingTextWidth),
            OverlayLayout.streamingTextHeight
        )
    }

    /// 记事流的可见文本也要落在同一个盒子里。
    func testVisibleNotesStreamingTextFitsTheStreamingTextBox() {
        let text = String(repeating: "这是一句很长的中文记事内容", count: 20) + "最后这句"
        let visible = OverlayLayout.visibleNotesStreamingText(text)

        XCTAssertTrue(visible.hasSuffix("最后这句"))
        XCTAssertLessThanOrEqual(
            renderedHeight(visible, width: OverlayLayout.streamingTextWidth),
            OverlayLayout.streamingTextHeight
        )
    }

    func testOverlayTextNeverAddsTrailingEllipsis() {
        XCTAssertEqual(OverlayLayout.textLineBreakMode, .byCharWrapping)
        XCTAssertFalse(OverlayLayout.truncatesLastVisibleLine)
    }

    func testTemporaryMessageRequiresVisibleText() {
        XCTAssertFalse(OverlayLayout.shouldShowTemporaryMessage(""))
        XCTAssertFalse(OverlayLayout.shouldShowTemporaryMessage("   \n\t"))
        XCTAssertTrue(OverlayLayout.shouldShowTemporaryMessage("识别失败"))
    }
}
