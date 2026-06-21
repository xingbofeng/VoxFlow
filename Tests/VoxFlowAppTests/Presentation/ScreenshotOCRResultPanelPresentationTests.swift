import XCTest

final class ScreenshotOCRResultPanelPresentationTests: XCTestCase {
    func testPanelUsesNativeWindowDraggingInsteadOfIncrementalSwiftUIDragGesture() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenshotOCRResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("window?.performDrag(with: event)"))
        XCTAssertFalse(source.contains("DragGesture()"))
        XCTAssertFalse(source.contains("lastDragTranslation"))
    }

    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
