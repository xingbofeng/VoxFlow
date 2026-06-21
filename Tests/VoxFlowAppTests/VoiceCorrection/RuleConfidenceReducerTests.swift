import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

final class RuleConfidenceReducerTests: XCTestCase {
    func testUserRevertLowersConfidence() {
        let rule = makeRule(confidence: 0.90, revertedCount: 0)

        let reduced = RuleConfidenceReducer().recordRevert(rule, at: Date())

        XCTAssertEqual(reduced.confidence, 0.55, accuracy: 0.0001)
        XCTAssertEqual(reduced.revertedCount, 1)
        XCTAssertEqual(reduced.lifecycle, .active)
    }

    func testSecondUserRevertSuspendsRule() {
        let rule = makeRule(confidence: 0.55, revertedCount: 1)

        let reduced = RuleConfidenceReducer().recordRevert(rule, at: Date())

        XCTAssertEqual(reduced.revertedCount, 2)
        XCTAssertEqual(reduced.lifecycle, .suspended)
    }

    private func makeRule(confidence: Double, revertedCount: Int) -> CorrectionRule {
        CorrectionRule(
            original: "q 问",
            replacement: "Qwen",
            matchPolicy: .boundary,
            scope: .application(bundleIdentifier: "com.cursor.Cursor"),
            lifecycle: .active,
            source: .automaticLearning,
            confidence: confidence,
            revertedCount: revertedCount
        )
    }
}
