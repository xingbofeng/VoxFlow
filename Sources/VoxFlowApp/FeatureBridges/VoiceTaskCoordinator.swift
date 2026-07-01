import Foundation
import VoxFlowVoiceCorrection

enum VoiceWorkflowKind: String, Equatable, Hashable, Sendable {
    case dictation
    case agentCompose
    case agentDispatch
    case clipboardImageOCR
    case screenshotOCR

    init(mode: VoiceTaskMode) {
        switch mode {
        case .dictation:
            self = .dictation
        case .agentCompose:
            self = .agentCompose
        case .agentDispatch:
            self = .agentDispatch
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
    private let agentRuntimeService: (any AgentRuntimeServing)?
    private let agentRuntimeSelection: @MainActor () -> AgentRuntimeProviderSelection?
    private let correctionObservationScheduler: (any CorrectionObservationScheduling)?
    private let assetRepository: (any AssetRepository)?
    private let isFocusedTextFieldSecure: @MainActor () -> Bool

    private let taskRuntime = VoiceTaskRuntimeStore()
    private var contextTask: ContextCollectionState?
    private var contextTaskGeneration: UInt64 = 0

    /// Emits accumulated text during streaming LLM generation.
    /// The handler (AgentComposeHandler → AppDelegate → Overlay) uses this to show real-time progress.
    var onStreamingDelta: ((String, String) -> Void)?

    var currentTaskID: String? {
        taskRuntime.currentTaskID
    }

    func activeTaskID(for kind: VoiceWorkflowKind) -> String? {
        taskRuntime.activeTaskID(for: kind)
    }

    @discardableResult
    func beginEphemeralWorkflow(kind: VoiceWorkflowKind) throws -> VoiceWorkflowLease {
        guard kind == .clipboardImageOCR || kind == .screenshotOCR else {
            throw CoordinatorError.invalidMode
        }
        let lease = try taskRuntime.beginEphemeralWorkflow(kind: kind)
        AppLogger.general.info("voice_workflow_started kind=\(kind.rawValue) taskID=\(lease.taskID)")
        return lease
    }

    func completeEphemeralWorkflow(_ lease: VoiceWorkflowLease) {
        guard taskRuntime.completeEphemeralWorkflow(lease) else { return }
        AppLogger.general.info("voice_workflow_completed kind=\(lease.kind.rawValue) taskID=\(lease.taskID) status=completed")
    }

    func registerEphemeralWorkflowTask(_ task: Task<Void, Never>, for lease: VoiceWorkflowLease) {
        taskRuntime.registerEphemeralWorkflowTask(task, for: lease)
    }

    func cancelEphemeralWorkflow(kind: VoiceWorkflowKind) {
        guard kind == .clipboardImageOCR || kind == .screenshotOCR,
              let lease = taskRuntime.cancelEphemeralWorkflow(kind: kind) else {
            return
        }
        AppLogger.general.info("voice_workflow_completed kind=\(kind.rawValue) taskID=\(lease.taskID) status=cancelled")
    }

    func isWorkflowLeaseActive(_ lease: VoiceWorkflowLease) -> Bool {
        taskRuntime.isWorkflowLeaseActive(lease)
    }

    init(
        taskRepository: VoiceTaskRepository,
        outputService: any OutputService,
        textPipeline: any TextProcessing,
        targetProvider: any DictationTargetProviding,
        clock: any AppClock = SystemClock(),
        contextPipeline: (any ContextCollecting)? = nil,
        agentRefiner: (any PromptAwareTextRefining)? = nil,
        agentRuntimeService: (any AgentRuntimeServing)? = nil,
        agentRuntimeSelection: @escaping @MainActor () -> AgentRuntimeProviderSelection? = { nil },
        correctionObservationScheduler: (any CorrectionObservationScheduling)? = nil,
        assetRepository: (any AssetRepository)? = nil,
        isFocusedTextFieldSecure: @escaping @MainActor () -> Bool = { false }
    ) {
        self.taskRepository = taskRepository
        self.outputService = outputService
        self.textPipeline = textPipeline
        self.targetProvider = targetProvider
        self.clock = clock
        self.contextPipeline = contextPipeline
        self.agentRefiner = agentRefiner
        self.agentRuntimeService = agentRuntimeService
        self.agentRuntimeSelection = agentRuntimeSelection
        self.correctionObservationScheduler = correctionObservationScheduler
        self.assetRepository = assetRepository
        self.isFocusedTextFieldSecure = isFocusedTextFieldSecure
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
        try taskRuntime.beginPersistedWorkflow(task, kind: workflowKind)
        AppLogger.general.info("voice_workflow_started kind=\(workflowKind.rawValue) taskID=\(task.id)")
        return task
    }

    /// Records the raw transcript from ASR and advances the stage to transcribing.
    func recordRawTranscript(_ text: String) throws {
        try recordRawTranscript(text, kind: taskRuntime.currentWorkflowKind)
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
        taskRuntime.updatePersistedTask(task)
    }

    func updateASRMetadata(_ metadata: VoiceTaskASRMetadata) throws {
        try updateASRMetadata(metadata, kind: taskRuntime.currentWorkflowKind)
    }

    func updateASRMetadata(_ metadata: VoiceTaskASRMetadata, kind: VoiceWorkflowKind?) throws {
        guard var task = try task(for: kind) else { return }
        try taskRepository.updateASRMetadata(id: task.id, metadata: metadata)
        task.asrMetadata = metadata
        task.updatedAt = clock.now
        taskRuntime.updatePersistedTask(task)
    }

    func completeAgentDispatch(
        finalText: String,
        presentation: AgentDispatchHUDPresentation,
        processingTrace: TextProcessingTrace? = nil
    ) throws {
        guard var task = try task(for: .agentDispatch) else {
            throw CoordinatorError.noActiveTask
        }
        let taskID = task.id
        let snapshot = AgentDispatchTaskSnapshot(presentation: presentation)
        let encoded = String(
            data: try JSONEncoder().encode(snapshot),
            encoding: .utf8
        ) ?? ""

        try taskRepository.updateFinalText(id: taskID, finalText: finalText)
        task.finalText = finalText
        try taskRepository.updateOutputResult(id: taskID, outputResult: encoded)
        try persistAgentDispatchTrace(
            taskID: taskID,
            presentation: presentation,
            processingTrace: processingTrace
        )

        switch presentation {
        case .sent, .clipboardFallback:
            let completedAt = clock.now
            task.stage = .outputting
            task.updatedAt = completedAt
            try taskRepository.updateStage(task)
            try taskRepository.complete(
                id: taskID,
                status: .completed,
                outputResult: encoded,
                completedAt: completedAt
            )
            task.status = .completed
            task.updatedAt = completedAt
            task.completedAt = completedAt
            task.outputResult = encoded
            taskRuntime.clearWorkflow(for: task)
            saveRawVoiceTextAssetIfNeeded(
                task: task,
                rawText: task.rawTranscript ?? finalText,
                captureReason: agentDispatchCaptureReason(for: presentation),
                completedAt: completedAt
            )
        case .fallbackInput:
            task.stage = .processing
            task.updatedAt = clock.now
            task.outputResult = encoded
            try taskRepository.updateStage(task)
            taskRuntime.updatePersistedTask(task)
        case .failure:
            try recordFailure(
                stage: "agentDispatch",
                code: "agent_dispatch_failed",
                message: presentation.detail,
                recoverable: true,
                kind: .agentDispatch
            )
        case .confirmation, .exact, .listening, .idle:
            task.stage = .processing
            task.updatedAt = clock.now
            try taskRepository.updateStage(task)
            taskRuntime.updatePersistedTask(task)
        }
    }

    func processAgentDispatchMessage(_ text: String) async throws -> TextProcessingResult {
        guard var task = try task(for: .agentDispatch) else {
            throw CoordinatorError.noActiveTask
        }
        let taskID = task.id

        task.stage = .processing
        task.updatedAt = clock.now
        try taskRepository.updateStage(task)
        taskRuntime.updatePersistedTask(task)

        let originalTarget = taskTarget(task)
        let correctionContext = CorrectionContext(
            mode: .dictation,
            providerID: task.asrMetadata?.providerID ?? "unknown",
            modelID: task.asrMetadata?.modelID,
            language: task.asrMetadata?.language,
            bundleIdentifier: originalTarget?.bundleID,
            isFinalTranscript: true,
            isSecureField: isFocusedTextFieldSecure()
        )
        let processingResult = await textPipeline.process(
            text,
            target: originalTarget,
            correctionContext: correctionContext
        )
        guard isActiveWorkflow(kind: .agentDispatch, taskID: taskID) else {
            throw CancellationError()
        }
        return processingResult
    }

    func completeAgentDispatchFallbackInput(
        finalText: String,
        outputResult: OutputResult,
        appliedCorrectionEvents: [CorrectionEvent] = [],
        processingTrace: TextProcessingTrace? = nil
    ) throws {
        guard var task = try task(for: .agentDispatch) else {
            throw CoordinatorError.noActiveTask
        }
        let taskID = task.id
        let encoded = String(
            data: try JSONEncoder().encode(outputResult.snapshot),
            encoding: .utf8
        )
        try persistAgentDispatchDefaultOutputTrace(
            taskID: taskID,
            processingTrace: processingTrace,
            outputResult: outputResult
        )

        if outputResult.kind == .cancelled {
            try taskRepository.clearFinalText(id: taskID)
            task.finalText = nil
        } else {
            try taskRepository.updateFinalText(id: taskID, finalText: finalText)
            task.finalText = finalText
        }
        try taskRepository.updateOutputResult(id: taskID, outputResult: encoded ?? "")

        let status = terminalStatus(for: outputResult)
        let completedAt = clock.now
        task.stage = .outputting
        task.updatedAt = completedAt
        try taskRepository.updateStage(task)
        try taskRepository.complete(
            id: taskID,
            status: status,
            outputResult: encoded,
            completedAt: completedAt
        )
        task.status = status
        task.outputResult = encoded
        task.completedAt = completedAt
        AppLogger.general.info("voice_workflow_completed kind=agentDispatch taskID=\(taskID) status=\(status.rawValue) output=\(outputResult.kind.rawValue)")
        taskRuntime.clearWorkflow(for: task)
        saveRawVoiceTextAssetIfNeeded(
            task: task,
            rawText: task.rawTranscript ?? finalText,
            captureReason: dictationCaptureReason(for: outputResult),
            completedAt: completedAt
        )
    }

    /// Processes text through the LLM pipeline and delivers via OutputService.
    func processAndDeliver() async throws -> OutputResult {
        try await processAndDeliver(kind: taskRuntime.currentWorkflowKind)
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
        taskRuntime.updatePersistedTask(task)

        let rawText = task.rawTranscript ?? ""
        let originalTarget = taskTarget(task)

        // Process through LLM pipeline
        let correctionContext: CorrectionContext? = task.mode == .dictation
            ? CorrectionContext(
                mode: .dictation,
                providerID: task.asrMetadata?.providerID ?? "unknown",
                modelID: task.asrMetadata?.modelID,
                language: task.asrMetadata?.language,
                bundleIdentifier: originalTarget?.bundleID,
                isFinalTranscript: true,
                isSecureField: isFocusedTextFieldSecure()
            )
            : nil
        let processingResult = await textPipeline.process(
            rawText,
            target: originalTarget,
            correctionContext: correctionContext
        )
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
        taskRuntime.updatePersistedTask(task)

        // Re-read current target to detect focus changes
        guard isActiveWorkflow(kind: workflowKind, taskID: taskID) else {
            try? taskRepository.clearFinalText(id: taskID)
            return .cancelled
        }
        let currentTarget = targetProvider.currentTarget()

        // Deliver output
        let correctionObservationAnchor = correctionObservationAnchorIfNeeded(
            context: correctionContext,
            targetProcessID: originalTarget?.pid
        )
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
        try? persistTextProcessingTrace(
            taskID: taskID,
            processingTrace: processingResult.trace,
            outputResult: outputResult
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
        taskRuntime.clearCurrentTaskIfMatching(task)
        AppLogger.general.info("voice_workflow_completed kind=\(workflowKind.rawValue) taskID=\(taskID) status=\(status.rawValue) output=\(outputResult.kind.rawValue)")
        taskRuntime.clearWorkflow(for: task)
        if task.mode == .dictation {
            saveVoiceTextAssetIfNeeded(
                task: task,
                rawText: rawText,
                finalText: finalText,
                outputResult: outputResult,
                completedAt: completedAt
            )
        } else {
            saveAgentComposeVoiceAssetIfNeeded(
                task: task,
                rawText: rawText,
                outputResult: outputResult,
                completedAt: completedAt
            )
        }
        scheduleCorrectionObservationIfNeeded(
            task: task,
            finalText: finalText,
            correctionContext: correctionContext,
            processingResult: processingResult,
            outputResult: outputResult,
            baseline: correctionObservationBaseline(from: correctionObservationAnchor),
            targetProcessID: originalTarget?.pid
        )

        return outputResult
    }

    private func scheduleCorrectionObservationIfNeeded(
        task: VoiceTask,
        finalText: String,
        correctionContext: CorrectionContext?,
        processingResult: TextProcessingResult,
        outputResult: OutputResult,
        baseline: FocusedTextObservation?,
        targetProcessID: Int?
    ) {
        guard task.mode == .dictation,
              case .injected = outputResult,
              let correctionContext,
              !correctionContext.isSecureField
        else {
            return
        }
        if processingResult.trace?.llm?.succeeded == true,
           processingResult.finalText != processingResult.rawText {
            return
        }
        correctionObservationScheduler?.scheduleObservation(
            insertedText: finalText,
            context: correctionContext,
            appliedEvents: processingResult.appliedCorrectionEvents,
            baseline: baseline,
            targetProcessID: targetProcessID
        )
    }

    private func correctionObservationAnchorIfNeeded(
        context: CorrectionContext?,
        targetProcessID: Int?
    ) -> FocusedTextObservation? {
        guard let context, !context.isSecureField else { return nil }
        return correctionObservationScheduler?.captureBaselineForObservation(targetProcessID: targetProcessID)
    }

    private func correctionObservationBaseline(from anchor: FocusedTextObservation?) -> FocusedTextObservation? {
        guard let anchor else { return nil }
        return correctionObservationScheduler?.recaptureBaselineForObservation(matching: anchor)
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
        stylePrompt: String?,
        onAgentRuntimeStage: (@MainActor (AgentComposeHUDStage) -> Void)? = nil,
        onAgentRuntimeCompleted: (@MainActor (String) -> Void)? = nil
    ) async throws -> OutputResult {
        guard var task = try task(for: .agentCompose) else {
            throw CoordinatorError.noActiveTask
        }
        guard task.mode == .agentCompose else {
            throw CoordinatorError.invalidMode
        }
        let taskID = task.id

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
        taskRuntime.updatePersistedTask(task)

        // Advance to processing stage
        task.stage = .processing
        task.updatedAt = clock.now
        try taskRepository.updateStage(task)
        taskRuntime.updatePersistedTask(task)

        let rawText = task.rawTranscript ?? ""

        if let runtimeResult = try await processAgentRuntimeIfAvailable(
            task: task,
            rawText: rawText,
            context: context,
            onAgentRuntimeStage: onAgentRuntimeStage,
            onAgentRuntimeCompleted: onAgentRuntimeCompleted
        ) {
            return runtimeResult
        }

        // Check LLM availability after runtime fallback. Non-Codex providers
        // keep the existing "帮我说" path.
        guard let agentRefiner else {
            throw CoordinatorError.llmNotConfigured
        }
        guard agentRefiner.isConfigured else {
            throw CoordinatorError.llmNotConfigured
        }

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

            if let streamingRefiner = agentRefiner as? any TraceableStreamingPromptAwareTextRefining {
                // Streaming path: emit deltas via onStreamingDelta callback
                let streamResult = streamingRefiner.refineStreamWithTrace(request)
                var accumulatedText = ""
                for try await delta in streamResult.stream {
                    guard isActiveWorkflow(kind: .agentCompose, taskID: taskID) else {
                        return .cancelled
                    }
                    accumulatedText = delta
                    onStreamingDelta?(taskID, delta)
                }
                guard isActiveWorkflow(kind: .agentCompose, taskID: taskID) else {
                    return .cancelled
                }
                try persistAgentTrace(taskID: taskID, trace: try await streamResult.trace.value())
                let trimmed = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                finalText = trimmed.isEmpty ? rawText : trimmed
            } else if let streamingRefiner = agentRefiner as? any StreamingPromptAwareTextRefining {
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
        taskRuntime.updatePersistedTask(task)

        // Record context warnings in task
        if let context, !context.warnings.isEmpty {
            task.warnings.append(contentsOf: context.warnings)
            try? taskRepository.updateWarnings(id: taskID, warnings: task.warnings)
        }

        // Advance to outputting stage
        task.stage = .outputting
        task.updatedAt = clock.now
        try taskRepository.updateStage(task)
        taskRuntime.updatePersistedTask(task)

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
        taskRuntime.clearCurrentTaskIfMatching(task)
        AppLogger.general.info("voice_workflow_completed kind=agentCompose taskID=\(taskID) status=\(status.rawValue) output=\(outputResult.kind.rawValue)")
        taskRuntime.clearWorkflow(for: task)
        saveAgentComposeVoiceAssetIfNeeded(
            task: task,
            rawText: rawText,
            outputResult: outputResult,
            completedAt: completedAt
        )

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
        guard let task = taskRuntime.currentTask else { return }
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
        taskRuntime.clearWorkflow(for: task)
    }

    func cancelTask(kind: VoiceWorkflowKind) throws {
        guard let lease = taskRuntime.lease(for: kind),
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
        taskRuntime.clearWorkflow(kind: kind, taskID: task.id)
    }

    /// Records a structured failure on the current task.
    func recordFailure(stage: String, code: String, message: String, recoverable: Bool) throws {
        try recordFailure(
            stage: stage,
            code: code,
            message: message,
            recoverable: recoverable,
            kind: taskRuntime.currentWorkflowKind
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
        taskRuntime.clearWorkflow(for: task)
        saveFailedVoiceAssetIfNeeded(task: task, completedAt: clock.now)
    }

    // MARK: - Incomplete task detection (Task 2.10)

    /// Queries incomplete tasks on startup. The caller decides whether to show a notification.
    func checkIncompleteTasks() throws -> [VoiceTask] {
        try taskRepository.queryIncompleteTasks()
    }

    // MARK: - Private

    private func processAgentRuntimeIfAvailable(
        task: VoiceTask,
        rawText: String,
        context: ContextSnapshot?,
        onAgentRuntimeStage: (@MainActor (AgentComposeHUDStage) -> Void)?,
        onAgentRuntimeCompleted: (@MainActor (String) -> Void)?
    ) async throws -> OutputResult? {
        guard let agentRuntimeService else { return nil }
        guard let selection = agentRuntimeSelection(),
              selection.usesCodexRuntime else {
            return nil
        }
        let availability = await agentRuntimeService.availability(forceRefresh: false)
        guard availability.isAvailable else {
            AppLogger.general.info(
                "agent_runtime_unavailable provider=\(selection.providerID) reason=\(availability.status.reason ?? "-") fallback=textOnly"
            )
            let now = clock.now
            let fallbackTrace = AgentActionTrace(
                providerID: selection.providerID,
                executionMode: .codexTextFallback,
                status: .completed,
                userInstruction: rawText,
                screenContext: screenContextSnapshot(context: context, target: taskTarget(task)),
                events: [
                    AgentActionEvent(
                        kind: .warning,
                        title: "Runtime 不可用",
                        detail: availability.status.reason,
                        timestamp: now,
                        elapsedMS: 0
                    )
                ],
                resultSummary: "已退回文本模式",
                model: selection.model,
                startedAt: now,
                completedAt: now
            )
            try? persistAgentActionTrace(taskID: task.id, trace: fallbackTrace)
            return nil
        }

        let taskID = task.id
        onAgentRuntimeStage?(.runtimeProcessing(summary: runtimeHUDSummary(from: rawText)))
        do {
            let serviceResult = try await agentRuntimeService.runIfAvailable(
                taskID: taskID,
                instruction: rawText,
                context: context,
                target: taskTarget(task),
                model: selection.model,
                onEvent: { event in
                    let stage = CodexEventNormalizer().hudStage(after: event)
                    Task { @MainActor in
                        onAgentRuntimeStage?(stage)
                    }
                }
            )
            switch serviceResult {
            case .unavailable:
                return nil
            case let .completed(result):
                guard isActiveWorkflow(kind: .agentCompose, taskID: taskID) else {
                    return .cancelled
                }
                try persistAgentActionTrace(taskID: taskID, trace: result.trace)
                var updatedTask = task
                let finalText = result.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !finalText.isEmpty {
                    try taskRepository.updateFinalText(id: taskID, finalText: finalText)
                    updatedTask.finalText = finalText
                }
                if let context, !context.warnings.isEmpty {
                    updatedTask.warnings.append(contentsOf: context.warnings)
                    try? taskRepository.updateWarnings(id: taskID, warnings: updatedTask.warnings)
                }
                let completedAt = clock.now
                updatedTask.stage = .outputting
                updatedTask.status = .completed
                updatedTask.completedAt = completedAt
                try taskRepository.updateStage(updatedTask)
                try taskRepository.complete(
                    id: taskID,
                    status: .completed,
                    outputResult: nil,
                    completedAt: completedAt
                )
                taskRuntime.clearCurrentTaskIfMatching(updatedTask)
                taskRuntime.clearWorkflow(for: updatedTask)
                saveAgentRuntimeVoiceAssetIfNeeded(
                    task: updatedTask,
                    rawText: rawText,
                    completedAt: completedAt
                )
                onAgentRuntimeStage?(.runtimeCompleted(summary: finalText))
                onAgentRuntimeCompleted?(taskID)
                AppLogger.general.info("voice_workflow_completed kind=agentCompose taskID=\(taskID) status=completed output=agentRuntime")
                return .cancelled
            }
        } catch AgentRuntimeClientError.failed(let trace) {
            try? persistAgentActionTrace(taskID: taskID, trace: trace)
            onAgentRuntimeStage?(.runtimeFailed(summary: trace.failureReason))
            throw CoordinatorError.llmCallFailed(trace.failureReason ?? "Codex runtime failed.")
        } catch AgentRuntimeError.cancelled {
            return .cancelled
        } catch {
            onAgentRuntimeStage?(.runtimeFailed(summary: error.localizedDescription))
            throw error
        }
    }

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

    private func screenContextSnapshot(
        context: ContextSnapshot?,
        target: DictationTarget?
    ) -> ScreenContextSnapshot? {
        guard context != nil || target != nil else { return nil }
        return ScreenContextSnapshot(
            thumbnailPath: nil,
            imagePath: nil,
            appName: context?.targetAppName ?? target?.appName,
            bundleID: context?.targetAppBundleID ?? target?.bundleID,
            windowTitle: context?.windowTitle ?? target?.windowTitle,
            capturedAt: clock.now
        )
    }

    private func task(for kind: VoiceWorkflowKind?) throws -> VoiceTask? {
        taskRuntime.task(for: kind)
    }

    private func saveVoiceTextAssetIfNeeded(
        task: VoiceTask,
        rawText: String,
        finalText: String,
        outputResult: OutputResult,
        completedAt: Date
    ) {
        if case .cancelled = outputResult { return }
        if case .copyFailed = outputResult { return }
        saveVoiceTextAssetIfNeeded(
            task: task,
            rawText: rawText,
            finalText: finalText,
            captureReason: dictationCaptureReason(for: outputResult),
            completedAt: completedAt
        )
    }

    private func saveAgentComposeVoiceAssetIfNeeded(
        task: VoiceTask,
        rawText: String,
        outputResult: OutputResult,
        completedAt: Date
    ) {
        if case .cancelled = outputResult { return }
        let transcript = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        saveRawVoiceTextAssetIfNeeded(
            task: task,
            rawText: rawText,
            captureReason: .dictationCompleted,
            completedAt: completedAt
        )
    }

    private func saveAgentRuntimeVoiceAssetIfNeeded(
        task: VoiceTask,
        rawText: String,
        completedAt: Date
    ) {
        let transcript = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        saveRawVoiceTextAssetIfNeeded(
            task: task,
            rawText: rawText,
            captureReason: .dictationCompleted,
            completedAt: completedAt
        )
    }

    private func saveRawVoiceTextAssetIfNeeded(
        task: VoiceTask,
        rawText: String,
        captureReason: AssetCaptureReason,
        completedAt: Date
    ) {
        saveVoiceTextAssetIfNeeded(
            task: task,
            rawText: rawText,
            finalText: rawText,
            captureReason: captureReason,
            completedAt: completedAt
        )
    }

    private func saveFailedVoiceAssetIfNeeded(task: VoiceTask, completedAt: Date) {
        guard task.mode == .agentCompose || task.mode == .agentDispatch,
              let rawText = task.rawTranscript,
              !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        saveVoiceTextAssetIfNeeded(
            task: task,
            rawText: rawText,
            finalText: rawText,
            captureReason: .dictationCompleted,
            completedAt: completedAt
        )
    }

    private func saveVoiceTextAssetIfNeeded(
        task: VoiceTask,
        rawText: String,
        finalText: String,
        captureReason: AssetCaptureReason,
        completedAt: Date
    ) {
        let storedText = finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? rawText
            : finalText
        guard let assetRepository else { return }

        let asset: AssetItem
        do {
            asset = try AssetItem.makeText(
                id: "dictation-\(task.id)",
                source: .dictation,
                title: assetTitle(from: storedText),
                text: storedText,
                rawText: rawText,
                previewText: storedText,
                contentHash: "dictation-\(task.id)",
                captureReason: captureReason,
                sourceAppName: task.targetAppName,
                sourceAppBundleID: task.targetAppBundleID,
                createdAt: completedAt,
                updatedAt: completedAt
            )
        } catch {
            AppLogger.general.error("voice_asset_validation_failed taskID=\(task.id) reason=\(error.localizedDescription)")
            return
        }
        do {
            try assetRepository.save(asset)
            AppLogger.general.debug("voice_asset_saved id=\(asset.id) taskID=\(task.id) reason=\(captureReason.rawValue)")
        } catch {
            AppLogger.general.error("Failed to save dictation asset: \(error.localizedDescription)")
        }
    }

    private func dictationCaptureReason(for outputResult: OutputResult) -> AssetCaptureReason {
        switch outputResult {
        case .injected:
            return .dictationCompleted
        case .copied, .targetChanged, .permissionDenied, .injectionFailed:
            return .fallbackCopied
        case .copyFailed, .cancelled:
            return .dictationCompleted
        }
    }

    private func agentDispatchCaptureReason(
        for presentation: AgentDispatchHUDPresentation
    ) -> AssetCaptureReason {
        if case .clipboardFallback = presentation {
            return .fallbackCopied
        }
        return .dictationCompleted
    }

    private func assetTitle(from text: String) -> String {
        let collapsed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? text
        guard collapsed.count > 80 else { return collapsed }
        return String(collapsed.prefix(80))
    }

    private func runtimeHUDSummary(from text: String, limit: Int = 32) -> String {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。.!！?？"))
        if trimmed.range(of: "ppt", options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return L10n.localize("hud.agent_compose.runtime_task_ppt", comment: "Runtime doing PPT")
        }
        guard !trimmed.isEmpty else {
            return L10n.localize("hud.agent_compose.runtime_operating_detail", comment: "Runtime operating detail")
        }
        let summary = trimmed.count > limit ? String(trimmed.prefix(limit)) + "..." : trimmed
        return L10n.format("hud.agent_compose.runtime_task_format", comment: "Runtime task summary", summary)
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

    private func isActiveWorkflow(kind: VoiceWorkflowKind, taskID: String) -> Bool {
        taskRuntime.isActiveWorkflow(kind: kind, taskID: taskID)
    }

    private func persistAgentTraceIfAvailable(taskID: String) throws {
        guard let trace = (agentRefiner as? RefinementTraceProviding)?.lastTrace else {
            return
        }
        try persistAgentTrace(taskID: taskID, trace: trace)
    }

    private func persistAgentTrace(taskID: String, trace: LLMRefinementTrace) throws {
        let processingTrace = TextProcessingTrace(
            llm: trace,
            agentAction: existingAgentActionTrace(taskID: taskID),
            agentDispatch: existingAgentDispatchTrace(taskID: taskID)
        )
        LLMDiagnosticCapture.shared.capture(taskID: taskID, trace: processingTrace)
        let data = try JSONEncoder().encode(processingTrace.safeForPersistence())
        guard let json = String(data: data, encoding: .utf8) else {
            return
        }
        try taskRepository.updateTrace(id: taskID, trace: json)
    }

    private func persistTextProcessingTrace(
        taskID: String,
        processingTrace: TextProcessingTrace?,
        outputResult: OutputResult
    ) throws {
        guard var processingTrace else {
            return
        }
        processingTrace.output = OutputDeliveryTrace(resultKind: outputResult.kind.rawValue)
        if processingTrace.agentAction == nil {
            processingTrace.agentAction = existingAgentActionTrace(taskID: taskID)
        }
        if processingTrace.agentDispatch == nil {
            processingTrace.agentDispatch = existingAgentDispatchTrace(taskID: taskID)
        }
        try persistProcessingTrace(taskID: taskID, trace: processingTrace)
    }

    private func persistAgentDispatchTrace(
        taskID: String,
        presentation: AgentDispatchHUDPresentation,
        processingTrace: TextProcessingTrace? = nil
    ) throws {
        var trace = processingTrace ?? existingProcessingTrace(taskID: taskID) ?? TextProcessingTrace()
        if trace.agentAction == nil {
            trace.agentAction = existingAgentActionTrace(taskID: taskID)
        }
        trace.agentDispatch = AgentDispatchTrace(presentation: presentation)
        try persistProcessingTrace(taskID: taskID, trace: trace)
    }

    private func persistAgentDispatchDefaultOutputTrace(
        taskID: String,
        processingTrace: TextProcessingTrace?,
        outputResult: OutputResult
    ) throws {
        var trace = processingTrace ?? existingProcessingTrace(taskID: taskID) ?? TextProcessingTrace()
        trace.output = OutputDeliveryTrace(resultKind: outputResult.kind.rawValue)
        trace.agentDispatch = AgentDispatchTrace(
            state: "fallbackInput",
            title: L10n.localize("home.detail.dispatch.default_output", comment: "Dispatch default output"),
            detail: L10n.localize("home.detail.dispatch.default_output_detail", comment: "Default output detail")
        )
        try persistProcessingTrace(taskID: taskID, trace: trace)
    }

    private func persistProcessingTrace(taskID: String, trace: TextProcessingTrace) throws {
        LLMDiagnosticCapture.shared.capture(taskID: taskID, trace: trace)
        let data = try JSONEncoder().encode(trace.safeForPersistence())
        guard let json = String(data: data, encoding: .utf8) else {
            return
        }
        try taskRepository.updateTrace(id: taskID, trace: json)
    }

    private func existingProcessingTrace(taskID: String) -> TextProcessingTrace? {
        guard let task = try? taskRepository.fetch(id: taskID),
              let traceJSON = task.trace,
              let data = traceJSON.data(using: .utf8),
              let trace = try? JSONDecoder().decode(TextProcessingTrace.self, from: data) else {
            return nil
        }
        return trace
    }

    private func existingAgentActionTrace(taskID: String) -> AgentActionTrace? {
        existingProcessingTrace(taskID: taskID)?.agentAction
    }

    private func existingAgentDispatchTrace(taskID: String) -> AgentDispatchTrace? {
        existingProcessingTrace(taskID: taskID)?.agentDispatch
    }

    private func persistAgentActionTrace(taskID: String, trace: AgentActionTrace) throws {
        let processingTrace = TextProcessingTrace(agentAction: trace)
        try persistProcessingTrace(taskID: taskID, trace: processingTrace)
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

private struct AgentDispatchTaskSnapshot: Encodable {
    let state: String
    let title: String
    let detail: String

    init(presentation: AgentDispatchHUDPresentation) {
        switch presentation {
        case .idle: state = "idle"
        case .listening: state = "listening"
        case .exact: state = "exact"
        case .confirmation: state = "confirmation"
        case .fallbackInput: state = "fallbackInput"
        case .clipboardFallback: state = "clipboardFallback"
        case .sent: state = "sent"
        case .failure: state = "failure"
        }
        title = presentation.title
        detail = presentation.detail
    }
}

private extension AgentDispatchTrace {
    init(presentation: AgentDispatchHUDPresentation) {
        switch presentation {
        case .idle:
            self.init(state: "idle", title: presentation.title, detail: presentation.detail)
        case .listening:
            self.init(state: "listening", title: presentation.title, detail: presentation.detail)
        case let .exact(agentName, message):
            self.init(state: "exact", title: presentation.title, detail: message, agentName: agentName)
        case .confirmation:
            self.init(state: "confirmation", title: presentation.title, detail: presentation.detail)
        case .fallbackInput:
            self.init(state: "fallbackInput", title: presentation.title, detail: presentation.detail)
        case .clipboardFallback:
            self.init(state: "clipboardFallback", title: presentation.title, detail: presentation.detail)
        case let .sent(agentName):
            self.init(state: "sent", title: presentation.title, detail: presentation.detail, agentName: agentName)
        case .failure:
            self.init(state: "failure", title: presentation.title, detail: presentation.detail)
        }
    }
}

@MainActor
private final class VoiceTaskRuntimeStore {
    private enum RuntimeEntry {
        case persisted(VoiceWorkflowLease, VoiceTask)
        case ephemeral(VoiceWorkflowLease, Task<Void, Never>?)

        var lease: VoiceWorkflowLease {
            switch self {
            case .persisted(let lease, _), .ephemeral(let lease, _):
                return lease
            }
        }

        var task: VoiceTask? {
            guard case .persisted(_, let task) = self else { return nil }
            return task
        }

        func updatingTask(_ task: VoiceTask) -> RuntimeEntry {
            switch self {
            case .persisted(let lease, _):
                return .persisted(lease, task)
            case .ephemeral:
                return self
            }
        }
    }

    private var entries: [VoiceWorkflowKind: RuntimeEntry] = [:]
    private var currentKind: VoiceWorkflowKind?

    var currentWorkflowKind: VoiceWorkflowKind? {
        guard let currentKind,
              entries[currentKind]?.task != nil else {
            return nil
        }
        return currentKind
    }

    var currentTask: VoiceTask? {
        guard let currentKind else { return nil }
        return entries[currentKind]?.task
    }

    var currentTaskID: String? {
        currentTask?.id
    }

    func activeTaskID(for kind: VoiceWorkflowKind) -> String? {
        entries[kind]?.lease.taskID
    }

    func lease(for kind: VoiceWorkflowKind) -> VoiceWorkflowLease? {
        entries[kind]?.lease
    }

    func beginEphemeralWorkflow(kind: VoiceWorkflowKind) throws -> VoiceWorkflowLease {
        guard entries[kind] == nil else {
            throw CoordinatorError.workflowAlreadyRunning(kind.rawValue)
        }
        let lease = VoiceWorkflowLease(
            kind: kind,
            taskID: "ephemeral-\(kind.rawValue)-\(UUID().uuidString)"
        )
        entries[kind] = .ephemeral(lease, nil)
        return lease
    }

    func completeEphemeralWorkflow(_ lease: VoiceWorkflowLease) -> Bool {
        guard case .ephemeral(let activeLease, _)? = entries[lease.kind],
              activeLease == lease else {
            return false
        }
        entries.removeValue(forKey: lease.kind)
        return true
    }

    func registerEphemeralWorkflowTask(_ task: Task<Void, Never>, for lease: VoiceWorkflowLease) {
        guard case .ephemeral(let activeLease, _)? = entries[lease.kind],
              activeLease == lease else {
            return
        }
        entries[lease.kind] = .ephemeral(lease, task)
    }

    func cancelEphemeralWorkflow(kind: VoiceWorkflowKind) -> VoiceWorkflowLease? {
        guard case .ephemeral(let lease, let task)? = entries[kind] else {
            return nil
        }
        task?.cancel()
        entries.removeValue(forKey: kind)
        return lease
    }

    func isWorkflowLeaseActive(_ lease: VoiceWorkflowLease) -> Bool {
        entries[lease.kind]?.lease == lease
    }

    func beginPersistedWorkflow(_ task: VoiceTask, kind: VoiceWorkflowKind) throws {
        guard entries[kind] == nil else {
            throw CoordinatorError.workflowAlreadyRunning(kind.rawValue)
        }
        let lease = VoiceWorkflowLease(kind: kind, taskID: task.id)
        entries[kind] = .persisted(lease, task)
        currentKind = kind
    }

    func task(for kind: VoiceWorkflowKind?) -> VoiceTask? {
        guard let kind else { return currentTask }
        return entries[kind]?.task
    }

    func updatePersistedTask(_ task: VoiceTask) {
        guard let kind = kind(forTaskID: task.id),
              let entry = entries[kind] else {
            return
        }
        entries[kind] = entry.updatingTask(task)
        if currentKind == nil {
            currentKind = kind
        }
    }

    func clearCurrentTaskIfMatching(_ task: VoiceTask) {
        guard currentTask?.id == task.id else { return }
        currentKind = nil
    }

    func clearWorkflow(for task: VoiceTask) {
        clearWorkflow(kind: VoiceWorkflowKind(mode: task.mode), taskID: task.id)
    }

    func clearWorkflow(kind: VoiceWorkflowKind, taskID: String) {
        guard entries[kind]?.lease.taskID == taskID else { return }
        entries.removeValue(forKey: kind)
        if currentKind == kind {
            currentKind = nil
        }
    }

    func isActiveWorkflow(kind: VoiceWorkflowKind, taskID: String) -> Bool {
        entries[kind]?.lease.taskID == taskID
    }

    private func kind(forTaskID taskID: String) -> VoiceWorkflowKind? {
        entries.first { _, entry in
            entry.lease.taskID == taskID
        }?.key
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
            return String(
                L10n.localize("dictation.coordinator.no_active_task", comment: "No active dictation task message")
            )
        case .invalidMode:
            return String(
                L10n.localize("dictation.coordinator.invalid_mode", comment: "Invalid mode for operation message")
            )
        case .llmNotConfigured:
            return String(
                L10n.localize("dictation.coordinator.llm_not_configured", comment: "LLM not configured message")
            )
        case .llmCallFailed(let reason):
            return L10n.format("dictation.coordinator.llm_call_failed_format", comment: "LLM call failed with reason",
                reason
            )
        case .workflowAlreadyRunning(let kind):
            return L10n.format("dictation.coordinator.workflow_already_running_format", comment: "Workflow already running message",
                kind
            )
        }
    }
}
