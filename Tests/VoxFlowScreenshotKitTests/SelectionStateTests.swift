import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

final class SelectionStateTests: XCTestCase {
    func testNormalizedRectIsStableRegardlessOfDragDirection() {
        let state = SelectionState(
            displayFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            displayScale: 1,
            startPoint: CGPoint(x: 300, y: 220),
            currentPoint: CGPoint(x: 120, y: 80)
        )

        XCTAssertEqual(state.normalizedRect, CGRect(x: 120, y: 80, width: 180, height: 140))
    }

    func testPixelRectConvertsDisplayRelativePointsUsingRetinaScale() {
        let state = SelectionState(
            displayFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            displayScale: 2,
            startPoint: CGPoint(x: 10, y: 20),
            currentPoint: CGPoint(x: 110, y: 70)
        )

        XCTAssertEqual(state.pixelRect, CGRect(x: 20, y: 40, width: 200, height: 100))
    }

    func testPixelRectIsRelativeToTheSelectedDisplayFrame() {
        let state = SelectionState(
            displayFrame: CGRect(x: 1440, y: 0, width: 800, height: 600),
            displayScale: 2,
            startPoint: CGPoint(x: 1500, y: 50),
            currentPoint: CGPoint(x: 1580, y: 130)
        )

        XCTAssertEqual(state.pixelRect, CGRect(x: 120, y: 100, width: 160, height: 160))
    }

    func testMinimumSizeRejectsAccidentalTinyDrag() {
        let tiny = SelectionState(
            displayFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            displayScale: 2,
            startPoint: CGPoint(x: 10, y: 10),
            currentPoint: CGPoint(x: 17, y: 18),
            minimumSizePoints: 12
        )
        let valid = SelectionState(
            displayFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            displayScale: 2,
            startPoint: CGPoint(x: 10, y: 10),
            currentPoint: CGPoint(x: 24, y: 24),
            minimumSizePoints: 12
        )

        XCTAssertFalse(tiny.isValidSelection)
        XCTAssertTrue(valid.isValidSelection)
    }

    func testMovingSelectionKeepsSizeAndOffsetsRect() {
        let state = SelectionState(
            displayFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            displayScale: 2,
            startPoint: CGPoint(x: 100, y: 100),
            currentPoint: CGPoint(x: 200, y: 200)
        )

        let moved = state.movingSelection(by: CGSize(width: 20, height: -10))

        XCTAssertEqual(moved.normalizedRect, CGRect(x: 120, y: 90, width: 100, height: 100))
    }

    func testResizingSelectionFromHandleUpdatesSelectedCorner() {
        let state = SelectionState(
            displayFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            displayScale: 2,
            startPoint: CGPoint(x: 100, y: 100),
            currentPoint: CGPoint(x: 200, y: 200)
        )

        let resized = state.resizingSelection(handle: .bottomRight, to: CGPoint(x: 240, y: 260))

        XCTAssertEqual(resized.normalizedRect, CGRect(x: 100, y: 100, width: 140, height: 160))
    }
}
