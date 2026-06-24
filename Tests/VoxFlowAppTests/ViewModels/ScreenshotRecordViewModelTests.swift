import XCTest
@testable import VoxFlowApp

@MainActor
final class ScreenshotRecordViewModelTests: XCTestCase {
    func testExternalInsertRefreshShowsNewestRecordEvenWhenPreviousFiltersWouldHideIt() throws {
        let container = try DependencyContainer.inMemory()
        let viewModel = ScreenshotRecordViewModel(
            environment: AppEnvironment(container: container),
            clipboardService: SystemClipboardService()
        )
        let oldRecord = makeRecord(id: "old", ocrText: "旧搜索词", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let newRecord = makeRecord(id: "new", ocrText: "新截图", createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        try container.screenshotRecordRepository.save(oldRecord)
        viewModel.updateSearch("旧搜索词")
        viewModel.onlyFavorites = true

        try container.screenshotRecordRepository.save(newRecord)
        viewModel.refreshAfterExternalInsert()

        XCTAssertFalse(viewModel.onlyFavorites)
        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertEqual(viewModel.records.first?.id, "new")
    }

    func testDeleteRecordRemovesPersistedImageFile() throws {
        let container = try DependencyContainer.inMemory()
        let viewModel = ScreenshotRecordViewModel(
            environment: AppEnvironment(container: container),
            clipboardService: SystemClipboardService()
        )
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxFlowScreenshotRecordViewModelTests-\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)
        let record = makeRecord(
            id: "with-image",
            ocrText: "截图",
            imagePath: imageURL.path,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try container.screenshotRecordRepository.save(record)
        viewModel.load()

        viewModel.deleteRecord(id: "with-image")

        XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path))
    }

    func testScreenshotImageCacheUsesBoundedNSCache() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/ViewModels/ScreenshotRecordViewModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("NSCache<NSString, NSImage>"))
        XCTAssertTrue(source.contains("countLimit"))
        XCTAssertTrue(source.contains("totalCostLimit"))
    }

    private func makeRecord(
        id: String,
        ocrText: String,
        imagePath: String? = nil,
        createdAt: Date
    ) -> ScreenshotRecord {
        ScreenshotRecord(
            id: id,
            ocrText: ocrText,
            translatedText: nil,
            summaryText: nil,
            imagePath: imagePath,
            charCount: ocrText.count,
            isFavorited: false,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        )
    }
}
