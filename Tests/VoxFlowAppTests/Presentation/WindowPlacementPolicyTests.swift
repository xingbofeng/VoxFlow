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
}
