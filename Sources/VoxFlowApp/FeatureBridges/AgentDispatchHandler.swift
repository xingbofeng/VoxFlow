import Foundation
import VoxFlowVoiceCorrection

@MainActor
protocol AgentDispatchHandling: AnyObject {
    var onPresentationChange: ((AgentDispatchHUDPresentation) -> Void)? { get set }
    func start(target: DictationTarget?, asrMetadata: VoiceTaskASRMetadata?) throws
    func updateASRMetadata(_ metadata: VoiceTaskASRMetadata) throws
    func finish(rawTranscript: String) async throws -> AgentDispatchHUDPresentation
    func beginDefaultOutput()
    func completeFallbackInput(
        finalText: String,
        outputResult: OutputResult,
        appliedCorrectionEvents: [CorrectionEvent]
    ) throws
    func confirm(agentID: String, utterance: String, message: String, alias: String?) async
    func cancel()
    func fail(_ error: Error)
}

@MainActor
final class DefaultAgentDispatchHandler: AgentDispatchHandling {
    private let taskCoordinator: VoiceTaskCoordinator
    private let dispatchCoordinator: AgentDispatchCoordinator
    private let clipboardService: any ClipboardSetting
    private let confirmationTimeoutNanoseconds: UInt64
    private var activeTaskID: String?
    private var confirmationTimeoutTask: Task<Void, Never>?

    private(set) var activeTarget: DictationTarget?
    var onPresentationChange: ((AgentDispatchHUDPresentation) -> Void)?

    init(
        taskCoordinator: VoiceTaskCoordinator,
        dispatchCoordinator: AgentDispatchCoordinator,
        clipboardService: any ClipboardSetting,
        confirmationTimeoutNanoseconds: UInt64 = 10_000_000_000
    ) {
        self.taskCoordinator = taskCoordinator
        self.dispatchCoordinator = dispatchCoordinator
        self.clipboardService = clipboardService
        self.confirmationTimeoutNanoseconds = confirmationTimeoutNanoseconds
    }

    func start(target: DictationTarget?, asrMetadata: VoiceTaskASRMetadata?) throws {
        AppLogger.dictation.debug("AgentDispatchHandler start target=\(target?.bundleID ?? "nil") provider=\(asrMetadata?.providerID ?? "nil")")
        cancelConfirmationTimeout()
        if activeTaskID != nil {
            AppLogger.dictation.warning("AgentDispatchHandler replacing existing task: \(activeTaskID ?? "nil")")
            try taskCoordinator.cancelTask(kind: .agentDispatch)
            activeTaskID = nil
            activeTarget = nil
        }
        let task = try taskCoordinator.startTask(
            mode: .agentDispatch,
            target: target,
            asrMetadata: asrMetadata
        )
        activeTaskID = task.id
        activeTarget = target
        AppLogger.dictation.info("AgentDispatchHandler task started id=\(task.id)")
        dispatchCoordinator.onPresentationChange = { [weak self] presentation in
            guard !presentation.isFallbackInput else { return }
            self?.onPresentationChange?(presentation)
        }
        Task { [weak self] in
            guard let self else { return }
            await self.dispatchCoordinator.startListening()
            self.emitCurrentPresentation()
        }
    }

    func updateASRMetadata(_ metadata: VoiceTaskASRMetadata) throws {
        let providerID = metadata.providerID ?? "nil"
        AppLogger.dictation.debug("AgentDispatchHandler updateASRMetadata provider=\(providerID)")
        try taskCoordinator.updateASRMetadata(metadata, kind: .agentDispatch)
    }

    func finish(rawTranscript: String) async throws -> AgentDispatchHUDPresentation {
        guard let workflowTaskID = activeTaskID else {
            AppLogger.dictation.warning("AgentDispatchHandler finish rejected: no active task")
            throw CoordinatorError.noActiveTask
        }
        AppLogger.dictation.debug("AgentDispatchHandler finish task=\(workflowTaskID) transcriptLen=\(rawTranscript.count)")
        try taskCoordinator.recordRawTranscript(rawTranscript, kind: .agentDispatch)
        await dispatchCoordinator.dispatch(utterance: rawTranscript)
        guard activeTaskID == workflowTaskID else {
            throw CancellationError()
        }
        if !dispatchCoordinator.presentation.isFallbackInput {
            emitCurrentPresentation()
        }
        try taskCoordinator.completeAgentDispatch(
            finalText: dispatchCoordinator.lastDispatchedMessage ?? rawTranscript,
            presentation: dispatchCoordinator.presentation
        )
        AppLogger.dictation.debug("AgentDispatchHandler complete presentation=\(dispatchCoordinator.presentation)")
        if dispatchCoordinator.presentation.isConfirmation {
            scheduleConfirmationTimeout(utterance: rawTranscript, taskID: workflowTaskID)
        } else {
            cancelConfirmationTimeout()
        }
        if dispatchCoordinator.presentation.isTerminalBeforeFallbackOutput {
            activeTaskID = nil
            activeTarget = nil
        }
        return dispatchCoordinator.presentation
    }

