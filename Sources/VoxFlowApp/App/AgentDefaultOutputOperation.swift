import Foundation

@MainActor
struct AgentDefaultOutputOperation {
    struct Result {
        let finalText: String
        let activatedOriginalTarget: Bool
        let currentTarget: DictationTarget?
        let outputResult: OutputResult
        let processingTrace: TextProcessingTrace?
    }

    let process: (String, DictationTarget?) async -> TextProcessingResult
    let activate: (DictationTarget?) async -> Bool
    let currentTarget: () -> DictationTarget?
    let deliver: (String, DictationTarget?, DictationTarget?) async -> OutputResult
    let isCancelled: () -> Bool

    func run(utterance: String, originalTarget: DictationTarget?) async -> Result? {
        let processingResult = await process(utterance, originalTarget)
        guard !isCancelled() else { return nil }

        let trimmedFinalText = processingResult.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalText = trimmedFinalText.isEmpty ? utterance : trimmedFinalText
        let activatedOriginalTarget = await activate(originalTarget)
        guard !isCancelled() else { return nil }

        let target = currentTarget()
        let outputResult = await deliver(finalText, target, originalTarget)
        guard !isCancelled() else { return nil }

        return Result(
            finalText: finalText,
            activatedOriginalTarget: activatedOriginalTarget,
            currentTarget: target,
            outputResult: outputResult,
            processingTrace: processingResult.trace
        )
    }
}

enum AgentDefaultOutputHUDCompletion: Equatable {
    case hidden
    case failure(message: String, retainedText: String)

    init(outputResult: OutputResult, finalText: String) {
        switch outputResult.kind {
        case .permissionDenied, .failed:
            self = .failure(message: L10n.localize("app.output.input_failed", comment: "Workflow output failure hint"), retainedText: finalText)
        case .inserted, .copied, .targetChanged, .handledExternally, .cancelled:
            self = .hidden
        }
    }
}
