import Foundation
import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

final class SQLiteCorrectionTargetRepositoryTests: XCTestCase {
    private var queue: DatabaseQueue!
    private var repository: SQLiteCorrectionTargetRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        repository = SQLiteCorrectionTargetRepository(databaseQueue: queue)
    }

    override func tearDown() {
        repository = nil
        queue = nil
        super.tearDown()
    }

    func testCreateUpdateAndDeleteTarget() throws {
        var target = makeTarget(text: "Qwen")
        try repository.save(target)

        XCTAssertEqual(try repository.target(id: target.id), target)

        target.text = "Qwen3-ASR"
        target.normalizedText = CorrectionTargetTerm.normalize(target.text)
        target.appliedCount = 3
        target.updatedAt = target.updatedAt.addingTimeInterval(60)
        try repository.save(target)

        XCTAssertEqual(try repository.target(id: target.id)?.text, "Qwen3-ASR")
        XCTAssertEqual(try repository.target(id: target.id)?.appliedCount, 3)

        try repository.delete(id: target.id)

        XCTAssertNil(try repository.target(id: target.id))
    }

    func testListsTargetsByRecentActivityThenText() throws {
        let older = makeTarget(text: "VoxFlow", updatedAt: Date(timeIntervalSince1970: 100))
        let newer = makeTarget(text: "Qwen", updatedAt: Date(timeIntervalSince1970: 200))
        try repository.save(older)
        try repository.save(newer)

        XCTAssertEqual(try repository.list().map(\.text), ["Qwen", "VoxFlow"])
    }

    func testRuleRepositoryPersistsTargetIdentifier() throws {
        let target = makeTarget(text: "Qwen")
        try repository.save(target)
        let ruleRepository = SQLiteCorrectionRuleRepository(databaseQueue: queue)
        let rule = CorrectionRule(
            targetID: target.id,
            original: "q 问",
            replacement: "Qwen"
        )

        try ruleRepository.save(rule)

        XCTAssertEqual(try ruleRepository.rule(id: rule.id)?.targetID, target.id)
    }

    func testMigrationBackfillsTargetsForLegacyRules() throws {
        let legacyQueue = try DatabaseQueue(connection: .inMemory())
        try DatabaseMigrator(migrations: [
            DatabaseMigration(id: 1, name: "initial_schema") { connection in
                try connection.execute(AppDatabase.initialSchemaSQL)
            },
            DatabaseMigration(id: 7, name: "voice_correction") { connection in
                try connection.execute(AppDatabase.voiceCorrectionSQL)
            },
            DatabaseMigration(id: 8, name: "voice_correction_scope_specific_unique_index") { connection in
                try connection.execute(AppDatabase.voiceCorrectionUniqueIndexSQL)
            },
        ]).migrate(legacyQueue)

        let ruleID = UUID()
        let timestamp = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_800_000_000))
        try legacyQueue.write { connection in
            let statement = try connection.prepare(
                """
                INSERT INTO voice_correction_rules (
                    id, original, replacement, match_policy, scope_type, scope_value,
                    allowed_modes_json, lifecycle, source, case_sensitive, confidence,
                    observed_count, applied_count, reverted_count, provider_id, model_id,
                    language, enabled, created_at, updated_at, last_applied_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            )
            try statement.bind(ruleID.uuidString, at: 1)
            try statement.bind("q 问", at: 2)
            try statement.bind("Qwen", at: 3)
            try statement.bind(MatchPolicy.boundary.rawValue, at: 4)
            try statement.bind("application", at: 5)
            try statement.bind("com.cursor.Cursor", at: 6)
            try statement.bind("[\"dictation\"]", at: 7)
            try statement.bind(RuleLifecycle.active.rawValue, at: 8)
            try statement.bind(RuleSource.manual.rawValue, at: 9)
            try statement.bind(0, at: 10)
            try statement.bind(1.0, at: 11)
            try statement.bind(1, at: 12)
            try statement.bind(2, at: 13)
            try statement.bind(0, at: 14)
            try statement.bind(nil as String?, at: 15)
            try statement.bind(nil as String?, at: 16)
            try statement.bind("zh-Hans", at: 17)
            try statement.bind(1, at: 18)
            try statement.bind(timestamp, at: 19)
            try statement.bind(timestamp, at: 20)
            try statement.bind(timestamp, at: 21)
            _ = try statement.step()
        }

        try AppDatabase.migrator().migrate(legacyQueue)

        let targetRepository = SQLiteCorrectionTargetRepository(databaseQueue: legacyQueue)
        let ruleRepository = SQLiteCorrectionRuleRepository(databaseQueue: legacyQueue)
        let targets = try targetRepository.list()
        let migratedRule = try XCTUnwrap(try ruleRepository.rule(id: ruleID))

        XCTAssertEqual(targets.map(\.text), ["Qwen"])
        XCTAssertEqual(targets.first?.scope, .application(bundleIdentifier: "com.cursor.Cursor"))
        XCTAssertEqual(migratedRule.targetID, targets.first?.id)

        try AppDatabase.migrator().migrate(legacyQueue)

        let targetsAfterSecondMigration = try targetRepository.list()
        let ruleAfterSecondMigration = try XCTUnwrap(try ruleRepository.rule(id: ruleID))
        XCTAssertEqual(targetsAfterSecondMigration.count, 1)
        XCTAssertEqual(ruleAfterSecondMigration.targetID, migratedRule.targetID)
    }

    private func makeTarget(
        text: String,
        updatedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> CorrectionTargetTerm {
        CorrectionTargetTerm(
            id: UUID(),
            text: text,
            scope: .global,
            lifecycle: .active,
            source: .manual,
            observedCount: 1,
            appliedCount: 2,
            revertedCount: 0,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            lastAppliedAt: updatedAt
        )
    }
}
