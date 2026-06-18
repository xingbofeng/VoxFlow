import Foundation
import XCTest
@testable import VoxFlowApp

final class SQLiteHistoryRepositoryTests: XCTestCase {
    private var repository: SQLiteHistoryRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        repository = SQLiteHistoryRepository(databaseQueue: queue)
    }

    override func tearDown() {
        repository = nil
        super.tearDown()
    }

    func testSaveAndFetchHistoryEntry() throws {
        let entry = makeEntry(
            finalText: "我在用 VoiceInput 写需求",
            processingTraceJSON: #"{"llm":{"model":"gpt"}}"#
        )

        try repository.save(entry)

        XCTAssertEqual(try repository.entry(id: entry.id), entry)
    }

    func testListRecentExcludesSoftDeletedEntries() throws {
        let oldEntry = makeEntry(id: "old", finalText: "旧输入", createdAt: Date(timeIntervalSince1970: 100))
        let newEntry = makeEntry(id: "new", finalText: "新输入", createdAt: Date(timeIntervalSince1970: 200))
        try repository.save(oldEntry)
        try repository.save(newEntry)
        try repository.softDelete(id: "new", deletedAt: Date(timeIntervalSince1970: 300))

        let entries = try repository.listRecent(limit: 10)

        XCTAssertEqual(entries.map(\.id), ["old"])
    }

    func testSearchMatchesRawOrFinalText() throws {
        try repository.save(makeEntry(id: "raw", rawText: "配森", finalText: "Python"))
        try repository.save(makeEntry(id: "final", rawText: "杰森", finalText: "JSON"))
        try repository.save(makeEntry(id: "other", rawText: "天气", finalText: "天气"))

        let entries = try repository.search("JSON", limit: 10)

        XCTAssertEqual(entries.map(\.id), ["final"])
    }

    private func makeEntry(
        id: String = UUID().uuidString,
        rawText: String = "raw text",
        finalText: String,
        createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
        processingTraceJSON: String? = nil
    ) -> DictationHistoryEntry {
        DictationHistoryEntry(
            id: id,
            rawText: rawText,
            finalText: finalText,
            language: "zh-CN",
            asrProviderID: "apple",
            llmProviderID: nil,
            styleID: nil,
            durationMS: 1_200,
            charCount: finalText.count,
            cpm: 180,
            targetAppBundleID: "com.example.editor",
            targetAppName: "Editor",
            processingWarningsJSON: nil,
            processingTraceJSON: processingTraceJSON,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        )
    }
}
