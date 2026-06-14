import AppKit
import XCTest
@testable import VoiceInputApp

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
