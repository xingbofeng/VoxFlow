import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

final class AnnotationDocumentTests: XCTestCase {
    func testDocumentStoresRequiredAnnotationElementTypes() {
        let style = ScreenshotAnnotationStyle.default
        let textStyle = ScreenshotAnnotationTextStyle.default
        var document = AnnotationDocument()

        document.add(.pen(FreehandAnnotationElement(points: [CGPoint(x: 1, y: 1), CGPoint(x: 8, y: 8)], style: style)))
        document.add(.ellipse(EllipseAnnotationElement(rect: CGRect(x: 10, y: 10, width: 30, height: 20), style: style)))
        document.add(.rectangle(RectangleAnnotationElement(rect: CGRect(x: 20, y: 20, width: 40, height: 24), style: style)))
        document.add(.arrow(ArrowAnnotationElement(startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 20, y: 8), style: style)))
        document.add(.dotMarker(DotMarkerAnnotationElement(center: CGPoint(x: 44, y: 44), radius: 7, style: style)))
        document.add(.numberedMarker(NumberedMarkerAnnotationElement(center: CGPoint(x: 60, y: 60), number: 1, radius: 9, style: style)))
        document.add(.text(TextAnnotationElement(position: CGPoint(x: 70, y: 70), content: "备注", style: textStyle)))
        document.add(.mosaic(MosaicAnnotationElement(
            points: [CGPoint(x: 80, y: 80), CGPoint(x: 110, y: 110)],
            brushSize: 18,
            blockSize: 8
        )))

