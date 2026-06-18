import XCTest
@testable import VoxFlowApp

final class SQLiteGlossaryRepositoryTests: XCTestCase {
    private var glossary: SQLiteGlossaryRepository!
    private var replacements: SQLiteReplacementRuleRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        glossary = SQLiteGlossaryRepository(databaseQueue: queue)
        replacements = SQLiteReplacementRuleRepository(databaseQueue: queue)
    }

    override func tearDown() {
        glossary = nil
        replacements = nil
        super.tearDown()
    }

    func testGlossarySaveListAndSearch() throws {
        try glossary.save(
            GlossaryTerm(
                id: "python",
                term: "Python",
                aliases: ["配森"],
                category: "coding",
                enabled: true,
                priority: 10,
                notes: "Programming language",
                createdAt: testDate,
                updatedAt: testDate
            )
        )

        XCTAssertEqual(try glossary.list(category: "coding").map(\.term), ["Python"])
        XCTAssertEqual(try glossary.search("配森").map(\.id), ["python"])
    }

    func testGlossaryDeleteRemovesTerm() throws {
        try glossary.save(
            GlossaryTerm(
                id: "json",
                term: "JSON",
                aliases: ["杰森"],
                category: "coding",
                enabled: true,
                priority: 20,
                notes: nil,
                createdAt: testDate,
                updatedAt: testDate
            )
        )

        try glossary.delete(id: "json")

        XCTAssertTrue(try glossary.list(category: nil).isEmpty)
    }

    func testReplacementRuleSaveListAndDelete() throws {
        let rule = ReplacementRule(
            id: "typescript",
            source: "Type Script",
            target: "TypeScript",
            matchMode: .contains,
            applyStage: .beforeLLM,
            category: "coding",
            enabled: true,
            priority: 5,
            createdAt: testDate,
            updatedAt: testDate
        )

        try replacements.save(rule)
        XCTAssertEqual(try replacements.listEnabled(stage: .beforeLLM).map(\.id), ["typescript"])

        try replacements.delete(id: "typescript")
        XCTAssertTrue(try replacements.listEnabled(stage: .beforeLLM).isEmpty)
    }

    private var testDate: Date {
        Date(timeIntervalSince1970: 1_800_000_000)
    }
}
