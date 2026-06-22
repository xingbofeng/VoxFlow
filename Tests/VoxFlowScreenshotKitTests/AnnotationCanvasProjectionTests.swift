import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

final class AnnotationCanvasProjectionTests: XCTestCase {
    func testAspectFitProjectionMapsLetterboxedViewPointToImagePoint() {
        let projection = AnnotationCanvasProjection(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 300, height: 300)
        )

        XCTAssertEqual(projection.fittedImageRect, CGRect(x: 0, y: 75, width: 300, height: 150))
        XCTAssertEqual(projection.imagePoint(fromViewPoint: CGPoint(x: 150, y: 150)), CGPoint(x: 100, y: 50))
        XCTAssertEqual(projection.imagePoint(fromViewPoint: CGPoint(x: 150, y: 40)), nil)
    }

    func testAspectFitProjectionMapsImagePointBackToViewPoint() {
        let projection = AnnotationCanvasProjection(
            imageSize: CGSize(width: 200, height: 100),
            containerSize: CGSize(width: 300, height: 300)
        )

        XCTAssertEqual(projection.viewPoint(fromImagePoint: CGPoint(x: 100, y: 50)), CGPoint(x: 150, y: 150))
    }
}
