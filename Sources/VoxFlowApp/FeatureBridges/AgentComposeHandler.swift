import Foundation

@MainActor
protocol AgentComposeHandling: AnyObject {
    var onStageChange: ((AgentComposeHUDStage) -> Void)? { get set }
    var onStreamingDelta: ((String) -> Void)? { get set }
    var onRuntimeCompleted: ((String) -> Void)? { get set }
    var lastFailedTaskID: String? { get }
    func start(target: DictationTarget?) throws
    func start(target: DictationTarget?, asrMetadata: VoiceTaskASRMetadata?) throws
    func updateASRMetadata(_ metadata: VoiceTaskASRMetadata) throws
    func finish(rawTranscript: String) async throws -> OutputResult
    func cancel()
    func fail(_ error: Error)
}

@MainActor
final class DefaultAgentComposeHandler: AgentComposeHandling {
    private let coordinator: VoiceTaskCoordinator
    private let styleSelector: any StyleSelecting
    private var target: DictationTarget?
    private var activeTaskID: String?

    var onStageChange: ((AgentComposeHUDStage) -> Void)?
    var onStreamingDelta: ((String) -> Void)?
    var onRuntimeCompleted: ((String) -> Void)?
    private(set) var lastFailedTaskID: String?

    init(
        coordinator: VoiceTaskCoordinator,
        styleSelector: any StyleSelecting
    ) {
        self.coordinator = coordinator
        self.styleSelector = styleSelector
    }

    func start(target: DictationTarget?) throws {
        try start(target: target, asrMetadata: nil)
    }

    func start(target: DictationTarget?, asrMetadata: VoiceTaskASRMetadata?) throws {
        self.target = target
        lastFailedTaskID = nil
        AppLogger.dictation.debug("AgentComposeHandler start target=\(target?.bundleID ?? "nil")")
        let task = try coordinator.startTask(
            mode: .agentCompose,
            target: target,
            asrMetadata: asrMetadata
        )
        AppLogger.dictation.info("AgentComposeHandler task started id=\(task.id)")
        activeTaskID = task.id
        coordinator.startContextCollection(target: target, visionSupported: true)
    }

    func updateASRMetadata(_ metadata: VoiceTaskASRMetadata) throws {
        let providerID = metadata.providerID ?? "nil"
        AppLogger.dictation.debug("AgentComposeHandler updateASRMetadata provider=\(providerID)")
        try coordinator.updateASRMetadata(metadata, kind: .agentCompose)
    }

    func finish(rawTranscript: String) async throws -> OutputResult {
        guard let taskID = activeTaskID else {
            AppLogger.dictation.warning("AgentComposeHandler finish rejected: no active task")
            throw CoordinatorError.noActiveTask
        }
        AppLogger.dictation.debug("AgentComposeHandler finish task=\(taskID) transcriptLen=\(rawTranscript.count)")
        emitStage(.transcribing, taskID: taskID)
        try coordinator.recordRawTranscript(rawTranscript, kind: .agentCompose)

        let context = await coordinator.awaitContextCollection()

        emitStage(.generating, taskID: taskID)
        let taskCoordinator = coordinator
        taskCoordinator.onStreamingDelta = { [weak self, weak taskCoordinator] taskID, delta in
            guard let self,
                  let taskCoordinator,
                  self.activeTaskID == taskID,
                  taskCoordinator.activeTaskID(for: .agentCompose) == taskID else {
                return
            }
            self.onStreamingDelta?(delta)
        }
        defer {
            if activeTaskID == taskID || taskCoordinator.activeTaskID(for: .agentCompose) == nil {
                taskCoordinator.onStreamingDelta = nil
            }
        }
        let stylePrompt = try await styleSelector.style(for: target)?.prompt

        let result = try await coordinator.processAgentComposeAndDeliver(
            context: context,
            stylePrompt: stylePrompt,
            onAgentRuntimeStage: { [weak self] stage in
                self?.emitStage(stage, taskID: taskID, requireActiveWorkflow: false)
            },
            onAgentRuntimeCompleted: { [weak self] completedTaskID in
                guard self?.activeTaskID == completedTaskID else { return }
                self?.onRuntimeCompleted?(completedTaskID)
            }
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
            emitStage(.inserted, taskID: taskID, requireActiveWorkflow: false)
        case .copied, .targetChanged, .permissionDenied, .injectionFailed:
            emitStage(.copied, taskID: taskID, requireActiveWorkflow: false)
        case .copyFailed:
            AppLogger.dictation.warning("AgentComposeHandler finish copyFailed")
            break
        case .cancelled:
            AppLogger.dictation.debug("AgentComposeHandler finish cancelled")
            break
        }
        activeTaskID = nil
        target = nil
        AppLogger.dictation.debug("AgentComposeHandler finish cleared task")
        return result
    }

    func cancel() {
        AppLogger.dictation.debug("AgentComposeHandler cancel task=\(activeTaskID ?? "nil")")
        coordinator.cancelContextCollection()
        try? coordinator.cancelTask(kind: .agentCompose)
        activeTaskID = nil
        target = nil
    }

    func fail(_ error: Error) {
        AppLogger.dictation.warning("AgentComposeHandler fail \(error.localizedDescription)")
        coordinator.cancelContextCollection()
        lastFailedTaskID = coordinator.activeTaskID(for: .agentCompose)
        try? coordinator.recordFailure(
            stage: "agentCompose",
            code: "agent_compose_failed",
            message: error.localizedDescription,
            recoverable: true,
            kind: .agentCompose
        )
        activeTaskID = nil
        target = nil
    }

    private func emitStage(
        _ stage: AgentComposeHUDStage,
        taskID: String,
        requireActiveWorkflow: Bool = true
    ) {
        guard activeTaskID == taskID else {
            return
        }
        if requireActiveWorkflow,
           coordinator.activeTaskID(for: .agentCompose) != taskID {
            return
        }
        AppLogger.dictation.debug("AgentComposeHandler emitStage \(stage)")
        onStageChange?(stage)
    }
}
