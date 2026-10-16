import XCTest
import VoxFlowVoiceCorrection
@testable import VoxFlowApp

@MainActor
final class PostEditLearningServiceTests: XCTestCase {
    func testLearnSavesRuleAndUpsertsEvidence() throws {
        let repositories = makeRepositories()
        let service = makeService(repositories: repositories)

        let result = try service.learn(
            pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
            context: context(),
            appliesImmediately: true,
            now: date(100)
        )

        XCTAssertEqual(result.status, .learned)
        let rule = try XCTUnwrap(repositories.ruleRepository.savedRules.first)
        XCTAssertEqual(rule.original, "q 问")
        XCTAssertEqual(rule.replacement, "Qwen")
        XCTAssertEqual(rule.scope, .application(bundleIdentifier: "com.cursor.Cursor"))
        XCTAssertEqual(rule.lifecycle, .active)
        XCTAssertEqual(rule.source, .automaticLearning)
        XCTAssertEqual(rule.confidence, 0.90, accuracy: 0.0001)
        XCTAssertEqual(rule.observedCount, 1)
        XCTAssertEqual(rule.providerID, "apple")
        XCTAssertEqual(rule.language, "en")
        XCTAssertEqual(result.item?.ruleID, rule.id)
        XCTAssertEqual(result.item?.targetID, rule.targetID)
        XCTAssertEqual(repositories.evidence.upsertedCorrections.count, 1)
        XCTAssertEqual(repositories.evidence.upsertedCorrections.first?.original, "q 问")
        XCTAssertEqual(repositories.evidence.upsertedCorrections.first?.corrected, "Qwen")
    }

    func testRepeatedObservationAggregatesObservedCountInsteadOfDuplicatingRule() throws {
        let repositories = makeRepositories()
        let service = makeService(repositories: repositories)

        _ = try service.learn(
            pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
            context: context(),
            appliesImmediately: true,
            now: date(100)
        )
        let result = try service.learn(
            pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
            context: context(),
            appliesImmediately: true,
            now: date(200)
        )

        XCTAssertEqual(result.status, .aggregated)
        XCTAssertEqual(repositories.ruleRepository.savedRules.count, 1)
        let rule = try XCTUnwrap(repositories.ruleRepository.savedRules.first)
        XCTAssertEqual(rule.observedCount, 2)
        XCTAssertEqual(rule.updatedAt, date(200))
        XCTAssertNil(result.item, "Repeated evidence must not offer deletion of a previously learned rule")
        // 证据库仍按语义去重 upsert（occurrence_count 自增）
        XCTAssertEqual(repositories.evidence.upsertedCorrections.count, 2)
    }

    func testSameOriginalDifferentReplacementSupersedesPreviousRule() throws {
        let repositories = makeRepositories()
        let service = makeService(repositories: repositories)

        _ = try service.learn(
            pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
            context: context(),
            appliesImmediately: true,
            now: date(100)
        )
        _ = try service.learn(
            pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen3"),
            context: context(),
            appliesImmediately: true,
            now: date(200)
        )

        let rules = repositories.ruleRepository.savedRules
        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(rules.first?.replacement, "Qwen")
        XCTAssertEqual(rules.first?.lifecycle, .retired, "旧写法规则应被替换退役")
        XCTAssertEqual(rules.first?.observedCount, 1, "旧写法规则 observedCount 不变")
        XCTAssertEqual(rules.last?.replacement, "Qwen3")
        XCTAssertEqual(rules.last?.lifecycle, .active)
        XCTAssertNotEqual(rules.first?.id, rules.last?.id)
    }

    func testRetiredRuleDoesNotHideCurrentRuleDuringRepeatedLearning() throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        let rules = SQLiteCorrectionRuleRepository(databaseQueue: queue)
        let service = PostEditLearningService(
            ruleRepository: rules,
            targetRepository: SQLiteCorrectionTargetRepository(databaseQueue: queue),
            evidenceRepository: nil,
            snapshotProvider: CorrectionRuleSnapshotProvider(loader: rules)
        )

        _ = try service.learn(
            pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
            context: context(), appliesImmediately: true, now: date(100)
        )
        _ = try service.learn(
            pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen3"),
            context: context(), appliesImmediately: true, now: date(200)
        )
        let repeated = try service.learn(
            pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen3"),
            context: context(), appliesImmediately: true, now: date(300)
        )
        XCTAssertEqual(repeated.status, .aggregated)
        XCTAssertEqual(try rules.list().first { $0.lifecycle == .active }?.observedCount, 2)

