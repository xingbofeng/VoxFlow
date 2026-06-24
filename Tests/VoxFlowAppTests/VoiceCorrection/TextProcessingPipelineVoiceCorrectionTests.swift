import VoxFlowContextBoost
import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

@MainActor
final class TextProcessingPipelineVoiceCorrectionTests: XCTestCase {
    func testRunsCorrectionAfterSuccessfulLLMRefinement() async {
        let event = CorrectionEvent(
            ruleID: UUID(),
            original: "queue win",
            replacement: "Qwen",
            range: CorrectionTextRange(location: 0, length: 9),
            scope: .global,
            source: .manual
        )
        let refiner = PipelineStubRefiner(result: .success("queue win"))
        let processor = CapturingVoiceCorrectionProcessor(
            result: .success(makeResult(raw: "queue win", corrected: "Qwen", events: [event]))
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            voiceCorrectionProcessor: processor
        )

        let result = await pipeline.process(
            "raw speech",
            target: nil,
            correctionContext: makeContext()
        )

        XCTAssertEqual(processor.inputs, ["queue win"])
        XCTAssertEqual(result.finalText, "Qwen")
        XCTAssertEqual(result.trace?.voiceCorrection?.candidateEvents, [event])
        XCTAssertEqual(result.trace?.voiceCorrection?.appliedEvents, [event])
    }

    func testRunsCorrectionAfterLLMFailure() async {
        let refiner = PipelineStubRefiner(result: .failure(TestError.expected))
        let processor = CapturingVoiceCorrectionProcessor(
            result: .success(makeResult(raw: "q 问", corrected: "Qwen"))
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            voiceCorrectionProcessor: processor
        )

        let result = await pipeline.process(
            "q 问",
            target: nil,
            correctionContext: makeContext()
        )

        XCTAssertEqual(processor.inputs, ["q 问"])
        XCTAssertEqual(result.finalText, "Qwen")
        XCTAssertTrue(result.warnings.contains("llm_refinement_failed"))
    }

    func testCommandAndTranslationBypassCorrectionProcessor() async {
        for mode in [CorrectionInputMode.command, .translation] {
            let processor = CapturingVoiceCorrectionProcessor(
                result: .success(makeResult(raw: "teh", corrected: "the"))
            )
            let pipeline = DefaultTextProcessingPipeline(
                refiner: PipelineStubRefiner(isEnabled: false, result: .success("unused")),
                voiceCorrectionProcessor: processor
            )

            let result = await pipeline.process(
                "teh",
                target: nil,
                correctionContext: makeContext(mode: mode)
            )

            XCTAssertEqual(result.finalText, "teh")
            XCTAssertTrue(processor.inputs.isEmpty)
        }
    }

    func testCorrectionFailureKeepsCurrentTextAndRecordsWarning() async {
        let processor = CapturingVoiceCorrectionProcessor(
            result: .failure(TestError.expected)
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: PipelineStubRefiner(result: .success("refined text")),
            voiceCorrectionProcessor: processor
        )

        let result = await pipeline.process(
            "raw text",
            target: nil,
            correctionContext: makeContext()
        )

        XCTAssertEqual(result.finalText, "refined text")
        XCTAssertTrue(result.warnings.contains("voice_correction_failed"))
    }

    func testShadowLikeCorrectionEventsAreNotTreatedAsAppliedEvents() async {
        let event = CorrectionEvent(
            ruleID: UUID(),
            original: "foo",
            replacement: "Foo",
            range: CorrectionTextRange(location: 0, length: 3),
            scope: .global,
            source: .manual
        )
        let processor = CapturingVoiceCorrectionProcessor(
            result: .success(CorrectionResult(
                rawText: "foo",
                correctedText: "foo",
                events: [event]
            ))
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: PipelineStubRefiner(isEnabled: false, result: .success("unused")),
            voiceCorrectionProcessor: processor
        )

        let result = await pipeline.process(
            "foo",
            target: nil,
            correctionContext: makeContext()
        )

        XCTAssertEqual(result.correctionEvents, [event])
        XCTAssertEqual(result.appliedCorrectionEvents, [])
        XCTAssertEqual(result.trace?.voiceCorrection?.candidateEvents, [event])
        XCTAssertEqual(result.trace?.voiceCorrection?.appliedEvents, [])
    }

