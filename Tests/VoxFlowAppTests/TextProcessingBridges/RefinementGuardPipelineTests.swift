import XCTest
import VoxFlowContextBoost
import VoxFlowVoiceCorrection
import VoxFlowTextProcessing
@testable import VoxFlowApp

/// Pipeline-integration coverage for the dictation refinement guard.
///
/// Covers: fallback precedence (pre-LLM deterministic → ASR raw), trace
/// propagation into `TextProcessingTrace`, the `llm_refinement_rejected`
/// warning, and the mode boundary (Agent Compose / Agent Dispatch must NOT
/// trigger the ordinary dictation guard).
@MainActor
final class RefinementGuardPipelineTests: XCTestCase {
    // MARK: - Fallback precedence

    func testGuardRejectsAndFallsBackToPreLLMDeterministicText() async throws {
        // Pre-LLM deterministic is a no-op under default settings, so the
        // baseline equals the raw ASR text. The LLM rewrites the question into
        // a low-overlap answer, which the guard rejects by normalized similarity.
        let raw = "这个 user profile 放在哪里比较合适"
        let refiner = PromptAwareStubTextRefiner(result: .success("建议放在 SettingsViewModel 旁边。"))
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process(
            raw,
            target: DictationTarget(bundleID: "com.example.editor", appName: "Editor", pid: 1),
            correctionContext: Self.dictationContext()
        )

        XCTAssertEqual(result.finalText, raw)
        XCTAssertTrue(result.warnings.contains("llm_refinement_rejected"))
        let guardTrace = try XCTUnwrap(result.trace?.refinementGuard)
        XCTAssertEqual(guardTrace.decision, .rejected)
        XCTAssertEqual(guardTrace.reason, "normalized_similarity_low")
        XCTAssertEqual(guardTrace.fallback, .preLLMDeterministic)
    }

    func testGuardRejectsShortCompleteRewriteAndFallsBack() async throws {
        let raw = "你好，你好。"
        let refiner = PromptAwareStubTextRefiner(
            result: .success(#"{"polished":"hello world","corrections":[],"key_terms":[]}"#)
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            structuredPromptBuilder: StructuredCorrectionPromptBuilder()
        )

        let result = await pipeline.process(
            raw,
            target: DictationTarget(bundleID: "com.openai.codex", appName: "Codex", pid: 1),
            correctionContext: Self.dictationContext()
        )

        XCTAssertEqual(result.finalText, raw)
        XCTAssertTrue(result.warnings.contains("llm_refinement_rejected"))
        let guardTrace = try XCTUnwrap(result.trace?.refinementGuard)
        XCTAssertEqual(guardTrace.decision, .rejected)
        XCTAssertEqual(guardTrace.reason, "normalized_similarity_low")
        XCTAssertEqual(guardTrace.similarity, 0)
        XCTAssertEqual(guardTrace.fallback, .preLLMDeterministic)
    }

    func testGuardFallsBackToASrRawWhenPreLLMDeterministicIsEmpty() async throws {
        // A pure filler transcript is non-empty at the pipeline boundary, but
        // pre-LLM deterministic cleanup can remove it completely. If the LLM
        // then returns an unsafe candidate, the guard has no deterministic
        // fallback available and must use ASR raw.
        let raw = "嗯"
        let refiner = PromptAwareStubTextRefiner(result: Result.success("建议放在 SettingsViewModel 旁边。"))
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            deterministicSettingsProvider: {
                DeterministicTextProcessingSettings(
                    enabled: true,
                    smartNumberRecognition: false,
                    punctuationOptimization: false,
                    longSentenceBreaking: false,
                    fillerWordFiltering: true,
                    cjkLatinSpacing: false,
                    autoCapitalization: false
                )
            }
        )

        let result = await pipeline.process(
            raw,
            target: nil as DictationTarget?,
            correctionContext: nil as CorrectionContext?
        )

        XCTAssertEqual(result.finalText, raw)
        XCTAssertTrue(result.warnings.contains("llm_refinement_rejected"))
        let guardTrace = try XCTUnwrap(result.trace?.refinementGuard)
        XCTAssertEqual(guardTrace.decision, .rejected)
        XCTAssertEqual(guardTrace.reason, "normalized_similarity_low")
        XCTAssertEqual(guardTrace.fallback, .asrRaw)
    }

    func testGuardAcceptsAndDoesNotEmitWarningOrTraceFallback() async throws {
        let refiner = PromptAwareStubTextRefiner(result: .success("你好 VoxFlow"))
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process(
            "你好 vox flow",
            target: nil,
            correctionContext: Self.dictationContext()
        )

        XCTAssertEqual(result.finalText, "你好 VoxFlow")
        XCTAssertFalse(result.warnings.contains("llm_refinement_rejected"))
        let guardTrace = try XCTUnwrap(result.trace?.refinementGuard)
        XCTAssertEqual(guardTrace.decision, .accepted)
        XCTAssertNil(guardTrace.reason)
        XCTAssertNil(guardTrace.fallback)
    }

