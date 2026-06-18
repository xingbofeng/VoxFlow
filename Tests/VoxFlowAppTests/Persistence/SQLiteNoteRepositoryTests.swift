import XCTest
@testable import VoxFlowApp

final class SQLiteNoteRepositoryTests: XCTestCase {
    private var repository: SQLiteNoteRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        repository = SQLiteNoteRepository(databaseQueue: queue)
    }

    override func tearDown() {
        repository = nil
        super.tearDown()
    }

    func testSaveAndFetchNote() throws {
        let note = makeNote(title: "需求笔记", body: "用 VoiceInput 记录需求")

        try repository.save(note)

        XCTAssertEqual(try repository.note(id: note.id), note)
    }

    func testSearchMatchesTitleBodyOrTag() throws {
        try repository.save(makeNote(id: "one", title: "会议", body: "无关内容", tags: ["work"]))
        try repository.save(makeNote(id: "two", title: "草稿", body: "包含 Markdown", tags: ["draft"]))

        XCTAssertEqual(try repository.search("Markdown").map(\.id), ["two"])
        XCTAssertEqual(try repository.search("work").map(\.id), ["one"])
    }

    func testSoftDeleteHidesNoteFromListAndSearch() throws {
        try repository.save(makeNote(id: "deleted", title: "删除", body: "应该隐藏"))

        try repository.softDelete(id: "deleted", deletedAt: testDate)

        XCTAssertTrue(try repository.list().isEmpty)
        XCTAssertTrue(try repository.search("删除").isEmpty)
    }

    private func makeNote(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        tags: [String] = ["default"]
    ) -> NoteRecord {
        NoteRecord(
            id: id,
            title: title,
            bodyMarkdown: body,
            sourceType: "manual",
            sourceID: nil,
            tags: tags,
            createdAt: testDate,
            updatedAt: testDate,
            deletedAt: nil
        )
    }

    private var testDate: Date {
        Date(timeIntervalSince1970: 1_800_000_000)
    }
}