    func testCorrectionTraceIsRecordedWhenLLMIsDisabledAndNoRuleMatches() async {
        let processor = CapturingVoiceCorrectionProcessor(
            result: .success(CorrectionResult(rawText: "Q问。", correctedText: "Q问。"))
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: PipelineStubRefiner(isEnabled: false, result: .success("unused")),
            voiceCorrectionProcessor: processor
        )

        let result = await pipeline.process(
            "Q问。",
            target: nil,
            correctionContext: makeContext()
        )

        XCTAssertEqual(result.finalText, "Q问。")
        XCTAssertNotNil(result.trace)
        XCTAssertEqual(result.trace?.voiceCorrection?.candidateEvents, [])
        XCTAssertEqual(result.trace?.voiceCorrection?.appliedEvents, [])
        XCTAssertNil(result.trace?.llm)
    }

    func testOCRContextBoostOnlyAffectsLLMPromptBeforeVoiceCorrection() async {
        let refiner = PipelinePromptAwareRefiner(result: .success("去问"))
        let processor = CapturingVoiceCorrectionProcessor(
            result: .success(CorrectionResult(rawText: "去问", correctedText: "去问"))
        )
        let contextProvider = PipelineOCRContextProvider(
            snapshot: OCRContextSnapshot(
                bundleID: "com.example.editor",
                appName: "Editor",
                windowTitle: "README",
                capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
                hotwords: [
                    TemporaryHotword(
                        text: "Qwen",
                        normalizedText: "qwen",
                        score: 5,
                        source: .ocrShape,
                        evidence: [HotwordEvidence(reason: "test", weight: 5)],
                        expiresAt: Date(timeIntervalSince1970: 1_800_000_120)
                    ),
                ]
            )
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            voiceCorrectionProcessor: processor,
            contextBoostProvider: contextProvider,
            contextBoostEnabled: { true }
        )

        let result = await pipeline.process(
            "去问",
            target: DictationTarget(bundleID: "com.example.editor", appName: "Editor", pid: 42),
            correctionContext: makeContext()
        )

        XCTAssertTrue(refiner.requests.first?.systemPrompt.contains(#""temporary_terms":["Qwen"]"#) == true)
        XCTAssertEqual(contextProvider.requestedTargets.map { $0?.bundleID }, ["com.example.editor"])
        XCTAssertEqual(processor.inputs, ["去问"])
        XCTAssertEqual(result.trace?.contextBoost?.hotwords, ["Qwen"])
        XCTAssertEqual(result.trace?.voiceCorrection?.candidateEvents, [])
    }

    private func makeContext(
        mode: CorrectionInputMode = .dictation
    ) -> CorrectionContext {
        CorrectionContext(
            mode: mode,
            providerID: "test",
            modelID: nil,
            language: "en",
            bundleIdentifier: "com.apple.TextEdit",
            isFinalTranscript: true,
            isSecureField: false
        )
    }

    private func makeResult(
        raw: String,
        corrected: String,
        events: [CorrectionEvent] = []
    ) -> CorrectionResult {
        CorrectionResult(rawText: raw, correctedText: corrected, events: events)
    }
}

private final class PipelineStubRefiner: TextRefining, @unchecked Sendable {
    let isEnabled: Bool
    let isConfigured = true
    let result: Result<String, Error>

    init(isEnabled: Bool = true, result: Result<String, Error>) {
        self.isEnabled = isEnabled
        self.result = result
    }

    func refine(_ text: String) async throws -> String {
        try result.get()
    }
}

private final class PipelinePromptAwareRefiner: TextRefining, PromptAwareTextRefining, @unchecked Sendable {
    let isEnabled = true
    let isConfigured = true
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

private final class PipelineOCRContextProvider: CurrentWindowOCRContextProviding, @unchecked Sendable {
    let snapshot: OCRContextSnapshot?
    private(set) var requestedTargets: [DictationTarget?] = []

    init(snapshot: OCRContextSnapshot?) {
        self.snapshot = snapshot
    }

    func captureContext(for target: DictationTarget?) async -> OCRContextSnapshot? {
        requestedTargets.append(target)
        return snapshot
    }
}

private final class CapturingVoiceCorrectionProcessor: VoiceCorrectionTextProcessing {
    let result: Result<CorrectionResult, Error>
    private(set) var inputs: [String] = []

    init(result: Result<CorrectionResult, Error>) {
        self.result = result
    }

    func process(_ text: String, context: CorrectionContext) throws -> CorrectionResult {
        inputs.append(text)
        return try result.get()
    }
}

private enum TestError: Error {
    case expected
}
