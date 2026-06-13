import AppKit
import XCTest
@testable import VoiceInputApp

final class OverlayLayoutTests: XCTestCase {
    func testCapsuleUsesRequiredHeightAndRadius() {
        XCTAssertEqual(OverlayLayout.capsuleHeight, 56)
        XCTAssertEqual(OverlayLayout.cornerRadius, 28)
    }

    func testTextWidthIsClampedToRequiredRange() {
        XCTAssertEqual(OverlayLayout.clampedTextWidth(40), 160)
        XCTAssertEqual(OverlayLayout.clampedTextWidth(320), 320)
        XCTAssertEqual(OverlayLayout.clampedTextWidth(900), 480)
    }

    func testWindowWidthIncludesWaveformSpacingAndPadding() {
        XCTAssertEqual(OverlayLayout.windowWidth(textWidth: 160), 248)
        XCTAssertEqual(OverlayLayout.windowWidth(textWidth: 480), 568)
    }

    func testWindowHeightExpandsForMultilineTextWithinMaximum() {
        XCTAssertEqual(OverlayLayout.windowHeight(textHeight: 20), 56)
        XCTAssertEqual(OverlayLayout.windowHeight(textHeight: 120), 144)
        XCTAssertEqual(OverlayLayout.windowHeight(textHeight: 400), 220)
    }
}
