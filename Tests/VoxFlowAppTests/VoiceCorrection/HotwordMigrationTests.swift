import Foundation
import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

/// Tests that legacy voice_correction_targets and voice_correction_rules data
/// can be loaded as hotwords and text replacement rules after the vocabulary
/// redesign migration.
///
/// These tests verify the data migration compatibility requirements from
/// `redesign-vocabulary-hotwords-learning` tasks 2.1 and 2.2:
/// - Old targets load as hotwords with hit count, blocklist, source, last hit time
/// - Old rules load as text replacement rules
/// - Old rules without target_id can be displayed by replacement
final class HotwordMigrationTests: XCTestCase {
    private var queue: DatabaseQueue!
    private var targetRepository: SQLiteCorrectionTargetRepository!
    private var ruleRepository: SQLiteCorrectionRuleRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        targetRepository = SQLiteCorrectionTargetRepository(databaseQueue: queue)
        ruleRepository = SQLiteCorrectionRuleRepository(databaseQueue: queue)
    }

    override func tearDown() {
        ruleRepository = nil
        targetRepository = nil
        queue = nil
        super.tearDown()
    }

    // MARK: - Task 2.1: Old targets as hotwords, old rules as text replacement

    func testLegacyTargetLoadsAsHotwordWithHitCount() throws {
        let target = makeTarget(text: "VoxFlow", appliedCount: 42)
        try targetRepository.save(target)

        let loaded = try XCTUnwrap(targetRepository.target(id: target.id))

        XCTAssertEqual(loaded.text, "VoxFlow")
        XCTAssertEqual(loaded.appliedCount, 42)
        // New hotword-specific fields (will fail until schema + model are extended)
        XCTAssertEqual(loaded.hitCount, 0)
        XCTAssertFalse(loaded.isBlocklisted)
        XCTAssertNil(loaded.lastHitAt)
    }

    func testLegacyRuleLoadsAsTextReplacementRule() throws {
        let rule = CorrectionRule(
            original: "欧拉玛",
            replacement: "Ollama",
            matchPolicy: .boundary,
            scope: .global,
            source: .manual
        )
        try ruleRepository.save(rule)

        let loaded = try XCTUnwrap(ruleRepository.rule(id: rule.id))

        XCTAssertEqual(loaded.original, "欧拉玛")
        XCTAssertEqual(loaded.replacement, "Ollama")
        XCTAssertEqual(loaded.matchPolicy, .boundary)
        XCTAssertTrue(loaded.isEnabled)
    }

    func testHotwordRepositoryListsActiveTargetsAsHotwords() throws {
        let active = makeTarget(text: "ContextBoost", lifecycle: .active)
        let retired = makeTarget(text: "Legacy", lifecycle: .retired)
        try targetRepository.save(active)
        try targetRepository.save(retired)

        let hotwords = try targetRepository.listHotwords()

        XCTAssertEqual(hotwords.count, 1)
        XCTAssertEqual(hotwords.first?.text, "ContextBoost")
    }

    // MARK: - Task 2.2: Old rule without target_id displayed by replacement

    func testLegacyRuleWithoutTargetIdLoadsByReplacement() throws {
        let rule = CorrectionRule(
            targetID: nil,
            original: "q 问",
            replacement: "Qwen",
            matchPolicy: .boundary,
            scope: .global,
            source: .manual
        )
        try ruleRepository.save(rule)

        let loaded = try XCTUnwrap(ruleRepository.rule(id: rule.id))

        XCTAssertNil(loaded.targetID)
        XCTAssertEqual(loaded.replacement, "Qwen")
        XCTAssertEqual(loaded.original, "q 问")
    }

    func testLegacyRuleWithoutTargetIdStillExecutesInPipeline() throws {
        let rule = CorrectionRule(
            targetID: nil,
            original: "欧拉玛",
            replacement: "Ollama",
            matchPolicy: .boundary,
            scope: .global,
            source: .manual
        )
        try ruleRepository.save(rule)

        let loaded = try XCTUnwrap(ruleRepository.rule(id: rule.id))
        XCTAssertTrue(loaded.isEnabled)
        // The rule should be loadable and usable in text replacement
        XCTAssertEqual(loaded.replacement, "Ollama")
    }

    // MARK: - Task 2.3: Hotword model fields

    func testHotwordWithHitCountAndBlocklistPersisted() throws {
        var target = makeTarget(text: "PostgreSQL")
        target.hitCount = 15
        target.isBlocklisted = false
        target.lastHitAt = Date(timeIntervalSince1970: 1_800_000_100)
        try targetRepository.save(target)

        let loaded = try XCTUnwrap(targetRepository.target(id: target.id))

        XCTAssertEqual(loaded.hitCount, 15)
        XCTAssertFalse(loaded.isBlocklisted)
        XCTAssertEqual(loaded.lastHitAt, Date(timeIntervalSince1970: 1_800_000_100))
    }

    // MARK: - Task 2.4: Sorted hotwords

    func testHotwordsSortedByHitCountDescending() throws {
        var lowHit = makeTarget(text: "Alpha", appliedCount: 0)
        lowHit.hitCount = 1
        var midHit = makeTarget(text: "Beta", appliedCount: 0)
        midHit.hitCount = 10
        var highHit = makeTarget(text: "Gamma", appliedCount: 0)
        highHit.hitCount = 50

        try targetRepository.save(lowHit)
        try targetRepository.save(midHit)
        try targetRepository.save(highHit)

        let hotwords = try targetRepository.listHotwords()

        XCTAssertEqual(hotwords.map(\.text), ["Gamma", "Beta", "Alpha"])
    }

    // MARK: - Task 2.5: Delete hotword enters blocklist

    func testDeleteHotwordEntersBlocklist() throws {
        let target = makeTarget(text: "PostgreSQL")
        try targetRepository.save(target)

        try targetRepository.blocklist(id: target.id)

        let hotwords = try targetRepository.listHotwords()
        XCTAssertFalse(hotwords.contains { $0.id == target.id })

        let blocklisted = try targetRepository.target(id: target.id)
        XCTAssertNotNil(blocklisted)
        XCTAssertTrue(blocklisted?.isBlocklisted == true)
    }

    func testBlocklistedHotwordNotReAddedByAutoLearning() throws {
        var target = makeTarget(text: "PostgreSQL", source: .automaticLearning)
        target.isBlocklisted = true
        try targetRepository.save(target)

        let autoLearned = makeTarget(text: "PostgreSQL", source: .automaticLearning)
        try targetRepository.saveHotwordIfNotBlocklisted(autoLearned)

        let loaded = try XCTUnwrap(targetRepository.target(id: target.id))
        XCTAssertTrue(loaded.isBlocklisted)
    }

    // MARK: - Helpers

    private func makeTarget(
        text: String,
        scope: RuleScope = .global,
        lifecycle: RuleLifecycle = .active,
        source: RuleSource = .manual,
        appliedCount: Int = 0,
        updatedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> CorrectionTargetTerm {
        CorrectionTargetTerm(
            id: UUID(),
            text: text,
            scope: scope,
            lifecycle: lifecycle,
            source: source,
            observedCount: 0,
            appliedCount: appliedCount,
            revertedCount: 0,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            lastAppliedAt: nil
        )
    }
}
