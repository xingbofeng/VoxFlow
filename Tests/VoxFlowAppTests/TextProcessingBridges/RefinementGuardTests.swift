import XCTest
@testable import VoxFlowApp

/// Unit tests for the conservative refinement guard model. These target
/// behavior (decision + trace) for each rejection/acceptance rule and the
/// spec scenarios, without wiring through the text pipeline. Pipeline-level
/// fallback and mode-boundary coverage live in `TextProcessingPipelineTests`.
@MainActor
final class RefinementGuardTests: XCTestCase {
    private func evaluate(
        asrRaw: String = "",
        preLLMDeterministic: String,
        refined: String,
        temporaryHotwords: [String] = [],
        settings: RefinementGuardSettings = .defaults
    ) -> ConservativeRefinementGuard.Outcome {
        ConservativeRefinementGuard(settings: settings).evaluate(
            asrRaw: asrRaw,
            preLLMDeterministic: preLLMDeterministic,
            refined: refined,
            temporaryHotwords: temporaryHotwords
        )
    }

    // MARK: - Rejections

    func testRejectsEmptyOutputWithTraceReason() {
        let outcome = evaluate(
            preLLMDeterministic: "帮我 review 一下这个 PR",
            refined: "   "
        )
        XCTAssertEqual(outcome.decision, .reject("empty_output"))
        XCTAssertEqual(outcome.trace.decision, .rejected)
        XCTAssertEqual(outcome.trace.reason, "empty_output")
        XCTAssertNil(outcome.trace.similarity)
        XCTAssertEqual(outcome.trace.fallback, .preLLMDeterministic)
        XCTAssertFalse(outcome.trace.shortTextBypassed)
    }

    func testRejectsExplanationWrapperBySimilarity() {
        let outcome = evaluate(
            preLLMDeterministic: "帮我看一下这个页面",
            refined: "以下是修改后的文本：已经帮你核对完了。"
        )
        XCTAssertEqual(outcome.decision, .reject("normalized_similarity_low"))
        XCTAssertEqual(outcome.trace.reason, "normalized_similarity_low")
    }

    func testRejectsAnswerLikeRewriteBySimilarity() {
        let outcome = evaluate(
            preLLMDeterministic: "这个 user profile 放在哪里比较合适",
            refined: "建议放在 SettingsViewModel 旁边。"
        )
        XCTAssertEqual(outcome.decision, .reject("normalized_similarity_low"))
        XCTAssertEqual(outcome.trace.reason, "normalized_similarity_low")
    }

    func testRejectsLowNormalizedSimilarityPerSpecScenario() {
        let outcome = evaluate(
            preLLMDeterministic: "帮我问一下发布包在哪里",
            refined: "你可以在发布页面查看最新安装包。"
        )
        XCTAssertEqual(outcome.decision, .reject("normalized_similarity_low"))
        XCTAssertEqual(outcome.trace.reason, "normalized_similarity_low")
        XCTAssertNotNil(outcome.trace.similarity)
        XCTAssertLessThan(outcome.trace.similarity ?? 1, 0.6)
    }

    // MARK: - Acceptances

    func testAcceptsConservativeCorrectionPerSpecScenario() {
        let outcome = evaluate(
            asrRaw: "你好 vox flow",
            preLLMDeterministic: "你好 vox flow",
            refined: "你好 VoxFlow"
        )
        XCTAssertEqual(outcome.decision, .accept)
        XCTAssertEqual(outcome.trace.decision, .accepted)
        XCTAssertNil(outcome.trace.reason)
        XCTAssertNil(outcome.trace.fallback)
    }

    func testAcceptsPunctuationOnlyChangeWithoutSimilarityReject() {
        let outcome = evaluate(
            preLLMDeterministic: "等会儿我发你链接",
            refined: "等会儿我发你链接。"
        )
        XCTAssertEqual(outcome.decision, .accept)
        XCTAssertFalse(outcome.trace.shortTextBypassed)
        XCTAssertEqual(outcome.trace.similarity, 1)
    }

    func testAcceptsCaseAndWhitespaceAndEmojiVariation() {
        let outcome = evaluate(
            preLLMDeterministic: "你好 vox flow",
            refined: "你好 VoxFlow ✨"
        )
        XCTAssertEqual(outcome.decision, .accept)
    }

    func testAcceptsSuggestionTextWhenBaselineAlreadyContainsIt() {
        let outcome = evaluate(
            preLLMDeterministic: "建议放在 SettingsViewModel 旁边",
            refined: "建议放在 SettingsViewModel 旁边。"
        )
        XCTAssertEqual(outcome.decision, .accept)
    }

    func testRejectsShortBaselineWhenRefinedHasNoContentOverlap() {
        let outcome = evaluate(
            preLLMDeterministic: "你好，你好。",
            refined: "hello world"
        )
        XCTAssertEqual(outcome.decision, .reject("normalized_similarity_low"))
        XCTAssertEqual(outcome.trace.reason, "normalized_similarity_low")
        XCTAssertFalse(outcome.trace.shortTextBypassed)
        XCTAssertEqual(outcome.trace.similarity, 0)
    }

    func testRejectsShortPrefixExpansionWithStricterShortTextFloor() {
        let outcome = evaluate(
            preLLMDeterministic: "你好啊。",
            refined: "你好啊，建议放在 SettingsViewModel 旁边。"
        )

        XCTAssertEqual(outcome.decision, .reject("normalized_similarity_low"))
        XCTAssertEqual(outcome.trace.reason, "normalized_similarity_low")
        XCTAssertGreaterThanOrEqual(outcome.trace.similarity ?? 0, RefinementGuardSettings.defaults.similarityFloor)
        XCTAssertLessThan(outcome.trace.similarity ?? 1, RefinementGuardSettings.defaults.shortTextSimilarityFloor)
    }

    func testAcceptsShortTextEmojiOnlyVariation() {
        let outcome = evaluate(
            preLLMDeterministic: "你好啊。",
            refined: "你好啊 😊"
        )

        XCTAssertEqual(outcome.decision, .accept)
        XCTAssertEqual(outcome.trace.similarity, 1)
    }

    // MARK: - Fallback source

    func testFallbackDefaultsToDeterministicWhenBaselineNonEmpty() {
        let outcome = evaluate(
            preLLMDeterministic: "帮我问一下版本号 1.13.0",
            refined: ""
        )
        XCTAssertEqual(outcome.trace.fallback, .preLLMDeterministic)
    }

    func testFallbackFallsBackToASrRawWhenBaselineEmpty() {
        let outcome = evaluate(
            asrRaw: "呃帮我问一下版本号一十三点零",
            preLLMDeterministic: "",
            refined: ""
        )
        XCTAssertEqual(outcome.decision, .reject("empty_output"))
        XCTAssertEqual(outcome.trace.fallback, .asrRaw)
    }

    // MARK: - Trace safety

    func testTraceDoesNotCarryRawOrRefinedText() {
        let outcome = evaluate(
            preLLMDeterministic: "secret baseline text",
            refined: "secret refined text"
        )
        // Trace only carries decision/reason/similarity/baseline/fallback and
        // legacy coarse token kinds — never the source strings.
        let trace = outcome.trace
        XCTAssertFalse(trace.reason?.contains("secret") ?? false)
        XCTAssertEqual(trace.baseline, .preLLMDeterministic)
        XCTAssertTrue(trace.protectedTokenKinds.isEmpty)
    }
}
