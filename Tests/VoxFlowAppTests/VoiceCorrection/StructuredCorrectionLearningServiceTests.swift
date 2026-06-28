import Foundation
import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

final class StructuredCorrectionLearningServiceTests: XCTestCase {
    private var queue: DatabaseQueue!
    private var repository: SQLiteCorrectionTargetRepository!
    private var evidenceRepository: SQLiteCorrectionEvidenceRepository!
    private var counter: InMemoryKeyTermCounter!
    private var service: StructuredCorrectionLearningService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        repository = SQLiteCorrectionTargetRepository(databaseQueue: queue)
        evidenceRepository = SQLiteCorrectionEvidenceRepository(databaseQueue: queue)
        counter = InMemoryKeyTermCounter()
        service = StructuredCorrectionLearningService(
            repository: repository,
            termCounter: counter,
            evidenceRepository: evidenceRepository
        )
    }

    func testReasonableHotWordAccepted() {
        XCTAssertTrue(StructuredCorrectionLearningService.isReasonableHotWord("PostgreSQL"))
        XCTAssertTrue(StructuredCorrectionLearningService.isReasonableHotWord("VoxFlow"))
    }

    func testEmptyTermRejected() {
        XCTAssertFalse(StructuredCorrectionLearningService.isReasonableHotWord(""))
    }

    func testSingleCJKRejected() {
        XCTAssertFalse(StructuredCorrectionLearningService.isReasonableHotWord("好"))
    }

    func testFillerWordsRejected() {
        XCTAssertFalse(StructuredCorrectionLearningService.isReasonableHotWord("嗯"))
        XCTAssertFalse(StructuredCorrectionLearningService.isReasonableHotWord("那个"))
    }

    func testFullSentenceRejected() {
        XCTAssertFalse(StructuredCorrectionLearningService.isReasonableHotWord("这是一个句子。"))
    }

    func testValidCorrectionAccepted() {
        XCTAssertTrue(StructuredCorrectionLearningService.isValidCorrection(original: "陈瑞", corrected: "陈睿"))
    }

    func testSameValueCorrectionRejected() {
        XCTAssertFalse(StructuredCorrectionLearningService.isValidCorrection(original: "X", corrected: "X"))
    }

    func testRatioTooLargeRejected() {
        XCTAssertFalse(StructuredCorrectionLearningService.isValidCorrection(original: "A", corrected: "ABCDEFGH"))
    }

    func testLearnsHomophoneCorrection() {
        let output = StructuredCorrectionOutput(
            polished: "t",
            corrections: [StructuredCorrection(original: "a", corrected: "b", type: .homophone)],
            keyTerms: []
        )
        let outcome = service.learn(from: output)
        XCTAssertEqual(outcome.correctionResults.first?.action, .learned)
    }

    func testLearnedCorrectionIsStoredAsKnownCorrectionEvidence() throws {
        let output = StructuredCorrectionOutput(
            polished: "扣子空间",
            corrections: [StructuredCorrection(original: "口子空间", corrected: "扣子空间", type: .term)],
            keyTerms: []
        )

        let outcome = service.learn(from: output)

        XCTAssertEqual(outcome.correctionResults.first?.action, .learned)
        let known = try evidenceRepository.relevantKnownCorrections(for: "打开口子空间", limit: 5)
        XCTAssertEqual(
            known,
            [
                StructuredCorrectionPromptContext.KnownCorrection(
                    original: "口子空间",
                    corrected: "扣子空间"
                )
            ]
        )
    }

    func testLearnedCorrectionIncrementsEvidenceCount() throws {
        let output = StructuredCorrectionOutput(
            polished: "扣子空间",
            corrections: [StructuredCorrection(original: "口子空间", corrected: "扣子空间", type: .term)],
            keyTerms: []
        )

        _ = service.learn(from: output)
        _ = service.learn(from: output)

        let known = try evidenceRepository.relevantKnownCorrections(for: "口子空间", limit: 5)
        XCTAssertEqual(known.count, 1)
    }

    func testBlocklistedHotwordDoesNotAppearAsKnownCorrectionTarget() throws {
        try evidenceRepository.upsert(
            StructuredCorrection(original: "QQ", corrected: "Qwen", type: .homophone)
        )
        let target = CorrectionTargetTerm(text: "Qwen", lifecycle: .active, source: .automaticLearning)
        try repository.save(target)
        try repository.blocklist(id: target.id)

        let known = try evidenceRepository.relevantKnownCorrections(for: "QQ。", limit: 5)

        XCTAssertEqual(known, [])
    }

    func testSkipsStyleCorrection() {
        let output = StructuredCorrectionOutput(
            polished: "t",
            corrections: [StructuredCorrection(original: "逗号", corrected: "，", type: .style)],
            keyTerms: []
        )
        let outcome = service.learn(from: output)
        XCTAssertEqual(outcome.correctionResults.first?.action, .skippedStyle)
    }

    func testKeyTermFirstOccurrenceOnlyCounts() {
        let output = StructuredCorrectionOutput(polished: "t", corrections: [], keyTerms: ["PostgreSQL"])
        let outcome = service.learn(from: output)
        XCTAssertEqual(outcome.keyTermResults.first?.action, .counting)
        XCTAssertEqual(outcome.keyTermResults.first?.count, 1)
    }

    func testKeyTermSecondOccurrenceEntersDrawer() {
        _ = service.learn(from: StructuredCorrectionOutput(polished: "t", corrections: [], keyTerms: ["PostgreSQL"]))
        let outcome = service.learn(from: StructuredCorrectionOutput(polished: "t", corrections: [], keyTerms: ["PostgreSQL"]))
        XCTAssertEqual(outcome.keyTermResults.first?.action, .enteredDrawer)
        XCTAssertEqual(outcome.drawerCandidates, ["PostgreSQL"])
    }

    func testKeyTermThirdOccurrencePromotesToHotword() {
        _ = service.learn(from: StructuredCorrectionOutput(polished: "t", corrections: [], keyTerms: ["PostgreSQL"]))
        _ = service.learn(from: StructuredCorrectionOutput(polished: "t", corrections: [], keyTerms: ["PostgreSQL"]))
        let outcome = service.learn(from: StructuredCorrectionOutput(polished: "t", corrections: [], keyTerms: ["PostgreSQL"]))
        XCTAssertEqual(outcome.keyTermResults.first?.action, .promotedToHotword)
        XCTAssertEqual(outcome.promotedHotwords, ["PostgreSQL"])
    }

    func testRepositoryBackedCounterPersistsKeyTermCountAcrossServiceRestart() throws {
        let firstService = StructuredCorrectionLearningService(
            repository: repository,
            termCounter: RepositoryBackedKeyTermCounter(repository: repository),
            evidenceRepository: evidenceRepository
        )
        _ = firstService.learn(from: StructuredCorrectionOutput(polished: "t", corrections: [], keyTerms: ["PostgreSQL"]))
        let secondOutcome = firstService.learn(
            from: StructuredCorrectionOutput(polished: "t", corrections: [], keyTerms: ["PostgreSQL"])
        )
        XCTAssertEqual(secondOutcome.keyTermResults.first?.action, .enteredDrawer)
        XCTAssertEqual(try repository.listLearningCandidates(limit: 10).map(\.text), ["PostgreSQL"])

        let restartedService = StructuredCorrectionLearningService(
            repository: repository,
            termCounter: RepositoryBackedKeyTermCounter(repository: repository),
            evidenceRepository: evidenceRepository
        )
        let thirdOutcome = restartedService.learn(
            from: StructuredCorrectionOutput(polished: "t", corrections: [], keyTerms: ["PostgreSQL"])
        )

        XCTAssertEqual(thirdOutcome.keyTermResults.first?.action, .promotedToHotword)
        XCTAssertEqual(try repository.listHotwords().map(\.text), ["PostgreSQL"])
        XCTAssertEqual(try repository.list().first?.observedCount, 3)
    }

    func testBlocklistPreventsPromotion() throws {
        let target = CorrectionTargetTerm(text: "PostgreSQL", lifecycle: .active, source: .manual)
        try repository.save(target)
        try repository.blocklist(id: target.id)

        _ = counter.increment("PostgreSQL")
        _ = counter.increment("PostgreSQL")

        let outcome = service.learn(from: StructuredCorrectionOutput(polished: "t", corrections: [], keyTerms: ["PostgreSQL"]))
        XCTAssertEqual(outcome.keyTermResults.first?.action, .blockedByBlocklist)
        XCTAssertEqual(outcome.promotedHotwords, [])
    }

    func testReverseChainDetected() {
        let existing = [(original: "A", corrected: "B")]
        XCTAssertTrue(StructuredCorrectionLearningService.isReverseChain(original: "B", corrected: "A", existing: existing))
        XCTAssertFalse(StructuredCorrectionLearningService.isReverseChain(original: "A", corrected: "C", existing: existing))
    }

    func testReverseChainStoredInEvidenceIsFiltered() {
        _ = service.learn(from: StructuredCorrectionOutput(
            polished: "B",
            corrections: [StructuredCorrection(original: "A", corrected: "B", type: .term)],
            keyTerms: []
        ))

        let outcome = service.learn(from: StructuredCorrectionOutput(
            polished: "A",
            corrections: [StructuredCorrection(original: "B", corrected: "A", type: .term)],
            keyTerms: []
        ))

        XCTAssertEqual(outcome.correctionResults.first?.action, .filtered)
    }

    func testFilteredKeyTermNotCounted() {
        let outcome = service.learn(from: StructuredCorrectionOutput(polished: "t", corrections: [], keyTerms: ["嗯"]))
        XCTAssertEqual(outcome.keyTermResults.first?.action, .filtered)
    }
}
