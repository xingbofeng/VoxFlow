import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

final class LearningPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testManualRulesAreImmediatelyActive() {
        let rule = LearningPolicy().manualRule(
            original: "teh",
            replacement: "the",
            scope: .global,
            createdAt: now
        )

        XCTAssertEqual(rule.lifecycle, .active)
        XCTAssertEqual(rule.source, .manual)
        XCTAssertEqual(rule.confidence, 1)
    }

    func testAutomaticLearningDirectApplyCreatesActiveRuleWithHighConfidence() {
        let rule = LearningPolicy().learnedRule(
            pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
            context: context(),
            appliesImmediately: true,
            createdAt: now
        )

        XCTAssertEqual(rule?.lifecycle, .active)
        XCTAssertEqual(rule?.source, .automaticLearning)
        XCTAssertEqual(rule?.confidence, 0.90)
        XCTAssertEqual(rule?.scope, .application(bundleIdentifier: "com.cursor.Cursor"))
    }

    func testAutomaticLearningCandidateWhenDirectApplyIsOff() {
        let rule = LearningPolicy().learnedRule(
            pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
            context: context(),
            appliesImmediately: false,
            createdAt: now
        )

        XCTAssertEqual(rule?.lifecycle, .candidate)
        XCTAssertEqual(rule?.confidence, 0.40)
    }

    func testRejectedPairsAreSuppressedForThirtyDays() {
        var suppression = LearningSuppressionList()
        suppression.suppress(
            LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
            bundleIdentifier: "com.cursor.Cursor",
            now: now
        )

        XCTAssertTrue(suppression.contains(
            LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
            bundleIdentifier: "com.cursor.Cursor",
            now: now.addingTimeInterval(29 * 24 * 60 * 60)
        ))
        XCTAssertFalse(suppression.contains(
            LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
            bundleIdentifier: "com.cursor.Cursor",
            now: now.addingTimeInterval(31 * 24 * 60 * 60)
        ))
    }

    func testUndoRecentAutomaticLearningDeletesRule() {
        let rule = LearningPolicy().learnedRule(
            pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
            context: context(),
            appliesImmediately: true,
            createdAt: now
        )!

        XCTAssertEqual(LearningPolicy().undoRecentAutomaticLearning(rule), .delete(rule.id))
    }

    func testFeedbackChainPairsAreRejected() {
        let existing = LearningPolicy().learnedRule(
            pair: LearnedCorrectionPair(original: "q 问", replacement: "Qwen"),
            context: context(),
            appliesImmediately: true,
            createdAt: now
        )!

        XCTAssertTrue(LearningPolicy().wouldCreateFeedbackChain(
            LearnedCorrectionPair(original: "Qwen", replacement: "Queue win"),
            existingRules: [existing]
        ))
    }

    private func context() -> CorrectionContext {
        CorrectionContext(
            mode: .dictation,
            providerID: "apple",
            modelID: nil,
            language: "en",
            bundleIdentifier: "com.cursor.Cursor",
            isFinalTranscript: true,
            isSecureField: false
        )
    }
}
