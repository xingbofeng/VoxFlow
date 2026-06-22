import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

final class SelectionOverlayPresentationTests: XCTestCase {
    func testPresentationProvidesBorderDimSizeReadoutAndResizeHandles() {
        let state = SelectionState(
            displayFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            displayScale: 2,
            startPoint: CGPoint(x: 300, y: 220),
            currentPoint: CGPoint(x: 120, y: 80)
        )

        let presentation = SelectionOverlayPresentation(state: state)

        XCTAssertEqual(presentation.selectionRect, CGRect(x: 120, y: 80, width: 180, height: 140))
        XCTAssertEqual(presentation.sizeReadout, "180 × 140")
        XCTAssertEqual(presentation.resizeHandleRects.count, 8)
        XCTAssertEqual(presentation.resizeHandleRects.first?.size, CGSize(width: 8, height: 8))
        XCTAssertGreaterThan(presentation.outsideDimmingAlpha, 0)
    }
}
