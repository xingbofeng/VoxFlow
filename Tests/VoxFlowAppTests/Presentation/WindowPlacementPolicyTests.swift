import AppKit
import XCTest
@testable import VoxFlowApp

final class WindowPlacementPolicyTests: XCTestCase {
    func testCenteredFrameUsesVisibleFrameCenter() {
        let frame = WindowPlacementPolicy.centeredFrame(
            windowSize: NSSize(width: 600, height: 400),
            visibleFrame: NSRect(x: 100, y: 200, width: 1_200, height: 800)
        )

        XCTAssertEqual(frame.origin.x, 400)
        XCTAssertEqual(frame.origin.y, 400)
        XCTAssertEqual(frame.size.width, 600)
        XCTAssertEqual(frame.size.height, 400)
    }

    func testBottomTrailingFrameUsesVisibleFrameLowerRightCorner() {
        let frame = WindowPlacementPolicy.bottomTrailingFrame(
            windowSize: NSSize(width: 440, height: 560),
            visibleFrame: NSRect(x: 100, y: 200, width: 1_200, height: 800),
            trailingMargin: 28,
            bottomMargin: 36
        )

        XCTAssertEqual(frame.origin.x, 832)
        XCTAssertEqual(frame.origin.y, 236)
        XCTAssertEqual(frame.size.width, 440)
        XCTAssertEqual(frame.size.height, 560)
    }

    func testBottomTrailingFrameStaysInsideVisibleFrameWhenWindowNearlyFillsScreen() {
        let frame = WindowPlacementPolicy.bottomTrailingFrame(
            windowSize: NSSize(width: 1_200, height: 800),
            visibleFrame: NSRect(x: 100, y: 200, width: 1_200, height: 800),
            trailingMargin: 28,
            bottomMargin: 36
        )

        XCTAssertEqual(frame.origin.x, 100)
        XCTAssertEqual(frame.origin.y, 200)
        XCTAssertEqual(frame.size.width, 1_200)
        XCTAssertEqual(frame.size.height, 800)
    }

    func testWindowSpanningTwoDisplaysIsNotConsideredFullyVisible() {
        let window = NSRect(x: 800, y: 100, width: 600, height: 400)
        let screens = [
            NSRect(x: 0, y: 0, width: 1_000, height: 800),
            NSRect(x: 1_000, y: 0, width: 1_000, height: 800),
        ]

        XCTAssertFalse(WindowPlacementPolicy.isFullyVisible(window, in: screens))
        XCTAssertEqual(
            WindowPlacementPolicy.preferredVisibleFrame(for: window, screens: screens),
            screens[1]
        )
    }

    func testWindowContainedByOneDisplayRemainsVisible() {
        let window = NSRect(x: 100, y: 100, width: 600, height: 400)
        let screens = [NSRect(x: 0, y: 0, width: 1_000, height: 800)]

        XCTAssertTrue(WindowPlacementPolicy.isFullyVisible(window, in: screens))
    }

    func testInteractionVisibleFramePrefersFocusedWindowScreenOverMouseScreen() {
        let screenFrames = [
            NSRect(x: 0, y: 0, width: 1_000, height: 800),
            NSRect(x: 1_000, y: 0, width: 1_000, height: 800),
        ]
        let visibleFrames = [
            NSRect(x: 0, y: 40, width: 1_000, height: 720),
            NSRect(x: 1_000, y: 20, width: 1_000, height: 760),
        ]
        let focusedWindowFrame = NSRect(x: 1_100, y: 120, width: 500, height: 400)
        let mouseLocation = NSPoint(x: 200, y: 200)

        XCTAssertEqual(
            WindowPlacementPolicy.interactionVisibleFrame(
                focusedWindowFrame: focusedWindowFrame,
                mouseLocation: mouseLocation,
                screenFrames: screenFrames,
                visibleFrames: visibleFrames
            ),
            visibleFrames[1]
        )
    }
}