        let changed = try service.learn(
            pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen4"),
            context: context(), appliesImmediately: true, now: date(400)
        )
        XCTAssertEqual(changed.status, .learned)
        let stored = try rules.list()
        XCTAssertEqual(stored.filter { $0.lifecycle == .active }.map(\.replacement), ["Qwen4"])
        XCTAssertEqual(stored.filter { $0.lifecycle == .retired }.count, 2)
    }

    func testLearningSeparatesProviderContexts() throws {
        try assertLearningPreservesOtherContext(context(providerID: "qwen3"))
    }

    func testLearningSeparatesModelContexts() throws {
        try assertLearningPreservesOtherContext(context(modelID: "large"))
    }

    func testLearningSeparatesLanguageContexts() throws {
        try assertLearningPreservesOtherContext(context(language: "zh-Hans"))
    }

    func testDisabledOrManualActiveRulesArePreservedWithoutLearning() throws {
        for (source, isEnabled) in [(RuleSource.automaticLearning, false), (.manual, true), (.imported, true)] {
            let repositories = makeRepositories()
            let existing = CorrectionRule(
                original: "q 问", replacement: "Qwen",
                scope: .application(bundleIdentifier: "com.cursor.Cursor"),
                source: source, providerID: "apple", language: "en", isEnabled: isEnabled
            )
            repositories.ruleRepository.presetRules = [existing]

            let result = try makeService(repositories: repositories).learn(
                pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen3"),
                context: context(), appliesImmediately: true, now: date(100)
            )

            XCTAssertEqual(result.status, .skippedUnsupportedContext)
            XCTAssertNil(result.item)
            XCTAssertEqual(try repositories.ruleRepository.list(), [existing])
            XCTAssertTrue(repositories.evidence.upsertedCorrections.isEmpty)
        }
    }

    func testInactiveOrOtherContextRulesDoNotBlockLearningAsFeedback() throws {
        for (lifecycle, isEnabled, providerID) in [
            (RuleLifecycle.retired, true, "apple"),
            (.suspended, true, "apple"),
            (.active, false, "apple"),
            (.active, true, "qwen3"),
        ] {
            let repositories = makeRepositories()
            repositories.ruleRepository.presetRules = [CorrectionRule(
                original: "Qwen", replacement: "q 问",
                scope: .application(bundleIdentifier: "com.cursor.Cursor"),
                lifecycle: lifecycle, source: .automaticLearning,
                providerID: providerID, language: "en", isEnabled: isEnabled
            )]

            let result = try makeService(repositories: repositories).learn(
                pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
                context: context(), appliesImmediately: true, now: date(100)
            )

            XCTAssertEqual(result.status, .learned)
        }
    }

    func testReverseEvidenceBlocksLearning() throws {
        let repositories = makeRepositories()
        // 证据库已存在 B→A：学习 A→B 应被拦截
        repositories.evidence.reverseEvidenceResult = true
        let service = makeService(repositories: repositories)

        let result = try service.learn(
            pair: LearnedCorrectionPair(original: "频繁", replacement: "平繁"),
            context: context(),
            appliesImmediately: true,
            now: date(100)
        )

        XCTAssertEqual(result.status, .blockedReverseEvidence)
        XCTAssertNil(result.item)
        XCTAssertTrue(repositories.ruleRepository.savedRules.isEmpty)
        XCTAssertTrue(repositories.evidence.upsertedCorrections.isEmpty)
    }

    func testFeedbackChainAgainstExistingAutomaticRuleBlocksLearning() throws {
        let repositories = makeRepositories()
        // 已有自动学习规则 Qwen→q 问（A→B 的反向规则），学习 q 问→Qwen 应拦截
        let existing = CorrectionRule(
            original: "Qwen",
            replacement: "q 问",
            matchPolicy: .boundary,
            scope: .application(bundleIdentifier: "com.cursor.Cursor"),
            lifecycle: .active,
            source: .automaticLearning
        )
        repositories.ruleRepository.presetRules = [existing]
        let service = makeService(repositories: repositories)

        let result = try service.learn(
            pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
            context: context(),
            appliesImmediately: true,
            now: date(100)
        )

        XCTAssertEqual(result.status, .blockedFeedbackChain)
        XCTAssertEqual(repositories.ruleRepository.savedRules.count, 0)
        XCTAssertTrue(repositories.evidence.upsertedCorrections.isEmpty)
    }

    func testEvidenceSaveFailureDoesNotBlockRuleSave() throws {
        let repositories = makeRepositories()
        repositories.evidence.upsertError = TestEvidenceError()
        let service = makeService(repositories: repositories)

        let result = try service.learn(
            pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
            context: context(),
            appliesImmediately: true,
            now: date(100)
        )

        XCTAssertEqual(result.status, .learned)
        XCTAssertEqual(repositories.ruleRepository.savedRules.count, 1)
    }

    func testUnsupportedContextSkipsLearning() throws {
        let repositories = makeRepositories()
        let service = makeService(repositories: repositories)

        // agentCompose 模式不学习
        let agentComposeResult = try service.learn(
            pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
            context: CorrectionContext(
                mode: .translation,
                providerID: "apple",
                modelID: nil,
                language: "en",
                bundleIdentifier: "com.cursor.Cursor",
                isFinalTranscript: true,
                isSecureField: false
            ),
            appliesImmediately: true,
            now: date(100)
        )
        XCTAssertEqual(agentComposeResult.status, .skippedUnsupportedContext)

        // 非 final 转写不学习
        let partialResult = try service.learn(
            pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
            context: context().with(isFinalTranscript: false),
            appliesImmediately: true,
            now: date(100)
        )
        XCTAssertEqual(partialResult.status, .skippedUnsupportedContext)

        // 安全输入框不学习
        let secureResult = try service.learn(
            pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
            context: context().with(isSecureField: true),
            appliesImmediately: true,
            now: date(100)
        )
        XCTAssertEqual(secureResult.status, .skippedUnsupportedContext)

        XCTAssertTrue(repositories.ruleRepository.savedRules.isEmpty)
        XCTAssertTrue(repositories.evidence.upsertedCorrections.isEmpty)
    }

    func testMissingBundleIdentifierLearnsGlobalScopeRule() throws {
        let repositories = makeRepositories()
        let service = makeService(repositories: repositories)

        // legacy 历史条目没有 bundleID：学习到全局 scope 而非跳过
        let result = try service.learn(
            pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
            context: CorrectionContext(
                mode: .dictation,
                providerID: "apple",
                modelID: nil,
                language: "en",
                bundleIdentifier: nil,
                isFinalTranscript: true,
                isSecureField: false
            ),
            appliesImmediately: true,
            now: date(100)
        )

        XCTAssertEqual(result.status, .learned)
        XCTAssertEqual(repositories.ruleRepository.savedRules.first?.scope, .global)
    }

    // MARK: - Fixtures

    private struct TestEvidenceError: Error {}

    private struct LearningRepositories {
        let ruleRepository: PresettableCorrectionRuleRepository
        let targetRepository: PostEditCapturingTargetRepository
        let evidence: FakePostEditEvidenceRepository
    }

    private func makeRepositories() -> LearningRepositories {
        LearningRepositories(
            ruleRepository: PresettableCorrectionRuleRepository(),
            targetRepository: PostEditCapturingTargetRepository(),
            evidence: FakePostEditEvidenceRepository()
        )
    }

    private func makeService(
        repositories: LearningRepositories,
        onEvent: @escaping (CorrectionObservationLearningEvent) -> Void = { _ in }
    ) -> PostEditLearningService {
        PostEditLearningService(
            ruleRepository: repositories.ruleRepository,
            targetRepository: repositories.targetRepository,
            evidenceRepository: repositories.evidence,
            snapshotProvider: CorrectionRuleSnapshotProvider(loader: SnapshotLoader(repository: repositories.ruleRepository))
        )
    }

    private func assertLearningPreservesOtherContext(
        _ otherContext: CorrectionContext,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repositories = makeRepositories()
        let service = makeService(repositories: repositories)
        let pair = LearnedCorrectionPair(original: "q 问", replacement: "Qwen")
        _ = try service.learn(pair: pair, context: context(), appliesImmediately: true, now: date(100))

        let other = try service.learn(pair: pair, context: otherContext, appliesImmediately: true, now: date(200))
        XCTAssertEqual(other.status, .learned, file: file, line: line)
        XCTAssertEqual(repositories.ruleRepository.savedRules.count, 2, file: file, line: line)

        _ = try service.learn(
            pair: LearnedCorrectionPair(original: pair.original, replacement: "Qwen3"),
            context: otherContext, appliesImmediately: true, now: date(300)
        )
        let originalContextRule = try XCTUnwrap(repositories.ruleRepository.savedRules.first)
        XCTAssertEqual(originalContextRule.replacement, "Qwen", file: file, line: line)
        XCTAssertEqual(originalContextRule.lifecycle, .active, file: file, line: line)
        XCTAssertEqual(originalContextRule.observedCount, 1, file: file, line: line)
        XCTAssertEqual(repositories.ruleRepository.savedRules.filter { $0.lifecycle == .active }.count, 2, file: file, line: line)
    }

    private func context(
        providerID: String = "apple",
        modelID: String? = nil,
        language: String? = "en"
    ) -> CorrectionContext {
        CorrectionContext(
            mode: .dictation,
            providerID: providerID,
            modelID: modelID,
            language: language,
            bundleIdentifier: "com.cursor.Cursor",
            isFinalTranscript: true,
            isSecureField: false
        )
    }

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + offset)
    }
}

