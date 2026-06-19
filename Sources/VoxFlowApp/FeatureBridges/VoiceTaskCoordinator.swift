import Foundation

enum VoiceWorkflowKind: String, Equatable, Hashable, Sendable {
    case dictation
    case agentCompose
    case clipboardImageOCR
    case screenshotOCR

    init(mode: VoiceTaskMode) {
        switch mode {
        case .dictation:
            self = .dictation
        case .agentCompose:
            self = .agentCompose
        }
    }
}

struct VoiceWorkflowLease: Equatable, Sendable {
    let kind: VoiceWorkflowKind
    let taskID: String
}

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
    private var activeWorkflows: [VoiceWorkflowKind: VoiceWorkflowLease] = [:]
    private var contextTask: ContextCollectionState?
    private var contextTaskGeneration: UInt64 = 0

    /// Emits accumulated text during streaming LLM generation.
    /// The handler (AgentComposeHandler → AppDelegate → Overlay) uses this to show real-time progress.
    var onStreamingDelta: ((String, String) -> Void)?

    var currentTaskID: String? {
        currentTask?.id
    }

    func activeTaskID(for kind: VoiceWorkflowKind) -> String? {
        activeWorkflows[kind]?.taskID
    }

    @discardableResult
    func beginEphemeralWorkflow(kind: VoiceWorkflowKind) throws -> VoiceWorkflowLease {
        guard kind == .clipboardImageOCR || kind == .screenshotOCR else {
            throw CoordinatorError.invalidMode
        }
        if activeWorkflows[kind] != nil {
            throw CoordinatorError.workflowAlreadyRunning(kind.rawValue)
        }
        let lease = VoiceWorkflowLease(
            kind: kind,
            taskID: "ephemeral-\(kind.rawValue)-\(UUID().uuidString)"
        )
        activeWorkflows[kind] = lease
        AppLogger.general.info("voice_workflow_started kind=\(kind.rawValue) taskID=\(lease.taskID)")
        return lease
    }

    func completeEphemeralWorkflow(_ lease: VoiceWorkflowLease) {
        guard activeWorkflows[lease.kind] == lease else { return }
        activeWorkflows.removeValue(forKey: lease.kind)
        AppLogger.general.info("voice_workflow_completed kind=\(lease.kind.rawValue) taskID=\(lease.taskID) status=completed")
    }

    func cancelEphemeralWorkflow(kind: VoiceWorkflowKind) {
        guard kind == .clipboardImageOCR || kind == .screenshotOCR,
              let lease = activeWorkflows[kind] else {
            return
        }
        activeWorkflows.removeValue(forKey: kind)
        AppLogger.general.info("voice_workflow_completed kind=\(kind.rawValue) taskID=\(lease.taskID) status=cancelled")
    }

    func isWorkflowLeaseActive(_ lease: VoiceWorkflowLease) -> Bool {
        activeWorkflows[lease.kind] == lease
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
        let workflowKind = VoiceWorkflowKind(mode: mode)
        if activeWorkflows[workflowKind] != nil {
            throw CoordinatorError.workflowAlreadyRunning(workflowKind.rawValue)
        }
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
        activeWorkflows[workflowKind] = VoiceWorkflowLease(kind: workflowKind, taskID: task.id)
        AppLogger.general.info("voice_workflow_started kind=\(workflowKind.rawValue) taskID=\(task.id)")
        currentTask = task
        return task
    }

    /// Records the raw transcript from ASR and advances the stage to transcribing.
    func recordRawTranscript(_ text: String) throws {
        try recordRawTranscript(text, kind: currentTask.map { VoiceWorkflowKind(mode: $0.mode) })
    }

    func recordRawTranscript(_ text: String, kind: VoiceWorkflowKind?) throws {
        guard var task = try task(for: kind) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try taskRepository.updateRawTranscript(id: task.id, rawTranscript: trimmed)
        task.rawTranscript = trimmed
        task.stage = .transcribing
        task.updatedAt = clock.now
        try taskRepository.updateStage(task)
        updateCurrentTaskIfMatching(task)
    }

    func updateASRMetadata(_ metadata: VoiceTaskASRMetadata) throws {
        try updateASRMetadata(metadata, kind: currentTask.map { VoiceWorkflowKind(mode: $0.mode) })
    }

    func updateASRMetadata(_ metadata: VoiceTaskASRMetadata, kind: VoiceWorkflowKind?) throws {
        guard var task = try task(for: kind) else { return }
        try taskRepository.updateASRMetadata(id: task.id, metadata: metadata)
        task.asrMetadata = metadata
        task.updatedAt = clock.now
        updateCurrentTaskIfMatching(task)
    }

    /// Processes text through the LLM pipeline and delivers via OutputService.
    func processAndDeliver() async throws -> OutputResult {
        try await processAndDeliver(kind: currentTask.map { VoiceWorkflowKind(mode: $0.mode) })
    }

    func processAndDeliver(kind: VoiceWorkflowKind?) async throws -> OutputResult {
        guard var task = try task(for: kind) else {
            throw CoordinatorError.noActiveTask
        }
        let workflowKind = kind ?? VoiceWorkflowKind(mode: task.mode)
        let taskID = task.id

        // Advance to processing stage
        task.stage = .processing
        task.updatedAt = clock.now
        try taskRepository.updateStage(task)

        let rawText = task.rawTranscript ?? ""
        let originalTarget = taskTarget(task)

        // Process through LLM pipeline
        let processingResult = await textPipeline.process(rawText, target: originalTarget)
        guard isActiveWorkflow(kind: workflowKind, taskID: taskID) else {
            return .cancelled
        }
        let finalText = processingResult.finalText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty ? rawText : processingResult.finalText

        try taskRepository.updateFinalText(id: taskID, finalText: finalText)
        task.finalText = finalText

        // Advance to outputting stage
        task.stage = .outputting
        task.updatedAt = clock.now
        try taskRepository.updateStage(task)

        // Re-read current target to detect focus changes
        guard isActiveWorkflow(kind: workflowKind, taskID: taskID) else {
            try? taskRepository.clearFinalText(id: taskID)
            return .cancelled
        }
        let currentTarget = targetProvider.currentTarget()

        // Deliver output
        let outputResult = await outputService.deliver(
            text: finalText,
            mode: task.mode,
            target: currentTarget,
            originalTarget: originalTarget
        )
        guard isActiveWorkflow(kind: workflowKind, taskID: taskID) else {
            try? taskRepository.clearFinalText(id: taskID)
            return .cancelled
        }
        if outputResult.kind == .cancelled {
            try taskRepository.clearFinalText(id: taskID)
            task.finalText = nil
        }

        // Encode and persist output result
        let encoded = String(
            data: try JSONEncoder().encode(outputResult.snapshot),
            encoding: .utf8
        )
        try taskRepository.updateOutputResult(id: taskID, outputResult: encoded ?? "")

        // Complete the task
        let completedAt = clock.now
        let status = terminalStatus(for: outputResult)
        try taskRepository.complete(
            id: taskID,
            status: status,
            outputResult: encoded,
            completedAt: completedAt
        )

        task.status = status
        task.outputResult = encoded
        task.completedAt = completedAt
        clearCurrentTaskIfMatching(task)
        AppLogger.general.info("voice_workflow_completed kind=\(workflowKind.rawValue) taskID=\(taskID) status=\(status.rawValue) output=\(outputResult.kind.rawValue)")
        clearWorkflowLease(for: task)

        return outputResult
    }

    // MARK: - Agent compose

    /// Starts context collection in parallel with recording for agent compose tasks.
    func startContextCollection(target: DictationTarget?, visionSupported: Bool) {
        guard let contextPipeline,
              let taskID = activeTaskID(for: .agentCompose) else { return }
        contextTask?.task.cancel()
        contextTaskGeneration &+= 1
        let task = Task.detached {
            await contextPipeline.collect(target: target, visionSupported: visionSupported)
        }
        AppLogger.general.info(
            "context_collection_started taskID=\(taskID) generation=\(contextTaskGeneration) visionSupported=\(visionSupported)"
        )
        contextTask = ContextCollectionState(
            taskID: taskID,
            generation: contextTaskGeneration,
            task: task
        )
    }

    /// Processes the current agent compose task using context and the agent prompt builder.
    /// Context failure degrades gracefully to dictation-only processing.
    /// LLM failure returns an actionable error.
    func processAgentComposeAndDeliver(
        context: ContextSnapshot?,
        stylePrompt: String?
    ) async throws -> OutputResult {
        guard var task = try task(for: .agentCompose) else {
            throw CoordinatorError.noActiveTask
        }
        guard task.mode == .agentCompose else {
            throw CoordinatorError.invalidMode
        }
        let taskID = task.id

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
                    guard isActiveWorkflow(kind: .agentCompose, taskID: taskID) else {
                        return .cancelled
                    }
                    accumulatedText = delta
                    onStreamingDelta?(taskID, delta)
                }
                guard isActiveWorkflow(kind: .agentCompose, taskID: taskID) else {
                    return .cancelled
                }
                try persistAgentTraceIfAvailable(taskID: taskID)
                let trimmed = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                finalText = trimmed.isEmpty ? rawText : trimmed
            } else {
                // Fallback: blocking call (non-RepositoryBackedLLMRefiner)
                let refinedText = try await agentRefiner.refine(request)
                guard isActiveWorkflow(kind: .agentCompose, taskID: taskID) else {
                    return .cancelled
                }
                try persistAgentTraceIfAvailable(taskID: taskID)
                let trimmed = refinedText.trimmingCharacters(in: .whitespacesAndNewlines)
                finalText = trimmed.isEmpty ? rawText : trimmed
            }
        } catch {
            guard isActiveWorkflow(kind: .agentCompose, taskID: taskID) else {
                return .cancelled
            }
            try? persistAgentTraceIfAvailable(taskID: taskID)
            AppLogger.general.error("Agent compose LLM failed: \(error.localizedDescription)")
            task.warnings.append("agent_llm_failed")
            try? taskRepository.updateWarnings(id: taskID, warnings: task.warnings)
            throw CoordinatorError.llmCallFailed(error.localizedDescription)
        }

        guard isActiveWorkflow(kind: .agentCompose, taskID: taskID) else {
            return .cancelled
        }

        try taskRepository.updateFinalText(id: taskID, finalText: finalText)
        task.finalText = finalText

        // Record context warnings in task
        if let context, !context.warnings.isEmpty {
            task.warnings.append(contentsOf: context.warnings)
            try? taskRepository.updateWarnings(id: taskID, warnings: task.warnings)
        }

        // Advance to outputting stage
        task.stage = .outputting
        task.updatedAt = clock.now
        try taskRepository.updateStage(task)

        // Safe output: inject only while the original target is still active; never simulate Enter.
        guard isActiveWorkflow(kind: .agentCompose, taskID: taskID) else {
            try? taskRepository.clearFinalText(id: taskID)
            return .cancelled
        }
        let currentTarget = targetProvider.currentTarget()
        let outputResult = await outputService.deliver(
            text: finalText,
            mode: .agentCompose,
            target: currentTarget,
            originalTarget: taskTarget(task)
        )
        guard isActiveWorkflow(kind: .agentCompose, taskID: taskID) else {
            try? taskRepository.clearFinalText(id: taskID)
            return .cancelled
        }
        if outputResult.kind == .cancelled {
            try taskRepository.clearFinalText(id: taskID)
            task.finalText = nil
        }

        // Encode and persist output result
        let encoded = String(
            data: try JSONEncoder().encode(outputResult.snapshot),
            encoding: .utf8
        )
        try taskRepository.updateOutputResult(id: taskID, outputResult: encoded ?? "")

        // Complete the task
        let completedAt = clock.now
        let status = terminalStatus(for: outputResult)
        try taskRepository.complete(
            id: taskID,
            status: status,
            outputResult: encoded,
            completedAt: completedAt
        )

        task.status = status
        task.outputResult = encoded
        task.completedAt = completedAt
        clearCurrentTaskIfMatching(task)
        AppLogger.general.info("voice_workflow_completed kind=agentCompose taskID=\(taskID) status=\(status.rawValue) output=\(outputResult.kind.rawValue)")
        clearWorkflowLease(for: task)

        return outputResult
    }

    /// Cancels any in-flight context collection.
    func cancelContextCollection() {
        contextTask?.task.cancel()
        contextTask = nil
        contextTaskGeneration &+= 1
    }

    /// Waits for context collection to complete and returns the result.
    /// Returns nil if no context collection was started.
    func awaitContextCollection(
        timeoutMilliseconds: Int = ContextPipeline.timeoutMilliseconds
    ) async -> ContextSnapshot? {
        guard let contextState = contextTask else {
            return nil
        }
        let taskID = contextState.taskID
        let generation = contextState.generation
        let task = contextState.task
        let timeoutNanoseconds = UInt64(max(timeoutMilliseconds, 0)) * 1_000_000

        let result = await withTaskGroup(of: ContextCollectionAwaitResult.self) { group in
            group.addTask {
                .completed(await task.value)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return .timedOut
            }

            let firstResult = await group.next() ?? .timedOut
            if case .timedOut = firstResult {
                task.cancel()
            }
            group.cancelAll()
            return firstResult
        }

        switch result {
        case .completed(let snapshot):
            if contextTaskGeneration == generation {
                contextTask = nil
            }
            guard isActiveWorkflow(kind: .agentCompose, taskID: taskID) else {
                AppLogger.general.info(
                    "context_collection_ignored taskID=\(taskID) generation=\(generation) reason=inactiveWorkflow"
                )
                return nil
            }
            AppLogger.general.info(
                "context_collection_completed taskID=\(taskID) generation=\(generation) warningCount=\(snapshot.warnings.count)"
            )
            return snapshot
        case .timedOut:
            if contextTaskGeneration == generation {
                contextState.task.cancel()
                contextTask = nil
                contextTaskGeneration &+= 1
            }
            guard isActiveWorkflow(kind: .agentCompose, taskID: taskID) else {
                AppLogger.general.info(
                    "context_collection_ignored taskID=\(taskID) generation=\(generation) reason=inactiveWorkflowAfterTimeout"
                )
                return nil
            }
            AppLogger.general.warning("context_collection_timeout taskID=\(taskID) generation=\(generation)")
            return ContextSnapshot(warnings: ["context_collection_timeout"])
        }
    }

    /// Cancels the current task.
    func cancelCurrentTask() throws {
        guard let task = currentTask else { return }
        if task.mode == .agentCompose {
            cancelContextCollection()
        }
        try taskRepository.clearFinalText(id: task.id)
        try taskRepository.complete(
            id: task.id,
            status: .cancelled,
            outputResult: nil,
            completedAt: clock.now
        )
        AppLogger.general.info("voice_workflow_completed kind=\(VoiceWorkflowKind(mode: task.mode).rawValue) taskID=\(task.id) status=cancelled")
        clearWorkflowLease(for: task)
        currentTask = nil
    }

    func cancelTask(kind: VoiceWorkflowKind) throws {
        guard let lease = activeWorkflows[kind],
              let task = try taskRepository.fetch(id: lease.taskID) else {
            return
        }
        if kind == .agentCompose {
            cancelContextCollection()
        }
        try taskRepository.clearFinalText(id: task.id)
        try taskRepository.complete(
            id: task.id,
            status: .cancelled,
            outputResult: nil,
            completedAt: clock.now
        )
        AppLogger.general.info("voice_workflow_completed kind=\(kind.rawValue) taskID=\(task.id) status=cancelled")
        activeWorkflows.removeValue(forKey: kind)
        if currentTask?.id == task.id {
            currentTask = nil
        }
    }

    /// Records a structured failure on the current task.
    func recordFailure(stage: String, code: String, message: String, recoverable: Bool) throws {
        try recordFailure(
            stage: stage,
            code: code,
            message: message,
            recoverable: recoverable,
            kind: currentTask.map { VoiceWorkflowKind(mode: $0.mode) }
        )
    }

    func recordFailure(
        stage: String,
        code: String,
        message: String,
        recoverable: Bool,
        kind: VoiceWorkflowKind?
    ) throws {
        guard let task = try task(for: kind) else { return }
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
        if kind == .agentCompose {
            cancelContextCollection()
        }
        AppLogger.general.error("voice_workflow_completed kind=\(VoiceWorkflowKind(mode: task.mode).rawValue) taskID=\(task.id) status=failed code=\(code) recoverable=\(recoverable)")
        clearWorkflowLease(for: task)
        if currentTask?.id == task.id {
            currentTask = nil
        }
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

    private func task(for kind: VoiceWorkflowKind?) throws -> VoiceTask? {
        guard let kind else {
            return currentTask
        }
        guard let lease = activeWorkflows[kind] else {
            return nil
        }
        if currentTask?.id == lease.taskID {
            return currentTask
        }
        return try taskRepository.fetch(id: lease.taskID)
    }

    private func terminalStatus(for result: OutputResult) -> VoiceTaskStatus {
        switch result {
        case .injected, .copied:
            return .completed
        case .cancelled:
            return .cancelled
        case .targetChanged, .permissionDenied, .injectionFailed, .copyFailed:
            return .partiallyCompleted
        }
    }

    private func updateCurrentTaskIfMatching(_ task: VoiceTask) {
        guard currentTask == nil || currentTask?.id == task.id else { return }
        currentTask = task
    }

    private func clearCurrentTaskIfMatching(_ task: VoiceTask) {
        guard currentTask?.id == task.id else { return }
        currentTask = nil
    }

    private func clearWorkflowLease(for task: VoiceTask) {
        let kind = VoiceWorkflowKind(mode: task.mode)
        if activeWorkflows[kind]?.taskID == task.id {
            activeWorkflows.removeValue(forKey: kind)
        }
    }

    private func isActiveWorkflow(kind: VoiceWorkflowKind, taskID: String) -> Bool {
        activeWorkflows[kind]?.taskID == taskID
    }

    private func persistAgentTraceIfAvailable(taskID: String) throws {
        guard let trace = (agentRefiner as? RefinementTraceProviding)?.lastTrace else {
            return
        }
        let processingTrace = TextProcessingTrace(llm: trace)
        LLMDiagnosticCapture.shared.capture(taskID: taskID, trace: processingTrace)
        let data = try JSONEncoder().encode(processingTrace.safeForPersistence())
        guard let json = String(data: data, encoding: .utf8) else {
            return
        }
        try taskRepository.updateTrace(id: taskID, trace: json)
    }

    private enum ContextCollectionAwaitResult: Sendable {
        case completed(ContextSnapshot)
        case timedOut
    }

    private struct ContextCollectionState {
        let taskID: String
        let generation: UInt64
        let task: Task<ContextSnapshot, Never>
    }
}

enum CoordinatorError: LocalizedError {
    case noActiveTask
    case invalidMode
    case llmNotConfigured
    case llmCallFailed(String)
    case workflowAlreadyRunning(String)

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
        case .workflowAlreadyRunning(let kind):
            return "已有进行中的 \(kind) 工作流。"
        }
    }
}
