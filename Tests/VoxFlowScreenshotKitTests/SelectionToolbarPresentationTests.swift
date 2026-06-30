import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

final class SelectionToolbarPresentationTests: XCTestCase {
    func testDefaultToolbarPreservesAnnotationToolsAndTerminalActions() {
        let presentation = SelectionToolbarPresentation.default

            XCTAssertEqual(
                presentation.items.map(\.role),
                [
                    .select,
                    .pen,
                    .circle,
                    .rectangle,
                    .arrow,
                    .dotMarker,
                    .numberedMarker,
                    .text,
                    .mosaic,
                    .scrollCapture,
                    .textRecognition,
                    .translate,
                    .screenRecording,
                    .color,
                    .lineWidth,
                    .fontSize,
                    .copy,
                    .paste,
                    .duplicate,
                    .undo,
                    .redo,
                    .download,
                    .cancel,
                    .complete,
                ]
        )
        XCTAssertEqual(presentation.items.first?.systemImageName, "cursorarrow")
        XCTAssertEqual(presentation.items.first { $0.role == .text }?.systemImageName, "t.square")
        XCTAssertEqual(
            presentation.items.first { $0.role == .scrollCapture }?.systemImageName,
            "arrow.up.and.down.text.horizontal"
        )
        XCTAssertEqual(presentation.items.first { $0.role == .textRecognition }?.systemImageName, "text.viewfinder")
        XCTAssertEqual(presentation.items.first { $0.role == .fontSize }?.systemImageName, "textformat.size")
        XCTAssertEqual(presentation.items.last?.systemImageName, "checkmark")
    }

    func testToolbarFrameStaysInsideVisibleBoundsNearSelectionBottom() {
        let presentation = SelectionToolbarPresentation.default
        let frame = presentation.toolbarFrame(
            for: CGRect(x: 720, y: 820, width: 240, height: 70),
            visibleBounds: CGRect(x: 0, y: 0, width: 1000, height: 900)
        )

        XCTAssertLessThanOrEqual(frame.maxX, 1000)
        XCTAssertLessThanOrEqual(frame.maxY, 900)
        XCTAssertGreaterThanOrEqual(frame.minX, 0)
        XCTAssertLessThan(frame.minY, 820)
    }
}
