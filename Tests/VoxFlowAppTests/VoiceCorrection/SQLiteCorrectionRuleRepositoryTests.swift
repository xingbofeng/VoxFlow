import Foundation
import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

final class SQLiteCorrectionRuleRepositoryTests: XCTestCase {
    private var repository: SQLiteCorrectionRuleRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        repository = SQLiteCorrectionRuleRepository(databaseQueue: queue)
    }

    override func tearDown() {
        repository = nil
        super.tearDown()
    }

    func testCreateUpdateDisableAndDeleteRule() throws {
        var rule = makeRule(original: "teh", replacement: "the")
        try repository.save(rule)
        XCTAssertEqual(try repository.rule(id: rule.id), rule)

        rule.replacement = "The"
        rule.updatedAt = rule.updatedAt.addingTimeInterval(60)
        try repository.save(rule)
        XCTAssertEqual(try repository.rule(id: rule.id)?.replacement, "The")

        try repository.setEnabled(false, id: rule.id, updatedAt: rule.updatedAt.addingTimeInterval(60))
        XCTAssertEqual(try repository.rule(id: rule.id)?.isEnabled, false)

        try repository.delete(id: rule.id)
        XCTAssertNil(try repository.rule(id: rule.id))
    }

    func testClearAllRules() throws {
        try repository.save(makeRule(original: "teh", replacement: "the"))
        try repository.save(makeRule(original: "q 问", replacement: "Qwen"))

        try repository.clearAll()

        XCTAssertTrue(try repository.list().isEmpty)
    }

    func testRejectsDuplicateActiveRuleForSameScopeAndOriginal() throws {
        try repository.save(makeRule(original: "teh", replacement: "the"))
        let duplicate = makeRule(original: "TEH", replacement: "The")

        XCTAssertThrowsError(try repository.save(duplicate))
    }

    func testCreatesImmutableSnapshotFromStoredRules() throws {
        let rule = makeRule(original: "teh", replacement: "the")
        try repository.save(rule)

        let provider = CorrectionRuleSnapshotProvider(loader: repository)
        let snapshot = provider.refresh()
        try repository.delete(id: rule.id)

        XCTAssertEqual(snapshot.version, 1)
        XCTAssertEqual(snapshot.rules, [rule])
        XCTAssertTrue(provider.refresh().rules.isEmpty)
        XCTAssertEqual(snapshot.rules, [rule])
    }

    func testSnapshotProviderReturnsPreviousSnapshotWhenStorageFails() {
        let rule = makeRule(original: "teh", replacement: "the")
        let loader = FakeCorrectionRuleLoader(result: .success([rule]))
        let provider = CorrectionRuleSnapshotProvider(loader: loader)
        XCTAssertEqual(provider.refresh().rules, [rule])

        loader.result = .failure(TestError.storageUnavailable)

        XCTAssertEqual(provider.refresh().rules, [rule])
    }

    func testSnapshotProviderReturnsEmptySnapshotOnInitialFailure() {
        let loader = FakeCorrectionRuleLoader(
            result: .failure(TestError.storageUnavailable)
        )

        XCTAssertEqual(CorrectionRuleSnapshotProvider(loader: loader).refresh(), .empty)
    }

    private func makeRule(
        original: String,
        replacement: String
    ) -> CorrectionRule {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return CorrectionRule(
            id: UUID(),
            original: original,
            replacement: replacement,
            matchPolicy: .boundary,
            scope: .application(bundleIdentifier: "com.apple.TextEdit"),
            allowedModes: [.dictation],
            lifecycle: .active,
            source: .manual,
            caseSensitive: false,
            confidence: 0.95,
            observedCount: 2,
            appliedCount: 1,
            revertedCount: 0,
            providerID: "apple",
            modelID: "local",
            language: "en",
            isEnabled: true,
            createdAt: now,
            updatedAt: now,
            lastAppliedAt: now
        )
    }
}

private final class FakeCorrectionRuleLoader: CorrectionRuleLoading {
    var result: Result<[CorrectionRule], Error>

    init(result: Result<[CorrectionRule], Error>) {
        self.result = result
    }

    func list() throws -> [CorrectionRule] {
        try result.get()
    }
}

private enum TestError: Error {
    case storageUnavailable
}
