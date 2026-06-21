import Foundation

@MainActor
protocol AgentDispatchHandling: AnyObject {
    var onPresentationChange: ((AgentDispatchHUDPresentation) -> Void)? { get set }
    func start(target: DictationTarget?, asrMetadata: VoiceTaskASRMetadata?) throws
    func updateASRMetadata(_ metadata: VoiceTaskASRMetadata) throws
    func finish(rawTranscript: String) async throws -> AgentDispatchHUDPresentation
    func completeFallbackInput(finalText: String, outputResult: OutputResult) throws
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
        cancelConfirmationTimeout()
        if activeTaskID != nil {
            try taskCoordinator.cancelTask(kind: .agentDispatch)
            activeTaskID = nil
        }
        let task = try taskCoordinator.startTask(
            mode: .agentDispatch,
            target: target,
            asrMetadata: asrMetadata
        )
        activeTaskID = task.id
        dispatchCoordinator.onPresentationChange = { [weak self] presentation in
            self?.onPresentationChange?(presentation)
        }
        Task { [weak self] in
            guard let self else { return }
            await self.dispatchCoordinator.startListening()
            self.emitCurrentPresentation()
        }
    }

    func updateASRMetadata(_ metadata: VoiceTaskASRMetadata) throws {
        try taskCoordinator.updateASRMetadata(metadata, kind: .agentDispatch)
    }

    func finish(rawTranscript: String) async throws -> AgentDispatchHUDPresentation {
        guard activeTaskID != nil else {
            throw CoordinatorError.noActiveTask
        }
        try taskCoordinator.recordRawTranscript(rawTranscript, kind: .agentDispatch)
        await dispatchCoordinator.dispatch(utterance: rawTranscript)
        emitCurrentPresentation()
        try taskCoordinator.completeAgentDispatch(
            finalText: rawTranscript,
            presentation: dispatchCoordinator.presentation
        )
        if dispatchCoordinator.presentation.isConfirmation {
            scheduleConfirmationTimeout(utterance: rawTranscript, taskID: activeTaskID)
        } else {
            cancelConfirmationTimeout()
        }
        if dispatchCoordinator.presentation.isTerminalBeforeFallbackOutput {
            activeTaskID = nil
        }
        return dispatchCoordinator.presentation
    }

    func completeFallbackInput(finalText: String, outputResult: OutputResult) throws {
        try taskCoordinator.completeAgentDispatchFallbackInput(
            finalText: finalText,
            outputResult: outputResult
        )
        activeTaskID = nil
    }

    func confirm(agentID: String, utterance: String, message: String, alias: String?) async {
        guard activeTaskID != nil else { return }
        cancelConfirmationTimeout()
        await dispatchCoordinator.confirm(
            agentID: agentID,
            utterance: utterance,
            message: message,
            alias: alias
        )
        emitCurrentPresentation()
        try? taskCoordinator.completeAgentDispatch(
            finalText: message,
            presentation: dispatchCoordinator.presentation
        )
        if dispatchCoordinator.presentation.isTerminalBeforeFallbackOutput {
            activeTaskID = nil
        }
    }

    func cancel() {
        cancelConfirmationTimeout()
        dispatchCoordinator.invalidatePendingListening()
        try? taskCoordinator.cancelTask(kind: .agentDispatch)
        activeTaskID = nil
    }

    func fail(_ error: Error) {
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
    }

    private func emitCurrentPresentation() {
        onPresentationChange?(dispatchCoordinator.presentation)
    }

    private func scheduleConfirmationTimeout(utterance: String, taskID: String?) {
        cancelConfirmationTimeout()
        let timeoutNanoseconds = confirmationTimeoutNanoseconds
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
        copyConfirmationToClipboardAndFinish(utterance)
    }

    private func cancelConfirmationTimeout() {
        confirmationTimeoutTask?.cancel()
        confirmationTimeoutTask = nil
    }

    private func copyConfirmationToClipboardAndFinish(_ text: String) {
        if clipboardService.setString(text) {
            dispatchCoordinator.fallbackToClipboard(text: text)
        } else {
            dispatchCoordinator.fail(message: "复制到剪切板失败", retainedText: text)
        }
        emitCurrentPresentation()
        try? taskCoordinator.completeAgentDispatch(
            finalText: text,
            presentation: dispatchCoordinator.presentation
        )
        if dispatchCoordinator.presentation.isTerminalBeforeFallbackOutput {
            activeTaskID = nil
        }
        confirmationTimeoutTask = nil
    }
}

private extension AgentDispatchHUDPresentation {
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
