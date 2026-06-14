import Foundation

@MainActor
protocol AgentComposeHandling: AnyObject {
    var onStageChange: ((AgentComposeHUDStage) -> Void)? { get set }
    var onStreamingDelta: ((String) -> Void)? { get set }
    var lastFailedTaskID: String? { get }
    func start(target: DictationTarget?) throws
    func finish(rawTranscript: String) async throws -> OutputResult
    func cancel()
    func fail(_ error: Error)
}

@MainActor
final class DefaultAgentComposeHandler: AgentComposeHandling {
    private let coordinator: VoiceTaskCoordinator
    private let styleSelector: any StyleSelecting
    private var target: DictationTarget?

    var onStageChange: ((AgentComposeHUDStage) -> Void)?
    var onStreamingDelta: ((String) -> Void)?
    private(set) var lastFailedTaskID: String?

    init(
        coordinator: VoiceTaskCoordinator,
        styleSelector: any StyleSelecting
    ) {
        self.coordinator = coordinator
        self.styleSelector = styleSelector
    }

    func start(target: DictationTarget?) throws {
        self.target = target
        lastFailedTaskID = nil
        try coordinator.startTask(mode: .agentCompose, target: target)
        coordinator.startContextCollection(target: target, visionSupported: true)
        onStageChange?(.readingWindow)
    }

    func finish(rawTranscript: String) async throws -> OutputResult {
        onStageChange?(.transcribing)
        try coordinator.recordRawTranscript(rawTranscript)

        let context = await coordinator.awaitContextCollection()

        onStageChange?(.generating)
        coordinator.onStreamingDelta = onStreamingDelta
        let stylePrompt = try await styleSelector.style(for: target)?.prompt

        let result = try await coordinator.processAgentComposeAndDeliver(
            context: context,
            stylePrompt: stylePrompt
        )

        // Check for context warnings and notify HUD
        if let context, !context.warnings.isEmpty {
            let hasOnlyVisionWarning = context.warnings.allSatisfy {
                $0 == "vision_not_supported" || $0 == "visual_fallback_timeout"
            }
            if hasOnlyVisionWarning && context.visibleText == nil && context.selectedText == nil {
                // Only vision warnings and no text context — still proceed normally
                // HUD already showed "generating" which is accurate
            }
        }

        switch result {
        case .injected:
            onStageChange?(.inserted)
        case .copied, .targetChanged, .injectionFailed, .copyFailed:
            onStageChange?(.copied)
        case .cancelled:
            break
        }
        return result
    }

    func cancel() {
        coordinator.cancelContextCollection()
        try? coordinator.cancelCurrentTask()
        target = nil
    }

    func fail(_ error: Error) {
        coordinator.cancelContextCollection()
        lastFailedTaskID = coordinator.currentTaskID
        try? coordinator.recordFailure(
            stage: "agentCompose",
            code: "agent_compose_failed",
            message: error.localizedDescription,
            recoverable: true
        )
        target = nil
    }
}
