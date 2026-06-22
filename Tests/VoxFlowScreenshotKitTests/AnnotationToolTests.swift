import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

@MainActor
final class AnnotationToolTests: XCTestCase {
    func testRectangleLikeToolsCreateNormalizedElementsFromDrag() {
        var rectangle = RectangleAnnotationTool()
        rectangle.beginDrawing(at: CGPoint(x: 80, y: 70))
        rectangle.continueDrawing(to: CGPoint(x: 20, y: 10))

        XCTAssertEqual(rectangle.endDrawing(at: CGPoint(x: 20, y: 10))?.bounds, CGRect(x: 20, y: 10, width: 60, height: 60))

        var ellipse = EllipseAnnotationTool()
        ellipse.beginDrawing(at: CGPoint(x: 90, y: 30))
        XCTAssertEqual(ellipse.endDrawing(at: CGPoint(x: 30, y: 90))?.bounds, CGRect(x: 30, y: 30, width: 60, height: 60))
    }

    func testMosaicToolCreatesBrushStrokeFromDrag() {
        var mosaic = MosaicAnnotationTool(brushSize: 12, blockSize: 6)
        mosaic.beginDrawing(at: CGPoint(x: 4, y: 5))
        mosaic.continueDrawing(to: CGPoint(x: 5, y: 5))
        mosaic.continueDrawing(to: CGPoint(x: 14, y: 5))

        guard case .mosaic(let element) = mosaic.endDrawing(at: CGPoint(x: 24, y: 15)) else {
            XCTFail("Expected mosaic annotation")
            return
        }
        XCTAssertEqual(element.points, [
            CGPoint(x: 4, y: 5),
            CGPoint(x: 14, y: 5),
            CGPoint(x: 24, y: 15),
        ])
        XCTAssertEqual(element.brushSize, 12)
        XCTAssertEqual(element.blockSize, 6)
        XCTAssertEqual(element.bounds, CGRect(x: -2, y: -1, width: 32, height: 22))
    }

    func testArrowAndFreehandToolsCreateElementsFromDrag() {
        var arrow = ArrowAnnotationTool()
        arrow.beginDrawing(at: CGPoint(x: 0, y: 0))
        arrow.continueDrawing(to: CGPoint(x: 20, y: 0))

        let arrowElement = arrow.endDrawing(at: CGPoint(x: 20, y: 0))
        XCTAssertEqual(arrowElement?.kind, .arrow)
        XCTAssertEqual(arrowElement?.bounds, CGRect(x: -18, y: -18, width: 56, height: 36))

        var pen = FreehandAnnotationTool()
        pen.beginDrawing(at: CGPoint(x: 0, y: 0))
        pen.continueDrawing(to: CGPoint(x: 1, y: 1))
        pen.continueDrawing(to: CGPoint(x: 4, y: 0))

        guard case .pen(let element) = pen.endDrawing(at: CGPoint(x: 8, y: 0)) else {
            XCTFail("Expected pen annotation")
            return
        }
        XCTAssertEqual(element.points, [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 4, y: 0),
            CGPoint(x: 8, y: 0),
        ])
    }

    func testMarkerAndTextToolsCreateClickBasedElements() {
        var dot = DotMarkerAnnotationTool()
        dot.beginDrawing(at: CGPoint(x: 30, y: 40))
        XCTAssertEqual(dot.endDrawing(at: CGPoint(x: 30, y: 40))?.bounds, CGRect(x: 24, y: 34, width: 12, height: 12))

        var numbered = NumberedMarkerAnnotationTool(nextNumber: 7)
        numbered.beginDrawing(at: CGPoint(x: 50, y: 60))
        guard case .numberedMarker(let marker) = numbered.endDrawing(at: CGPoint(x: 50, y: 60)) else {
            XCTFail("Expected numbered marker annotation")
            return
        }
        XCTAssertEqual(marker.center, CGPoint(x: 50, y: 60))
        XCTAssertEqual(marker.number, 7)

        var text = TextAnnotationTool()
        text.beginDrawing(at: CGPoint(x: 70, y: 80))
        text.updateText("中文标注")

        guard case .text(let textElement) = text.commitText() else {
            XCTFail("Expected text annotation")
            return
        }
        XCTAssertEqual(textElement.position, CGPoint(x: 70, y: 80))
        XCTAssertEqual(textElement.content, "中文标注")
    }

    func testCancelClearsCurrentAnnotation() {
        var rectangle = RectangleAnnotationTool()
        rectangle.beginDrawing(at: CGPoint(x: 0, y: 0))
        rectangle.continueDrawing(to: CGPoint(x: 20, y: 20))

        rectangle.cancelDrawing()

        XCTAssertNil(rectangle.currentAnnotation)
        XCTAssertFalse(rectangle.isActive)
    }
}
