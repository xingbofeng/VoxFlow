import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

@MainActor
final class TextProcessingPipelineVoiceCorrectionTests: XCTestCase {
    func testRunsCorrectionAfterSuccessfulLLMRefinement() async {
        let refiner = PipelineStubRefiner(result: .success("queue win"))
        let processor = CapturingVoiceCorrectionProcessor(
            result: .success(makeResult(raw: "queue win", corrected: "Qwen"))
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

    private func makeResult(raw: String, corrected: String) -> CorrectionResult {
        CorrectionResult(rawText: raw, correctedText: corrected)
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
