import Foundation

@MainActor
final class VoiceTaskCoordinator {
    private let taskRepository: VoiceTaskRepository
    private let outputService: any OutputService
    private let textPipeline: any TextProcessing
    private let targetProvider: any DictationTargetProviding
    private let clock: any AppClock
    private let contextPipeline: (any ContextCollecting)?
    private let agentRefiner: (any PromptAwareTextRefining)?

    private var currentTask: VoiceTask?
    private var contextTask: Task<ContextSnapshot, Never>?

    /// Emits accumulated text during streaming LLM generation.
    /// The handler (AgentComposeHandler → AppDelegate → Overlay) uses this to show real-time progress.
    var onStreamingDelta: ((String) -> Void)?

    var currentTaskID: String? {
        currentTask?.id
    }

    init(
        taskRepository: VoiceTaskRepository,
        outputService: any OutputService,
        textPipeline: any TextProcessing,
        targetProvider: any DictationTargetProviding,
        clock: any AppClock = SystemClock(),
        contextPipeline: (any ContextCollecting)? = nil,
        agentRefiner: (any PromptAwareTextRefining)? = nil
    ) {
        self.taskRepository = taskRepository
        self.outputService = outputService
        self.textPipeline = textPipeline
        self.targetProvider = targetProvider
        self.clock = clock
        self.contextPipeline = contextPipeline
        self.agentRefiner = agentRefiner
    }

    // MARK: - Recording lifecycle

    /// Creates a new VoiceTask when recording starts.
    @discardableResult
    func startTask(
        mode: VoiceTaskMode,
        target: DictationTarget?,
        asrMetadata: VoiceTaskASRMetadata? = nil
    ) throws -> VoiceTask {
        let now = clock.now
        let task = VoiceTask(
            id: UUID().uuidString,
            mode: mode,
            stage: .recording,
            status: .inProgress,
            targetAppBundleID: target?.bundleID,
            targetAppName: target?.appName,
            targetAppPID: target?.pid,
            targetWindowID: target?.windowID,
            targetWindowTitle: target?.windowTitle,
            asrMetadata: asrMetadata,
            createdAt: now,
            updatedAt: now
        )
        try taskRepository.create(task)
        currentTask = task
        return task
    }

    /// Records the raw transcript from ASR and advances the stage to transcribing.
    func recordRawTranscript(_ text: String) throws {
        guard var task = currentTask else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try taskRepository.updateRawTranscript(id: task.id, rawTranscript: trimmed)
        task.rawTranscript = trimmed
        task.stage = .transcribing
        task.updatedAt = clock.now
        try taskRepository.updateStage(task)
        currentTask = task
    }

    func updateASRMetadata(_ metadata: VoiceTaskASRMetadata) throws {
        guard var task = currentTask else { return }
        try taskRepository.updateASRMetadata(id: task.id, metadata: metadata)
        task.asrMetadata = metadata
        task.updatedAt = clock.now
        currentTask = task
    }

    /// Processes text through the LLM pipeline and delivers via OutputService.
    func processAndDeliver() async throws -> OutputResult {
        guard var task = currentTask else {
            throw CoordinatorError.noActiveTask
        }

        // Advance to processing stage
        task.stage = .processing
        task.updatedAt = clock.now
        try taskRepository.updateStage(task)

        let rawText = task.rawTranscript ?? ""
        let originalTarget = taskTarget(task)

        // Process through LLM pipeline
        let processingResult = await textPipeline.process(rawText, target: originalTarget)
        let finalText = processingResult.finalText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty ? rawText : processingResult.finalText

        try taskRepository.updateFinalText(id: task.id, finalText: finalText)
        task.finalText = finalText

        // Advance to outputting stage
        task.stage = .outputting
        task.updatedAt = clock.now
        try taskRepository.updateStage(task)

        // Re-read current target to detect focus changes
        let currentTarget = targetProvider.currentTarget()

        // Deliver output
        let outputResult = await outputService.deliver(
            text: finalText,
            mode: task.mode,
            target: currentTarget,
            originalTarget: originalTarget
        )

        // Encode and persist output result
        let encoded = String(
            data: try JSONEncoder().encode(outputResult),
            encoding: .utf8
        )
        try taskRepository.updateOutputResult(id: task.id, outputResult: encoded ?? "")

        // Complete the task
        let completedAt = clock.now
        let status: VoiceTaskStatus = isSuccess(outputResult) ? .completed : .partiallyCompleted
        try taskRepository.complete(
            id: task.id,
            status: status,
            outputResult: encoded,
            completedAt: completedAt
        )

        task.status = status
        task.outputResult = encoded
        task.completedAt = completedAt
        currentTask = task

        return outputResult
    }

