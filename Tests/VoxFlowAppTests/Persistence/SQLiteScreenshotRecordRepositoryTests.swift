import XCTest
@testable import VoxFlowApp

final class SQLiteScreenshotRecordRepositoryTests: XCTestCase {
    private var repository: SQLiteScreenshotRecordRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        repository = SQLiteScreenshotRecordRepository(databaseQueue: queue)
    }

    override func tearDown() {
        repository = nil
        super.tearDown()
    }

    func testSaveAndFetchRecord() throws {
        let record = makeRecord(ocrText: "Hello World")

        try repository.save(record)

        let fetched = try repository.record(id: record.id)
        XCTAssertEqual(fetched, record)
    }

    func testRequiredRuntimeTablesRepairCreatesScreenshotRecordsWhenMigrationWasMarkedApplied() throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        try queue.write { connection in
            try connection.execute(
                """
                CREATE TABLE schema_migrations (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    applied_at TEXT NOT NULL
                );
                INSERT INTO schema_migrations (id, name, applied_at)
                VALUES (11, 'old-conflicting-migration', '2026-06-23T00:00:00Z');
                """
            )
        }

        try AppDatabase.ensureRequiredRuntimeTables(queue)
        let repairedRepository = SQLiteScreenshotRecordRepository(databaseQueue: queue)
        let record = makeRecord(ocrText: "修复后可保存")

        try repairedRepository.save(record)

        XCTAssertEqual(try repairedRepository.list(filter: .all, search: nil).map(\.id), [record.id])
    }

    func testSaveUpsertsExistingRecord() throws {
        var record = makeRecord(ocrText: "原始文本")
        try repository.save(record)

        record = ScreenshotRecord(
            id: record.id,
            ocrText: "更新后的文本",
            translatedText: "Translated",
            summaryText: nil,
            imagePath: record.imagePath,
            charCount: 8,
            isFavorited: true,
            createdAt: record.createdAt,
            updatedAt: Date(),
            deletedAt: nil
        )
        try repository.save(record)

        let fetched = try repository.record(id: record.id)
        XCTAssertEqual(fetched?.ocrText, "更新后的文本")
        XCTAssertEqual(fetched?.translatedText, "Translated")
        XCTAssertTrue(fetched?.isFavorited ?? false)
    }

    func testListReturnsAllRecordsOrderedByCreatedAtDesc() throws {
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        try repository.save(makeRecord(id: "r1", ocrText: "first", createdAt: date1))
        try repository.save(makeRecord(id: "r2", ocrText: "second", createdAt: date2))

        let records = try repository.list(filter: .all, search: nil)

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first?.id, "r2")
    }

    func testSoftDeleteHidesFromList() throws {
        try repository.save(makeRecord(id: "r1", ocrText: "keep"))
        try repository.save(makeRecord(id: "r2", ocrText: "delete"))

        try repository.softDelete(id: "r2", deletedAt: Date())

        let records = try repository.list(filter: .all, search: nil)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, "r1")
    }

    func testToggleFavorite() throws {
        try repository.save(makeRecord(ocrText: "test"))
        let record = try repository.list(filter: .all, search: nil).first!
        XCTAssertFalse(record.isFavorited)

        try repository.toggleFavorite(id: record.id, isFavorited: true, updatedAt: Date())

        let updated = try repository.record(id: record.id)
        XCTAssertTrue(updated?.isFavorited ?? false)
    }

    func testFilterFavoritesReturnsOnlyFavorited() throws {
        try repository.save(makeRecord(id: "r1", ocrText: "not fav"))
        try repository.save(makeRecord(id: "r2", ocrText: "fav"))
        try repository.toggleFavorite(id: "r2", isFavorited: true, updatedAt: Date())

        let favorites = try repository.list(filter: .favorites, search: nil)
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites.first?.id, "r2")
    }

    func testCalendarFiltersUseLocalTodayWeekAndMonthBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        calendar.firstWeekday = 2
        let queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        let fixedNow = ISO8601DateFormatter().date(from: "2026-06-23T02:00:00Z")!
        let repository = SQLiteScreenshotRecordRepository(
            databaseQueue: queue,
            calendar: calendar,
            now: { fixedNow }
        )
        try repository.save(makeRecord(id: "local-today", ocrText: "today", createdAt: ISO8601DateFormatter().date(from: "2026-06-22T17:00:00Z")!))
        try repository.save(makeRecord(id: "previous-week", ocrText: "previous week", createdAt: ISO8601DateFormatter().date(from: "2026-06-21T15:59:59Z")!))
        try repository.save(makeRecord(id: "previous-month", ocrText: "previous month", createdAt: ISO8601DateFormatter().date(from: "2026-05-31T15:59:59Z")!))

        XCTAssertEqual(try repository.list(filter: .today, search: nil).map(\.id), ["local-today"])
        XCTAssertEqual(try repository.list(filter: .thisWeek, search: nil).map(\.id), ["local-today"])
        XCTAssertEqual(try repository.list(filter: .thisMonth, search: nil).map(\.id), ["local-today", "previous-week"])
        XCTAssertEqual(try repository.stats().todayRecords, 1)
    }

    func testSearchMatchesOcrText() throws {
        try repository.save(makeRecord(id: "r1", ocrText: "产品设计需求文档"))
        try repository.save(makeRecord(id: "r2", ocrText: "代码片段"))

        let results = try repository.list(filter: .all, search: "产品")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "r1")
    }

    func testStatsReturnsCorrectCounts() throws {
        let now = Date()
        try repository.save(makeRecord(id: "r1", ocrText: "12345", charCount: 5, createdAt: now))
        try repository.save(makeRecord(id: "r2", ocrText: "67890", charCount: 5, createdAt: now))
        try repository.toggleFavorite(id: "r1", isFavorited: true, updatedAt: now)

        let stats = try repository.stats()

        XCTAssertEqual(stats.totalRecords, 2)
        XCTAssertEqual(stats.todayRecords, 2)
        XCTAssertEqual(stats.totalCharacters, 10)
        XCTAssertEqual(stats.favoritedRecords, 1)
    }

    func testEmptyRepositoryReturnsZeroStats() throws {
        let stats = try repository.stats()

        XCTAssertEqual(stats.totalRecords, 0)
        XCTAssertEqual(stats.todayRecords, 0)
        XCTAssertEqual(stats.totalCharacters, 0)
        XCTAssertEqual(stats.favoritedRecords, 0)
    }

    // MARK: - Helpers

    private func makeRecord(
        id: String = UUID().uuidString,
        ocrText: String,
        charCount: Int? = nil,
        // ISO8601DateFormatter 默认无毫秒精度，截断到整秒避免 SQLite 往返后不等。
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> ScreenshotRecord {
        ScreenshotRecord(
            id: id,
            ocrText: ocrText,
            translatedText: nil,
            summaryText: nil,
            imagePath: "/tmp/test-\(id).png",
            charCount: charCount ?? ocrText.count,
            isFavorited: false,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        )
    }
}
