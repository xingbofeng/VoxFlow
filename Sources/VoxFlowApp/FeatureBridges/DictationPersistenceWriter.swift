import Foundation

@MainActor
final class DictationPersistenceWriter {
    private let taskRepository: VoiceTaskRepository
    private let assetRepository: (any AssetRepository)?
    private let agentTraceProvider: @MainActor () -> LLMRefinementTrace?

    init(
        taskRepository: VoiceTaskRepository,
        assetRepository: (any AssetRepository)?,
        agentTraceProvider: @escaping @MainActor () -> LLMRefinementTrace? = { nil }
    ) {
        self.taskRepository = taskRepository
        self.assetRepository = assetRepository
        self.agentTraceProvider = agentTraceProvider
    }

    func saveVoiceTextAssetIfNeeded(
        task: VoiceTask,
        rawText: String,
        finalText: String,
        outputResult: OutputResult,
        completedAt: Date
    ) {
        if case .cancelled = outputResult { return }
        if case .copyFailed = outputResult { return }
        saveVoiceTextAsset(
            task: task,
            rawText: rawText,
            finalText: finalText,
            captureReason: Self.dictationCaptureReason(for: outputResult),
            completedAt: completedAt
        )
    }

    func saveAgentComposeVoiceAssetIfNeeded(
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

    func saveAgentRuntimeVoiceAssetIfNeeded(
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

    func saveRawVoiceTextAssetIfNeeded(
        task: VoiceTask,
        rawText: String,
        captureReason: AssetCaptureReason,
        completedAt: Date
    ) {
        saveVoiceTextAsset(
            task: task,
            rawText: rawText,
            finalText: rawText,
            captureReason: captureReason,
            completedAt: completedAt
        )
    }

    func saveFailedVoiceAssetIfNeeded(task: VoiceTask, completedAt: Date) {
        guard task.mode == .agentCompose || task.mode == .agentDispatch,
              let rawText = task.rawTranscript,
              !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        saveVoiceTextAsset(
            task: task,
            rawText: rawText,
            finalText: rawText,
            captureReason: .dictationCompleted,
            completedAt: completedAt
        )
    }

    func persistAgentTraceIfAvailable(taskID: String) throws {
        guard let trace = agentTraceProvider() else {
            return
        }
        try persistAgentTrace(taskID: taskID, trace: trace)
    }

    func persistAgentTrace(taskID: String, trace: LLMRefinementTrace) throws {
        let processingTrace = TextProcessingTrace(
            llm: trace,
            agentAction: existingAgentActionTrace(taskID: taskID),
            agentDispatch: existingAgentDispatchTrace(taskID: taskID)
        )
        try persistProcessingTrace(taskID: taskID, trace: processingTrace)
    }

    func persistTextProcessingTrace(
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

    func persistAgentDispatchTrace(
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

    func persistAgentDispatchDefaultOutputTrace(
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

    func persistAgentActionTrace(taskID: String, trace: AgentActionTrace) throws {
        let processingTrace = TextProcessingTrace(agentAction: trace)
        try persistProcessingTrace(taskID: taskID, trace: processingTrace)
    }

    func agentDispatchCaptureReason(
        for presentation: AgentDispatchHUDPresentation
    ) -> AssetCaptureReason {
        if case .clipboardFallback = presentation {
            return .fallbackCopied
        }
        return .dictationCompleted
    }

    func saveVoiceTextAsset(
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

    static func dictationCaptureReason(for outputResult: OutputResult) -> AssetCaptureReason {
        switch outputResult {
        case .injected:
            return .dictationCompleted
        case .copied, .targetChanged, .permissionDenied, .injectionFailed:
            return .fallbackCopied
        case .copyFailed, .handledExternally, .cancelled:
            return .dictationCompleted
        }
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