    // MARK: - Agent compose

    /// Starts context collection in parallel with recording for agent compose tasks.
    func startContextCollection(target: DictationTarget?, visionSupported: Bool) {
        guard let contextPipeline else { return }
        contextTask = Task.detached {
            await contextPipeline.collect(target: target, visionSupported: visionSupported)
        }
    }

    /// Processes the current agent compose task using context and the agent prompt builder.
    /// Context failure degrades gracefully to dictation-only processing.
    /// LLM failure returns an actionable error.
    func processAgentComposeAndDeliver(
        context: ContextSnapshot?,
        stylePrompt: String?
    ) async throws -> OutputResult {
        guard var task = currentTask else {
            throw CoordinatorError.noActiveTask
        }
        guard task.mode == .agentCompose else {
            throw CoordinatorError.invalidMode
        }

        // Check LLM availability
        guard let agentRefiner else {
            throw CoordinatorError.llmNotConfigured
        }
        guard agentRefiner.isConfigured else {
            throw CoordinatorError.llmNotConfigured
        }

        // Persist context snapshot
        if let context {
            if let contextData = try? JSONEncoder().encode(context),
               let contextJson = String(data: contextData, encoding: .utf8) {
                try? taskRepository.updateContextJson(id: task.id, contextJson: contextJson)
                task.contextJson = contextJson
            }
        }

        // Advance to collectingContext stage
        task.stage = .collectingContext
        task.updatedAt = clock.now
        try taskRepository.updateStage(task)

        // Advance to processing stage
        task.stage = .processing
        task.updatedAt = clock.now
        try taskRepository.updateStage(task)

        let rawText = task.rawTranscript ?? ""

        // Build agent prompt
        let builder = AgentPromptBuilder()
        let request = builder.build(
            appName: task.targetAppName,
            stylePrompt: stylePrompt,
            context: context,
            userDictation: rawText
        )

        // Call LLM (streaming for real-time HUD updates)
        let finalText: String
        do {
            (agentRefiner as? RefinementTraceProviding)?.clearLastTrace()

            if let streamingRefiner = agentRefiner as? RepositoryBackedLLMRefiner {
                // Streaming path: emit deltas via onStreamingDelta callback
                let stream = streamingRefiner.refineStream(request)
                var accumulatedText = ""
                for try await delta in stream {
                    accumulatedText = delta
                    onStreamingDelta?(delta)
                }
                try persistAgentTraceIfAvailable(taskID: task.id)
                let trimmed = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                finalText = trimmed.isEmpty ? rawText : trimmed
            } else {
                // Fallback: blocking call (non-RepositoryBackedLLMRefiner)
                let refinedText = try await agentRefiner.refine(request)
                try persistAgentTraceIfAvailable(taskID: task.id)
                let trimmed = refinedText.trimmingCharacters(in: .whitespacesAndNewlines)
                finalText = trimmed.isEmpty ? rawText : trimmed
            }
        } catch {
            try? persistAgentTraceIfAvailable(taskID: task.id)
            AppLogger.general.error("Agent compose LLM failed: \(error.localizedDescription)")
            task.warnings.append("agent_llm_failed")
            try? taskRepository.updateWarnings(id: task.id, warnings: task.warnings)
            throw CoordinatorError.llmCallFailed(error.localizedDescription)
        }

        try taskRepository.updateFinalText(id: task.id, finalText: finalText)
        task.finalText = finalText

        // Record context warnings in task
        if let context, !context.warnings.isEmpty {
            task.warnings.append(contentsOf: context.warnings)
            try? taskRepository.updateWarnings(id: task.id, warnings: task.warnings)
        }

        // Advance to outputting stage
        task.stage = .outputting
        task.updatedAt = clock.now
        try taskRepository.updateStage(task)

        // Safe output: inject only while the original target is still active; never simulate Enter.
        let currentTarget = targetProvider.currentTarget()
        let outputResult = await outputService.deliver(
            text: finalText,
            mode: .agentCompose,
            target: currentTarget,
            originalTarget: taskTarget(task)
        )

        // Encode and persist output result
        let encoded = String(
            data: try JSONEncoder().encode(outputResult),
            encoding: .utf8
        )
        try taskRepository.updateOutputResult(id: task.id, outputResult: encoded ?? "")

        // Complete the task
        let completedAt = clock.now
        let status: VoiceTaskStatus = isSuccess(outputResult) ? .completed : .partiallyCompleted
        try taskRepository.complete(
            id: task.id,
            status: status,
            outputResult: encoded,
            completedAt: completedAt
        )

        task.status = status
        task.outputResult = encoded
        task.completedAt = completedAt
        currentTask = task

        return outputResult
    }