private extension CorrectionContext {
    func with(isFinalTranscript: Bool) -> CorrectionContext {
        CorrectionContext(
            mode: mode,
            providerID: providerID,
            modelID: modelID,
            language: language,
            bundleIdentifier: bundleIdentifier,
            isFinalTranscript: isFinalTranscript,
            isSecureField: isSecureField
        )
    }

    func with(isSecureField: Bool) -> CorrectionContext {
        CorrectionContext(
            mode: mode,
            providerID: providerID,
            modelID: modelID,
            language: language,
            bundleIdentifier: bundleIdentifier,
            isFinalTranscript: isFinalTranscript,
            isSecureField: isSecureField
        )
    }
}

private final class PresettableCorrectionRuleRepository: CorrectionRuleRepository {
    var presetRules: [CorrectionRule] = []
    private(set) var savedRules: [CorrectionRule] = []
    private(set) var deletedRuleIDs: [UUID] = []

    func list() throws -> [CorrectionRule] {
        var all = presetRules
        all.append(contentsOf: savedRules)
        return all
    }

    func save(_ rule: CorrectionRule) throws {
        if let index = savedRules.firstIndex(where: { $0.id == rule.id }) {
            savedRules[index] = rule
        } else {
            savedRules.append(rule)
        }
    }

    func rule(id: UUID) throws -> CorrectionRule? {
        savedRules.first { $0.id == id }
    }

