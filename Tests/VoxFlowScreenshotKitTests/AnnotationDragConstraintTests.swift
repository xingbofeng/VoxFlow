import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

final class AnnotationDragConstraintTests: XCTestCase {
    func testSquareToolsConstrainEndPointToSquareWhenShiftIsPressed() {
        let start = CGPoint(x: 10, y: 20)
        let end = CGPoint(x: 80, y: 50)

        let constrained = AnnotationDragConstraint.constrainedEndPoint(
            start: start,
            end: end,
            tool: .rectangle,
            isShiftPressed: true
        )

        XCTAssertEqual(constrained, CGPoint(x: 80, y: 90))
    }

    func testArrowConstrainsToNearest45DegreeWhenShiftIsPressed() {
        let start = CGPoint(x: 10, y: 10)
        let end = CGPoint(x: 60, y: 30)

        let constrained = AnnotationDragConstraint.constrainedEndPoint(
            start: start,
            end: end,
            tool: .arrow,
            isShiftPressed: true
        )

        XCTAssertEqual(constrained.x, 60, accuracy: 0.001)
        XCTAssertEqual(constrained.y, 10, accuracy: 0.001)
    }

    func testConstraintLeavesPointUnchangedWhenShiftIsNotPressed() {
        let end = CGPoint(x: 80, y: 50)

        XCTAssertEqual(
            AnnotationDragConstraint.constrainedEndPoint(
                start: CGPoint(x: 10, y: 20),
                end: end,
                tool: .ellipse,
                isShiftPressed: false
            ),
            end
        )
    }
}
