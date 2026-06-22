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

    private func makeRecord(id: String, ocrText: String, createdAt: Date) -> ScreenshotRecord {
        ScreenshotRecord(
            id: id,
            ocrText: ocrText,
            translatedText: nil,
            summaryText: nil,
            imagePath: nil,
            charCount: ocrText.count,
            isFavorited: false,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        )
    }
}