    /// Cancels any in-flight context collection.
    func cancelContextCollection() {
        contextTask?.cancel()
        contextTask = nil
    }

    /// Waits for context collection to complete and returns the result.
    /// Returns nil if no context collection was started.
    func awaitContextCollection() async -> ContextSnapshot? {
        await contextTask?.value
    }

    /// Cancels the current task.
    func cancelCurrentTask() throws {
        guard let task = currentTask else { return }
        try taskRepository.complete(
            id: task.id,
            status: .cancelled,
            outputResult: nil,
            completedAt: clock.now
        )
        currentTask = nil
    }

    /// Records a structured failure on the current task.
    func recordFailure(stage: String, code: String, message: String, recoverable: Bool) throws {
        guard let task = currentTask else { return }
        let failure = VoiceTaskFailure(
            stage: stage,
            code: code,
            message: message,
            recoverable: recoverable
        )
        let encoded = String(
            data: try JSONEncoder().encode(failure),
            encoding: .utf8
        ) ?? ""
        try taskRepository.updateFailure(
            id: task.id,
            failureJson: encoded,
            status: .failed
        )
        currentTask = nil
    }

    // MARK: - Incomplete task detection (Task 2.10)

    /// Queries incomplete tasks on startup. The caller decides whether to show a notification.
    func checkIncompleteTasks() throws -> [VoiceTask] {
        try taskRepository.queryIncompleteTasks()
    }

    // MARK: - Private

    private func taskTarget(_ task: VoiceTask) -> DictationTarget? {
        guard task.targetAppBundleID != nil || task.targetAppName != nil else {
            return nil
        }
        return DictationTarget(
            bundleID: task.targetAppBundleID,
            appName: task.targetAppName,
            pid: task.targetAppPID,
            windowID: task.targetWindowID,
            windowTitle: task.targetWindowTitle
        )
    }

    private func isSuccess(_ result: OutputResult) -> Bool {
        switch result {
        case .injected, .copied:
            return true
        case .targetChanged, .permissionDenied, .injectionFailed, .copyFailed, .cancelled:
            return false
        }
    }

    private func persistAgentTraceIfAvailable(taskID: String) throws {
        guard let trace = (agentRefiner as? RefinementTraceProviding)?.lastTrace else {
            return
        }
        let processingTrace = TextProcessingTrace(llm: trace)
        let data = try JSONEncoder().encode(processingTrace)
        guard let json = String(data: data, encoding: .utf8) else {
            return
        }
        try taskRepository.updateTrace(id: taskID, trace: json)
    }
}

enum CoordinatorError: LocalizedError {
    case noActiveTask
    case invalidMode
    case llmNotConfigured
    case llmCallFailed(String)

    var errorDescription: String? {
        switch self {
        case .noActiveTask:
            return "没有活跃的语音任务。"
        case .invalidMode:
            return "任务模式不支持此操作。"
        case .llmNotConfigured:
            return "未配置 LLM。请在设置中添加 LLM 提供方以使用帮我说功能。"
        case .llmCallFailed(let reason):
            return "LLM 调用失败：\(reason)"
        }
    }
}
