import XCTest
@testable import VoxFlowApp

final class MediaRecordRepositoryTests: XCTestCase {
    private var queue: DatabaseQueue!
    private var repository: SQLiteMediaRecordRepository!
    private var screenshotRepository: SQLiteScreenshotRecordRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        repository = SQLiteMediaRecordRepository(databaseQueue: queue)
        screenshotRepository = SQLiteScreenshotRecordRepository(databaseQueue: queue)
    }

    override func tearDown() {
        repository = nil
        screenshotRepository = nil
        queue = nil
        super.tearDown()
    }

    // MARK: - 兼容性：旧截图行默认 screenshot 媒体类型

    func testOldScreenshotRowDefaultsToScreenshotMediaType() throws {
        let screenshot = makeScreenshotRecord(ocrText: "旧截图文本")
        try screenshotRepository.save(screenshot)

        let media = try repository.record(id: screenshot.id)

        XCTAssertEqual(media?.mediaType, .screenshot)
        XCTAssertEqual(media?.ocrText, "旧截图文本")
        XCTAssertNil(media?.videoPath)
        XCTAssertEqual(media?.audioMode, MediaAudioMode.none)
        XCTAssertEqual(media?.durationMs, 0)
    }

    // MARK: - 录屏行存储视频元数据

    func testScreenRecordingRowStoresVideoMetadata() throws {
        let recording = makeRecordingRecord(
            videoPath: "/tmp/rec.mp4",
            durationMs: 5_000,
            width: 1920,
            height: 1080,
            fileSizeBytes: 1_024,
            audioMode: .microphone
        )
        try repository.save(recording)

        let fetched = try repository.record(id: recording.id)

        XCTAssertEqual(fetched?.mediaType, .screenRecording)
        XCTAssertEqual(fetched?.videoPath, "/tmp/rec.mp4")
        XCTAssertEqual(fetched?.durationMs, 5_000)
        XCTAssertEqual(fetched?.width, 1920)
        XCTAssertEqual(fetched?.height, 1080)
        XCTAssertEqual(fetched?.fileSizeBytes, 1_024)
        XCTAssertEqual(fetched?.audioMode, .microphone)
    }

    // MARK: - 筛选

    func testAllFilterReturnsBothScreenshotsAndRecordings() throws {
        try repository.save(makeRecordingRecord())
        try screenshotRepository.save(makeScreenshotRecord(ocrText: "截图"))

        let page = try repository.page(limit: 10, offset: 0, filter: .all, search: nil)

        XCTAssertEqual(page.records.count, 2)
        XCTAssertEqual(page.totalCount, 2)
    }

    func testScreenshotsFilterExcludesRecordings() throws {
        try repository.save(makeRecordingRecord())
        try screenshotRepository.save(makeScreenshotRecord(ocrText: "截图"))

        let page = try repository.page(limit: 10, offset: 0, filter: .screenshots, search: nil)

        XCTAssertEqual(page.records.count, 1)
        XCTAssertEqual(page.records.first?.mediaType, .screenshot)
    }

    func testRecordingsFilterExcludesScreenshots() throws {
        try repository.save(makeRecordingRecord())
        try screenshotRepository.save(makeScreenshotRecord(ocrText: "截图"))

        let page = try repository.page(limit: 10, offset: 0, filter: .recordings, search: nil)

        XCTAssertEqual(page.records.count, 1)
        XCTAssertEqual(page.records.first?.mediaType, .screenRecording)
    }

    func testFavoritesFilterReturnsFavoritedMediaOfBothTypes() throws {
        try repository.save(makeRecordingRecord(isFavorited: true))
        try screenshotRepository.save(makeScreenshotRecord(ocrText: "普通截图"))
        let favoritedScreenshot = makeScreenshotRecord(ocrText: "收藏截图", isFavorited: true)
        try screenshotRepository.save(favoritedScreenshot)

        let page = try repository.page(limit: 10, offset: 0, filter: .favorites, search: nil)

        XCTAssertEqual(page.records.count, 2)
        XCTAssertTrue(page.records.allSatisfy { $0.isFavorited })
    }

    // MARK: - 统计

    func testStatsCountsByMediaType() throws {
        try screenshotRepository.save(makeScreenshotRecord(ocrText: "截图1"))
        try repository.save(makeRecordingRecord())
        try repository.save(makeRecordingRecord())

        let stats = try repository.stats()

        XCTAssertEqual(stats.totalMedia, 3)
        XCTAssertEqual(stats.screenshotCount, 1)
        XCTAssertEqual(stats.recordingCount, 2)
    }

    func testStatsTodayMediaCountsTodayRecords() throws {
        let now = Date()
        try repository.save(makeRecordingRecord(createdAt: now))
        try repository.save(makeRecordingRecord(createdAt: Date(timeIntervalSince1970: 1_700_000_000)))

        let stats = try repository.stats()

        XCTAssertEqual(stats.todayMedia, 1)
        XCTAssertEqual(stats.totalMedia, 2)
    }

    // MARK: - 软删与收藏

    func testSoftDeleteHidesFromList() throws {
        let recording = makeRecordingRecord()
        try repository.save(recording)

        try repository.softDelete(id: recording.id, deletedAt: Date())

        let page = try repository.page(limit: 10, offset: 0, filter: .all, search: nil)
        XCTAssertFalse(page.records.map(\.id).contains(recording.id))
    }

    func testToggleFavoriteUpdatesRecord() throws {
        let recording = makeRecordingRecord(isFavorited: false)
        try repository.save(recording)

        try repository.toggleFavorite(id: recording.id, isFavorited: true, updatedAt: Date())

        let fetched = try repository.record(id: recording.id)
        XCTAssertTrue(fetched?.isFavorited ?? false)
    }

    // MARK: - 搜索

    func testSearchMatchesOcrTextAcrossTypes() throws {
        try screenshotRepository.save(makeScreenshotRecord(ocrText: " VoxFlow 截图"))
        try repository.save(makeRecordingRecord(ocrText: " VoxFlow 录屏"))

        let page = try repository.page(limit: 10, offset: 0, filter: .all, search: "VoxFlow")

        XCTAssertEqual(page.records.count, 2)
    }

    // MARK: - 诊断：addColumnIfNeeded 在 BEGIN IMMEDIATE 事务内是否补列

    func testDiagnosticAddColumnInsideImmediateTransaction() throws {
        let q = try DatabaseQueue(connection: .inMemory())
        try q.write { connection in
            try connection.execute(
                """
                CREATE TABLE screenshot_records (
                    id TEXT PRIMARY KEY, ocr_text TEXT NOT NULL DEFAULT '',
                    translated_text TEXT, summary_text TEXT, image_path TEXT,
                    char_count INTEGER NOT NULL DEFAULT 0, is_favorited INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT
                )
                """
            )
        }
        // 完整模拟 migration 16：同事务内 addColumn × 8 + applyBundledSchema（整个 schema SQL）。
        let schemaSQL = try AppDatabase.loadBundledSchemaSQL()
        let columns: [String]
        do {
            try q.write { connection in
                try connection.execute("BEGIN IMMEDIATE TRANSACTION")
                let mediaColumns: [(String, String)] = [
                    ("media_type", "TEXT NOT NULL DEFAULT 'screenshot'"),
                    ("video_path", "TEXT"),
                    ("thumbnail_path", "TEXT"),
                    ("duration_ms", "INTEGER NOT NULL DEFAULT 0"),
                    ("width", "INTEGER NOT NULL DEFAULT 0"),
                    ("height", "INTEGER NOT NULL DEFAULT 0"),
                    ("file_size_bytes", "INTEGER NOT NULL DEFAULT 0"),
                    ("audio_mode", "TEXT NOT NULL DEFAULT 'none'")
                ]
                for (column, definition) in mediaColumns {
                    try connection.addColumnIfNeeded(
                        table: "screenshot_records",
                        column: column,
                        definition: definition
                    )
                }
                try connection.execute(schemaSQL)
                try connection.execute("COMMIT")
            }
            columns = try q.read { connection -> [String] in
                let statement = try connection.prepare("PRAGMA table_info('screenshot_records')")
                var names: [String] = []
                while try statement.step() {
                    names.append(statement.columnString(at: 1) ?? "")
                }
                return names
            }
        } catch {
            let cols = (try? q.read { connection -> [String] in
                let statement = try connection.prepare("PRAGMA table_info('screenshot_records')")
                var names: [String] = []
                while try statement.step() {
                    names.append(statement.columnString(at: 1) ?? "")
                }
                return names
            }) ?? []
            XCTFail("事务内 addColumn + schema 失败：\(error)，列：\(cols)")
            return
        }
        XCTAssertTrue(columns.contains("media_type"), "事务内 addColumn 未补列：\(columns)")
    }

    // MARK: - 迁移兼容：老库无媒体列时迁移补齐

    func testMigrationAddsMediaColumnsToLegacyScreenshotTable() throws {
        let legacyQueue = try DatabaseQueue(connection: .inMemory())
        try legacyQueue.write { connection in
            try connection.execute(
                """
                CREATE TABLE schema_migrations (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    applied_at TEXT NOT NULL
                );
                """
            )
            // 模拟真实老库：migration 1-15 均已应用，screenshot_records 仍是旧结构（无媒体列）。
            for id in 1...15 {
                try connection.execute(
                    "INSERT INTO schema_migrations (id, name, applied_at) VALUES (\(id), 'legacy', '2026-06-23T00:00:00Z')"
                )
            }
            try connection.execute(
                """
                CREATE TABLE screenshot_records (
                    id TEXT PRIMARY KEY,
                    ocr_text TEXT NOT NULL DEFAULT '',
                    translated_text TEXT,
                    summary_text TEXT,
                    image_path TEXT,
                    char_count INTEGER NOT NULL DEFAULT 0,
                    is_favorited INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    deleted_at TEXT
                );
                """
            )
            try connection.execute(
                """
                INSERT INTO screenshot_records (id, ocr_text, created_at, updated_at)
                VALUES ('legacy-1', '旧数据', '2026-06-01T00:00:00Z', '2026-06-01T00:00:00Z');
                """
            )
        }

        try AppDatabase.migrator().migrate(legacyQueue)

        let columns = try legacyQueue.read { connection -> [String] in
            let statement = try connection.prepare("PRAGMA table_info('screenshot_records')")
            var names: [String] = []
            while try statement.step() {
                if let name = statement.columnString(at: 1) {
                    names.append(name)
                }
            }
            return names
        }
        XCTAssertTrue(columns.contains("media_type"), "media_type 列未补齐，实际列：\(columns)")

        let repaired = SQLiteMediaRecordRepository(databaseQueue: legacyQueue)

        let legacy = try repaired.record(id: "legacy-1")
        XCTAssertEqual(legacy?.mediaType, .screenshot)
        XCTAssertEqual(legacy?.ocrText, "旧数据")

        let newRecording = makeRecordingRecord(videoPath: "/tmp/new.mp4")
        try repaired.save(newRecording)
        XCTAssertEqual(try repaired.record(id: newRecording.id)?.videoPath, "/tmp/new.mp4")
    }

    // MARK: - Helpers

    private func makeScreenshotRecord(
        id: String = UUID().uuidString,
        ocrText: String,
        isFavorited: Bool = false,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> ScreenshotRecord {
        ScreenshotRecord(
            id: id,
            ocrText: ocrText,
            translatedText: nil,
            summaryText: nil,
            imagePath: "/tmp/shot-\(id).png",
            charCount: ocrText.count,
            isFavorited: isFavorited,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        )
    }

    private func makeRecordingRecord(
        id: String = UUID().uuidString,
        ocrText: String = "",
        videoPath: String = "/tmp/rec.mp4",
        durationMs: Int = 3_000,
        width: Int = 1280,
        height: Int = 720,
        fileSizeBytes: Int = 512,
        audioMode: MediaAudioMode = .none,
        isFavorited: Bool = false,
        createdAt: Date = Date()
    ) -> MediaRecord {
        MediaRecord(
            id: id,
            mediaType: .screenRecording,
            ocrText: ocrText,
            videoPath: videoPath,
            durationMs: durationMs,
            width: width,
            height: height,
            fileSizeBytes: fileSizeBytes,
            audioMode: audioMode,
            isFavorited: isFavorited,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}