        XCTAssertEqual(document.elements.map(\.kind), [
            .pen,
            .ellipse,
            .rectangle,
            .arrow,
            .dotMarker,
            .numberedMarker,
            .text,
            .mosaic,
        ])
    }

    func testRemoveAndClearAreUndoable() {
        var document = AnnotationDocument()
        let first = AnnotationElement.rectangle(
            RectangleAnnotationElement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        )
        let second = AnnotationElement.arrow(
            ArrowAnnotationElement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, startPoint: .zero, endPoint: CGPoint(x: 20, y: 20))
        )
        document.add(first)
        document.add(second)

        document.removeElement(id: first.id)
        XCTAssertEqual(document.elements, [second])

        document.undo()
        XCTAssertEqual(document.elements, [first, second])

        document.clear()
        XCTAssertTrue(document.elements.isEmpty)

        document.undo()
        XCTAssertEqual(document.elements, [first, second])
    }

    func testRedoReappliesUndoneChangeWithoutCorruptingDocument() {
        var document = AnnotationDocument()
        let element = AnnotationElement.rectangle(
            RectangleAnnotationElement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        )
        document.add(element)

        document.undo()
        XCTAssertTrue(document.elements.isEmpty)

        document.redo()
        XCTAssertEqual(document.elements, [element])
    }

    func testSelectedAnnotationCanMoveAndDelete() {
        var document = AnnotationDocument()
        let element = AnnotationElement.rectangle(
            RectangleAnnotationElement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, rect: CGRect(x: 5, y: 6, width: 20, height: 30))
        )
        document.add(element)

        document.selectElement(id: element.id)
        document.moveSelectedElement(by: CGSize(width: 4, height: -2))

        XCTAssertEqual(
            document.elements.first?.bounds,
            CGRect(x: 9, y: 4, width: 20, height: 30)
        )

        document.deleteSelectedElement()
        XCTAssertTrue(document.elements.isEmpty)
    }

    func testMultipleSelectedAnnotationsMoveDeleteAndUndoTogether() {
        var document = AnnotationDocument()
        let first = AnnotationElement.rectangle(
            RectangleAnnotationElement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!, rect: CGRect(x: 5, y: 6, width: 20, height: 30))
        )
        let second = AnnotationElement.ellipse(
            EllipseAnnotationElement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!, rect: CGRect(x: 50, y: 60, width: 15, height: 25))
        )
        let third = AnnotationElement.arrow(
            ArrowAnnotationElement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!, startPoint: CGPoint(x: 80, y: 80), endPoint: CGPoint(x: 100, y: 100))
        )
        document.add(first)
        document.add(second)
        document.add(third)

        document.selectElement(id: first.id)
        document.toggleElementSelection(id: second.id)
        document.moveSelectedElement(by: CGSize(width: 4, height: -2))

        XCTAssertEqual(document.selectedElementIDs, [first.id, second.id])
        XCTAssertEqual(document.elements[0].bounds, CGRect(x: 9, y: 4, width: 20, height: 30))
        XCTAssertEqual(document.elements[1].bounds, CGRect(x: 54, y: 58, width: 15, height: 25))
        XCTAssertEqual(document.elements[2].id, third.id)

        document.deleteSelectedElement()
        XCTAssertEqual(document.elements, [third])

        document.undo()
        XCTAssertEqual(document.elements.count, 3)
        XCTAssertEqual(document.selectedElementIDs, [first.id, second.id])
    }

    func testSelectElementsIntersectingRectSupportsMarqueeSelectionAndExtension() {
        var document = AnnotationDocument()
        let first = AnnotationElement.rectangle(
            RectangleAnnotationElement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000106")!, rect: CGRect(x: 5, y: 6, width: 20, height: 30))
        )
        let second = AnnotationElement.ellipse(
            EllipseAnnotationElement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000107")!, rect: CGRect(x: 50, y: 60, width: 15, height: 25))
        )
        let third = AnnotationElement.arrow(
            ArrowAnnotationElement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000108")!, startPoint: CGPoint(x: 120, y: 120), endPoint: CGPoint(x: 140, y: 140))
        )
        document.add(first)
        document.add(second)
        document.add(third)

        document.selectElements(intersecting: CGRect(x: 0, y: 0, width: 80, height: 90))

        XCTAssertEqual(document.selectedElementIDs, [first.id, second.id])

        document.selectElements(
            intersecting: CGRect(x: 110, y: 110, width: 40, height: 40),
            extendingSelection: true
        )

        XCTAssertEqual(document.selectedElementIDs, [first.id, second.id, third.id])

        document.selectElements(intersecting: CGRect(x: 200, y: 200, width: 20, height: 20))

        XCTAssertTrue(document.selectedElementIDs.isEmpty)
    }

    func testSelectedAnnotationStyleUpdatesAllSelectedNonTextElements() {
        var document = AnnotationDocument()
        let first = AnnotationElement.rectangle(
            RectangleAnnotationElement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000104")!, rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        )
        let second = AnnotationElement.arrow(
            ArrowAnnotationElement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000105")!, startPoint: CGPoint(x: 20, y: 20), endPoint: CGPoint(x: 40, y: 40))
        )
        document.add(first)
        document.add(second)
        document.selectElement(id: first.id)
        document.toggleElementSelection(id: second.id)

        let style = ScreenshotAnnotationStyle(color: .red, lineWidth: 8)
        document.updateSelectedStyle(style)

        guard case .rectangle(let updatedFirst) = document.elements[0],
              case .arrow(let updatedSecond) = document.elements[1] else {
            XCTFail("Expected rectangle and arrow annotations")
            return
        }
        XCTAssertEqual(updatedFirst.style, style)
        XCTAssertEqual(updatedSecond.style, style)
    }

    func testDragInteractionRecordsSingleUndoSnapshot() {
        var document = AnnotationDocument()
        let element = AnnotationElement.rectangle(
            RectangleAnnotationElement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!, rect: CGRect(x: 5, y: 6, width: 20, height: 30))
        )
        document.add(element)
        document.selectElement(id: element.id)

        document.beginUndoGroup()
        document.moveSelectedElement(by: CGSize(width: 4, height: 0), recordsUndo: false)
        document.moveSelectedElement(by: CGSize(width: 3, height: 0), recordsUndo: false)

        document.undo()

        XCTAssertEqual(document.elements.first?.bounds, CGRect(x: 5, y: 6, width: 20, height: 30))
    }

    func testHitTestingSelectsTopmostElementUsingShotShotSelectionRules() {
        var document = AnnotationDocument()
        let bottom = AnnotationElement.rectangle(
            RectangleAnnotationElement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, rect: CGRect(x: 10, y: 10, width: 80, height: 50))
        )
        let top = AnnotationElement.ellipse(
            EllipseAnnotationElement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!, rect: CGRect(x: 20, y: 20, width: 50, height: 30))
        )
        document.add(bottom)
        document.add(top)

        XCTAssertEqual(document.hitTestElement(at: CGPoint(x: 30, y: 30)), top.id)
        XCTAssertNil(document.hitTestElement(at: CGPoint(x: 180, y: 30)))
    }

    func testSelectedRectangleCanResizeFromCornerHandle() {
        var document = AnnotationDocument()
        let element = AnnotationElement.rectangle(
            RectangleAnnotationElement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!, rect: CGRect(x: 20, y: 30, width: 60, height: 40))
        )
        document.add(element)
        document.selectElement(id: element.id)

        document.resizeSelectedElement(handle: .endPoint, to: CGPoint(x: 120, y: 100))

        XCTAssertEqual(
            document.elements.first?.bounds,
            CGRect(x: 20, y: 30, width: 100, height: 70)
        )
    }

    func testSelectedAnnotationStyleCanBeUpdated() {
        var document = AnnotationDocument()
        let element = AnnotationElement.arrow(
            ArrowAnnotationElement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 20, y: 20))
        )
        document.add(element)
        document.selectElement(id: element.id)

        let style = ScreenshotAnnotationStyle(color: .red, lineWidth: 6)
        document.updateSelectedStyle(style)

        guard case .arrow(let updated) = document.elements.first else {
            XCTFail("Expected arrow annotation")
            return
        }
        XCTAssertEqual(updated.style, style)
    }
}
