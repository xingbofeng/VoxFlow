import VoxFlowVoiceCorrection

struct TranscriptPostProcessingCoordinator: VoiceCorrectionTextProcessing {
    private static let logger = AppLogger.general

    private let processor: VoiceCorrectionTextProcessor

    init(processor: VoiceCorrectionTextProcessor) {
        Self.logger.debug("TranscriptPostProcessingCoordinator init")
        self.processor = processor
    }

    func process(
        _ text: String,
        context: CorrectionContext
    ) throws -> CorrectionResult {
        Self.logger.debug("TranscriptPostProcessingCoordinator process inputLength=\(text.count) contextMode=\(context.mode)")
        let result = processor.process(text, context: context)
        Self.logger.debug("TranscriptPostProcessingCoordinator process done eventCount=\(result.events.count)")
        return result
    }
}