    func completeFallbackInput(
        finalText: String,
        outputResult: OutputResult,
        appliedCorrectionEvents: [CorrectionEvent] = []
    ) throws {
        AppLogger.dictation.debug("AgentDispatchHandler completeFallbackInput finalLen=\(finalText.count) resultKind=\(outputResult.kind.rawValue)")
        cancelConfirmationTimeout()
        defer {
            activeTaskID = nil
            activeTarget = nil
        }
        try taskCoordinator.completeAgentDispatchFallbackInput(
            finalText: finalText,
            outputResult: outputResult,
            appliedCorrectionEvents: appliedCorrectionEvents
        )
    }

    func beginDefaultOutput() {
        AppLogger.dictation.debug("AgentDispatchHandler beginDefaultOutput")
        cancelConfirmationTimeout()
    }

    func confirm(agentID: String, utterance: String, message: String, alias: String?) async {
        guard let workflowTaskID = activeTaskID else { return }
        AppLogger.dictation.debug("AgentDispatchHandler confirm task=\(workflowTaskID) agent=\(agentID)")
        cancelConfirmationTimeout()
        await dispatchCoordinator.confirm(
            agentID: agentID,
            utterance: utterance,
            message: message,
            alias: alias
        )
        guard activeTaskID == workflowTaskID else { return }
        emitCurrentPresentation()
        try? taskCoordinator.completeAgentDispatch(
            finalText: message,
            presentation: dispatchCoordinator.presentation
        )
        if dispatchCoordinator.presentation.isTerminalBeforeFallbackOutput {
            activeTaskID = nil
            activeTarget = nil
        }
    }

    func cancel() {
        AppLogger.dictation.warning("AgentDispatchHandler cancel task=\(activeTaskID ?? "nil")")
        cancelConfirmationTimeout()
        dispatchCoordinator.invalidatePendingListening()
        try? taskCoordinator.cancelTask(kind: .agentDispatch)
        activeTaskID = nil
        activeTarget = nil
    }

    func fail(_ error: Error) {
        AppLogger.dictation.error("AgentDispatchHandler fail \(error.localizedDescription)")
        cancelConfirmationTimeout()
        dispatchCoordinator.invalidatePendingListening()
        try? taskCoordinator.recordFailure(
            stage: "agentDispatch",
            code: "agent_dispatch_failed",
            message: error.localizedDescription,
            recoverable: true,
            kind: .agentDispatch
        )
        activeTaskID = nil
        activeTarget = nil
    }

    private func emitCurrentPresentation() {
        AppLogger.dictation.debug("AgentDispatchHandler emit presentation=\(dispatchCoordinator.presentation)")
        onPresentationChange?(dispatchCoordinator.presentation)
    }

    private func scheduleConfirmationTimeout(utterance: String, taskID: String?) {
        cancelConfirmationTimeout()
        let timeoutNanoseconds = confirmationTimeoutNanoseconds
        AppLogger.dictation.debug("AgentDispatchHandler scheduleConfirmationTimeout isTimeoutSet=\(timeoutNanoseconds > 0)")
        confirmationTimeoutTask = Task { [weak self] in
            if timeoutNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            }
            guard !Task.isCancelled else { return }
            self?.handleConfirmationTimeout(utterance: utterance, taskID: taskID)
        }
    }

    private func handleConfirmationTimeout(utterance: String, taskID: String?) {
        guard activeTaskID == taskID,
              dispatchCoordinator.presentation.isConfirmation else {
            return
        }
        AppLogger.dictation.debug("AgentDispatchHandler confirmation timeout for task=\(taskID ?? "nil")")
        retainConfirmationWithoutClipboardAndFinish(utterance)
    }

    private func cancelConfirmationTimeout() {
        confirmationTimeoutTask?.cancel()
        confirmationTimeoutTask = nil
    }

    private func retainConfirmationWithoutClipboardAndFinish(_ text: String) {
        AppLogger.dictation.debug("AgentDispatchHandler confirmation timeout retained without clipboard")
        dispatchCoordinator.fail(message: "未选择任务助手", retainedText: text)
        emitCurrentPresentation()
        try? taskCoordinator.completeAgentDispatch(
            finalText: text,
            presentation: dispatchCoordinator.presentation
        )
        if dispatchCoordinator.presentation.isTerminalBeforeFallbackOutput {
            activeTaskID = nil
            activeTarget = nil
        }
        confirmationTimeoutTask = nil
    }
}

private extension AgentDispatchHUDPresentation {
    var isFallbackInput: Bool {
        if case .fallbackInput = self { return true }
        return false
    }

    var isConfirmation: Bool {
        if case .confirmation = self { return true }
        return false
    }

    var isTerminalBeforeFallbackOutput: Bool {
        switch self {
        case .clipboardFallback, .sent, .failure:
            return true
        case .fallbackInput, .idle, .listening, .exact, .confirmation:
            return false
        }
    }
}
