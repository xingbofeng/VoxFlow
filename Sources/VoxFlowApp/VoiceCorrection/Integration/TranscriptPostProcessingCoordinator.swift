import VoxFlowVoiceCorrection

struct TranscriptPostProcessingCoordinator: VoiceCorrectionTextProcessing {
    private let processor: VoiceCorrectionTextProcessor

    init(processor: VoiceCorrectionTextProcessor) {
        self.processor = processor
    }

    func process(
        _ text: String,
        context: CorrectionContext
    ) throws -> CorrectionResult {
        processor.process(text, context: context)
    }
}
