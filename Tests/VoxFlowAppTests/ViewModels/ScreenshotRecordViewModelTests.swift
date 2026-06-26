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

    func testDeleteRecordingRemovesPersistedVideoFile() throws {
        let container = try DependencyContainer.inMemory()
        let viewModel = ScreenshotRecordViewModel(
            environment: AppEnvironment(container: container),
            clipboardService: SystemClipboardService()
        )
        let videoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxFlowScreenshotRecordViewModelTests-\(UUID().uuidString).mp4")
        try Data([0, 1, 2, 3]).write(to: videoURL)
        let record = MediaRecord(
            id: "with-video",
            mediaType: .screenRecording,
            videoPath: videoURL.path,
            durationMs: 1_000,
            width: 800,
            height: 600,
            fileSizeBytes: 4,
            audioMode: .none,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try container.mediaRecordRepository.save(record)
        viewModel.load()

        viewModel.deleteRecord(id: "with-video")

        XCTAssertFalse(FileManager.default.fileExists(atPath: videoURL.path))
    }

    func testMediaFiltersReturnAllScreenshotsRecordingsAndFavorites() throws {
        let container = try DependencyContainer.inMemory()
        let viewModel = ScreenshotRecordViewModel(
            environment: AppEnvironment(container: container),
            clipboardService: SystemClipboardService()
        )
        let screenshot = makeRecord(
            id: "screenshot",
            ocrText: "截图",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let favoritedScreenshot = ScreenshotRecord(
            id: "favorite-screenshot",
            ocrText: "收藏截图",
            translatedText: nil,
            summaryText: nil,
            imagePath: nil,
            charCount: 4,
            isFavorited: true,
            createdAt: Date(timeIntervalSince1970: 1_800_000_010),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_010),
            deletedAt: nil
        )
        let recording = MediaRecord(
            id: "recording",
            mediaType: .screenRecording,
            videoPath: "/tmp/recording.mp4",
            durationMs: 2_000,
            width: 1280,
            height: 720,
            fileSizeBytes: 512,
            audioMode: .none,
            createdAt: Date(timeIntervalSince1970: 1_800_000_020),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_020)
        )
        try container.screenshotRecordRepository.save(screenshot)
        try container.screenshotRecordRepository.save(favoritedScreenshot)
        try container.mediaRecordRepository.save(recording)

        viewModel.load()
        XCTAssertEqual(viewModel.records.map(\.id), ["recording", "favorite-screenshot", "screenshot"])

        viewModel.selectedFilter = .screenshots
        XCTAssertEqual(viewModel.records.map(\.id), ["favorite-screenshot", "screenshot"])

        viewModel.selectedFilter = .recordings
        XCTAssertEqual(viewModel.records.map(\.id), ["recording"])

        viewModel.selectedFilter = .favorites
        XCTAssertEqual(viewModel.records.map(\.id), ["favorite-screenshot"])
    }

    func testMediaStatsIncludeOldScreenshotRowsAndRecordings() throws {
        let container = try DependencyContainer.inMemory()
        let viewModel = ScreenshotRecordViewModel(
            environment: AppEnvironment(container: container),
            clipboardService: SystemClipboardService()
        )
        try container.screenshotRecordRepository.save(
            makeRecord(id: "screenshot", ocrText: "截图", createdAt: Date())
        )
        try container.mediaRecordRepository.save(
            MediaRecord(
                id: "recording",
                mediaType: .screenRecording,
                videoPath: "/tmp/recording.mp4",
                durationMs: 1_000,
                width: 800,
                height: 600,
                fileSizeBytes: 256,
                audioMode: .microphone,
                createdAt: Date(),
                updatedAt: Date()
            )
        )

        viewModel.load()

        XCTAssertEqual(viewModel.mediaStats?.totalMedia, 2)
        XCTAssertEqual(viewModel.mediaStats?.screenshotCount, 1)
        XCTAssertEqual(viewModel.mediaStats?.recordingCount, 1)
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
