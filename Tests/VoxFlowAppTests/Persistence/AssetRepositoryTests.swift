import XCTest
@testable import VoxFlowApp

final class AssetRepositoryTests: XCTestCase {
    private var queue: DatabaseQueue!
    private var repository: SQLiteAssetRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        repository = SQLiteAssetRepository(databaseQueue: queue)
    }

    override func tearDown() {
        repository = nil
        queue = nil
        super.tearDown()
    }

    func testMigrationCreatesAssetItemsTable() throws {
        let count = try queue.read { connection -> Int in
            let statement = try connection.prepare(
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'asset_items'"
            )
            _ = try statement.step()
            return statement.columnInt(at: 0)
        }

        XCTAssertEqual(count, 1)
    }

    func testSaveAndFetchAsset() throws {
        let asset = makeAsset(
            id: "dictation-1",
            source: .dictation,
            contentType: .text,
            title: "Qwen3-ASR 接入计划",
            text: "把 Qwen3-ASR 接到 VoxFlow",
            rawText: "把 Qwen3 ASR 接到 VoxFlow",
            sourceAppName: "Cursor"
        )

        try repository.save(asset)

        XCTAssertEqual(try repository.asset(id: "dictation-1"), asset)
    }

    func testPageOrdersByCreatedAtDescendingThenIDAscending() throws {
        try repository.save(makeAsset(id: "old", createdAt: date("2026-06-22T09:00:00Z")))
        try repository.save(makeAsset(id: "b", createdAt: date("2026-06-23T09:00:00Z")))
        try repository.save(makeAsset(id: "a", createdAt: date("2026-06-23T09:00:00Z")))

        let page = try repository.page(query: .init(limit: 10, offset: 0))

        XCTAssertEqual(page.totalCount, 3)
        XCTAssertEqual(page.items.map(\.id), ["a", "b", "old"])
    }

    func testSearchMatchesAssetTextAndMetadata() throws {
        try repository.save(makeAsset(id: "title", title: "Thread 1: EXC_BAD_ACCESS"))
        try repository.save(makeAsset(id: "text", text: "Cannot convert value of type"))
        try repository.save(makeAsset(id: "app", sourceAppName: "Xcode"))
        try repository.save(makeAsset(id: "url", contentType: .link, url: "https://github.com/voxflow/issues/1"))
        try repository.save(makeAsset(id: "file", contentType: .file, filePath: "/Users/counter/report.pdf"))
        try repository.save(makeAsset(id: "color", contentType: .color, colorValue: "#08745f"))
        try repository.save(makeAsset(id: "miss", title: "unrelated"))

        XCTAssertEqual(try repository.page(query: .init(searchText: "access", limit: 10, offset: 0)).items.map(\.id), ["title"])
        XCTAssertEqual(try repository.page(query: .init(searchText: "convert", limit: 10, offset: 0)).items.map(\.id), ["text"])
        XCTAssertEqual(try repository.page(query: .init(searchText: "xcode", limit: 10, offset: 0)).items.map(\.id), ["app"])
        XCTAssertEqual(try repository.page(query: .init(searchText: "github", limit: 10, offset: 0)).items.map(\.id), ["url"])
        XCTAssertEqual(try repository.page(query: .init(searchText: "report", limit: 10, offset: 0)).items.map(\.id), ["file"])
        XCTAssertEqual(try repository.page(query: .init(searchText: "08745f", limit: 10, offset: 0)).items.map(\.id), ["color"])
    }

    func testFiltersBySourceAndContentType() throws {
        try repository.save(makeAsset(id: "voice", source: .dictation, contentType: .text))
        try repository.save(makeAsset(id: "screenshot", source: .screenshot, contentType: .image))
        try repository.save(makeAsset(id: "clip-text", source: .clipboard, contentType: .text))
        try repository.save(makeAsset(id: "clip-file", source: .clipboard, contentType: .file))

        let clipboard = try repository.page(
            query: .init(sources: [.clipboard], limit: 10, offset: 0)
        )
        let text = try repository.page(
            query: .init(contentTypes: [.text], limit: 10, offset: 0)
        )
        let clipboardText = try repository.page(
            query: .init(sources: [.clipboard], contentTypes: [.text], limit: 10, offset: 0)
        )

        XCTAssertEqual(clipboard.items.map(\.id), ["clip-file", "clip-text"])
        XCTAssertEqual(text.items.map(\.id), ["clip-text", "voice"])
        XCTAssertEqual(clipboardText.items.map(\.id), ["clip-text"])
    }

    func testSoftDeleteExcludesAssetFromQueriesButKeepsRow() throws {
        try repository.save(makeAsset(id: "delete-me"))

        try repository.softDelete(id: "delete-me", deletedAt: date("2026-06-23T10:00:00Z"))

        XCTAssertNil(try repository.asset(id: "delete-me"))
        XCTAssertEqual(try repository.page(query: .init(limit: 10, offset: 0)).totalCount, 0)
        let deletedAt = try queue.read { connection -> String? in
            let statement = try connection.prepare("SELECT deleted_at FROM asset_items WHERE id = 'delete-me'")
            _ = try statement.step()
            return statement.columnString(at: 0)
        }
        XCTAssertEqual(deletedAt, "2026-06-23T10:00:00Z")
    }

    func testSoftDeleteBatchAndClearAllAssets() throws {
        try repository.save(makeAsset(id: "a"))
        try repository.save(makeAsset(id: "b"))
        try repository.save(makeAsset(id: "c"))

        try repository.softDelete(ids: ["a", "b"], deletedAt: date("2026-06-23T10:00:00Z"))

        XCTAssertEqual(try repository.page(query: .init(limit: 10, offset: 0)).items.map(\.id), ["c"])
        XCTAssertNil(try repository.asset(id: "a"))
        XCTAssertNil(try repository.asset(id: "b"))

        try repository.clearAll(deletedAt: date("2026-06-23T11:00:00Z"))

        XCTAssertEqual(try repository.page(query: .init(limit: 10, offset: 0)).totalCount, 0)
    }

    private func makeAsset(
        id: String,
        source: AssetSource = .clipboard,
        contentType: AssetContentType = .text,
        title: String = "asset",
        previewText: String? = nil,
        text: String? = "asset text",
        rawText: String? = nil,
        imagePath: String? = nil,
        filePath: String? = nil,
        url: String? = nil,
        colorValue: String? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        contentHash: String? = nil,
        captureReason: AssetCaptureReason = .userCopied,
        metadataJSON: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) -> AssetItem {
        let resolvedCreatedAt = createdAt ?? date("2026-06-23T09:00:00Z")
        return AssetItem(
            id: id,
            source: source,
            contentType: contentType,
            title: title,
            previewText: previewText,
            text: text,
            rawText: rawText,
            imagePath: imagePath,
            filePath: filePath,
            url: url,
            colorValue: colorValue,
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID,
            contentHash: contentHash ?? "hash-\(id)",
            captureReason: captureReason,
            metadataJSON: metadataJSON,
            createdAt: resolvedCreatedAt,
            updatedAt: updatedAt ?? resolvedCreatedAt,
            deletedAt: deletedAt
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