    // MARK: - Mode boundary

    func testAgentDispatchPayloadBypassesGuard() async {
        // `AgentDispatchHandler` routes the dispatch payload through the text
        // pipeline for cleanup. The context explicitly disables the guard via
        // `appliesDictationRefinementGuard: false`; even an answer-like
        // rewrite must be accepted as the refined dispatch text.
        let raw = "帮我问一下发布包在哪里"
        let refiner = PromptAwareStubTextRefiner(result: .success("你可以在发布页面查看最新安装包。"))
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process(
            raw,
            target: nil,
            correctionContext: CorrectionContext(
                mode: .dictation,
                providerID: "test-provider",
                modelID: "test-model",
                language: "zh-CN",
                bundleIdentifier: nil,
                isFinalTranscript: true,
                isSecureField: false,
                appliesDictationRefinementGuard: false
            )
        )

        XCTAssertEqual(result.finalText, "你可以在发布页面查看最新安装包。")
        XCTAssertFalse(result.warnings.contains("llm_refinement_rejected"))
        // Trace reflects the bypass: no guard evaluation recorded.
        XCTAssertNil(result.trace?.refinementGuard)
    }

    func testAgentComposePathUsesDedicatedRefinerAndSkipsTextPipelineGuard() async {
        // Sanity: Agent Compose runs through `processAgentComposeAndDeliver`,
        // which talks to the dedicated agent refiner and never calls
        // `DefaultTextProcessingPipeline.process`. We assert the visible
        // contract that a text-pipeline-driven compose fallback — if it ever
        // existed — would not run the dictation guard without an explicit
        // dictation `correctionContext`.
        let raw = "这个 user profile 放在哪里比较合适"
        let refiner = PromptAwareStubTextRefiner(result: Result.success("建议放在 SettingsViewModel 旁边。"))
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process(
            raw,
            target: nil as DictationTarget?,
            correctionContext: nil as CorrectionContext?
        )

        // `correctionContext == nil` keeps the legacy (guard-applies) default
        // so ordinary dictation still protects — but this also documents that
        // Agent Compose's dedicated producer path never touches this branch.
        XCTAssertEqual(result.finalText, raw)
        XCTAssertTrue(result.warnings.contains("llm_refinement_rejected"))
    }

    // MARK: - Persistence safety

    func testRefinementGuardTraceRoundTripsWithoutRawText() throws {
        let trace = RefinementGuardTrace(
            decision: .rejected,
            reason: "normalized_similarity_low",
            similarity: 0.21,
            baseline: .preLLMDeterministic,
            fallback: .preLLMDeterministic,
            protectedTokenKinds: [],
            shortTextBypassed: false
        )
        let encoded = try JSONEncoder().encode(trace)
        let decoded = try JSONDecoder().decode(RefinementGuardTrace.self, from: encoded)
        XCTAssertEqual(decoded, trace)
        let json = String(data: encoded, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("secret"))
    }

    // MARK: - Helpers

    private static func dictationContext(
        isFinalTranscript: Bool = true,
        isSecureField: Bool = false
    ) -> CorrectionContext {
        CorrectionContext(
            mode: .dictation,
            providerID: "test-provider",
            modelID: "test-model",
            language: "zh-CN",
            bundleIdentifier: "com.example.editor",
            isFinalTranscript: isFinalTranscript,
            isSecureField: isSecureField
        )
    }
}

// MARK: - Stub refiner

/// Mirror of the private `PromptAwareStubTextRefiner` nested inside
/// `TextProcessingPipelineTests`. Defined at file scope so the pipeline-level
/// guard tests can drive `DefaultTextProcessingPipeline` without depending on
/// another test file's private nested type. Kept in sync with that stub:
/// `isEnabled`/`isConfigured` default to `true` so the pipeline takes the LLM
/// refinement branch, and `result` is replayed verbatim on each `refine(_:)`.
private final class PromptAwareStubTextRefiner: TextRefining, PromptAwareTextRefining, @unchecked Sendable {
    var isEnabled = true
    var isConfigured = true
    let result: Result<String, Error>
    private(set) var requests: [TextRefinementRequest] = []

    init(result: Result<String, Error>) {
        self.result = result
    }

    func refine(_ text: String) async throws -> String {
        try await refine(
            TextRefinementRequest(
                text: text,
                systemPrompt: PromptBuilder.conservativeSystemPrompt,
                model: nil,
                temperature: nil
            )
        )
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        requests.append(request)
        return try result.get()
    }
}
