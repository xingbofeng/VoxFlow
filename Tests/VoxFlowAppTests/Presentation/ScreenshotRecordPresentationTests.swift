import XCTest

final class ScreenshotRecordPresentationTests: XCTestCase {
    func testDetailActionsUseCompactIconToolbarAndOfferImageCopy() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Views/ScreenshotRecordDetailView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("recordActionIcon("))
        XCTAssertTrue(source.contains("viewModel.copyImage(id: record.id)"))
        XCTAssertTrue(source.contains(".buttonStyle(.plain)"))
        XCTAssertFalse(source.contains(".buttonStyle(.bordered)"))
        XCTAssertFalse(source.contains("Label(\"复制文字\""))
    }

    func testRecordCardsContainImagesWithoutCroppingAndCanCopyImages() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Views/ScreenshotRecordView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".scaledToFit()"))
        XCTAssertFalse(source.contains(".scaledToFill()"))
        XCTAssertTrue(source.contains("viewModel.copyImage(id: record.id)"))
        XCTAssertTrue(source.contains("help: \"复制图片\""))
    }

    func testRecordImageViewportsStayFixedForWideAndTallScreenshots() throws {
        let listSource = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Views/ScreenshotRecordView.swift"),
            encoding: .utf8
        )
        let detailSource = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Views/ScreenshotRecordDetailView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(listSource.contains("private let thumbnailHeight: CGFloat = 150"))
        XCTAssertTrue(listSource.contains(".frame(height: thumbnailHeight)"))
        XCTAssertTrue(listSource.contains(".clipped()"))

        XCTAssertTrue(detailSource.contains("GeometryReader"))
        XCTAssertTrue(detailSource.contains("ScrollView(.vertical)"))
        XCTAssertTrue(detailSource.contains(".frame(width: proxy.size.width, height: proxy.size.height)"))
        XCTAssertTrue(detailSource.contains(".clipped()"))
    }

    func testRecognizedTextScrollAreaUsesRemainingDetailHeight() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Views/ScreenshotRecordDetailView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains(".frame(maxHeight: 120)"))
        XCTAssertTrue(source.contains("ocrSection"))
        XCTAssertTrue(source.contains(".layoutPriority(1)"))
        XCTAssertTrue(source.contains(".frame(maxHeight: .infinity, alignment: .top)"))
    }

    func testDetailRecognizedTextScrollAreaCanUseRemainingInfoPanelHeight() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Views/ScreenshotRecordDetailView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains(".frame(maxHeight: 120)"))
        XCTAssertTrue(source.contains("ocrSection"))
        XCTAssertTrue(source.contains(".layoutPriority(1)"))
        XCTAssertTrue(source.contains(".frame(maxHeight: .infinity"))
    }

    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