    func setEnabled(_ isEnabled: Bool, id: UUID, updatedAt: Date) throws {}

    func delete(id: UUID) throws {
        deletedRuleIDs.append(id)
        savedRules.removeAll { $0.id == id }
    }

    func clearAll() throws {
        savedRules.removeAll()
    }
}

private final class FakePostEditEvidenceRepository: CorrectionEvidenceRepository {
    var upsertedCorrections: [StructuredCorrection] = []
    var reverseEvidenceResult = false
    var upsertError: Error?

    func upsert(_ correction: StructuredCorrection) throws -> CorrectionEvidenceRecord {
        if let upsertError {
            throw upsertError
        }
        upsertedCorrections.append(correction)
        return CorrectionEvidenceRecord(
            original: correction.original,
            corrected: correction.corrected,
            correctionType: correction.type
        )
    }

    func hasReverseEvidence(original: String, corrected: String) throws -> Bool {
        reverseEvidenceResult
    }

    func relevantKnownCorrections(for rawText: String, limit: Int) throws -> [StructuredCorrectionPromptContext.KnownCorrection] {
        []
    }
}

private struct SnapshotLoader: CorrectionRuleLoading {
    let repository: PresettableCorrectionRuleRepository

    func list() throws -> [CorrectionRule] {
        try repository.list()
    }
}

private final class PostEditCapturingTargetRepository: CorrectionTargetRepository {
    private var targets: [CorrectionTargetTerm] = []
    private(set) var savedTargets: [CorrectionTargetTerm] = []

    init(initialTargets: [CorrectionTargetTerm] = []) {
        targets = initialTargets
    }

    func save(_ target: CorrectionTargetTerm) throws {
        savedTargets.append(target)
        if let index = targets.firstIndex(where: { $0.id == target.id }) {
            targets[index] = target
        } else {
            targets.append(target)
        }
    }

    func target(id: UUID) throws -> CorrectionTargetTerm? {
        targets.first { $0.id == id }
    }

    func list() throws -> [CorrectionTargetTerm] {
        targets
    }

    func delete(id: UUID) throws {
        targets.removeAll { $0.id == id }
    }
}
