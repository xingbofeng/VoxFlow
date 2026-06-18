import AVFoundation
import Foundation
import VoxFlowTextInsertion

protocol AudioRecording: AnyObject {
    var isRecording: Bool { get }
    func start() throws
    func stop()
    func drain()
}

extension AudioRecorder: AudioRecording {}

struct DictationConfiguration: Equatable {
    let engineType: ASREngineType
    let locale: Locale
    let languageIdentifier: String
    let asrProviderID: String
    let modelID: String?
    let modelVersion: String?

    init(
        engineType: ASREngineType,
        locale: Locale,
        languageIdentifier: String,
        asrProviderID: String? = nil,
        modelID: String? = nil,
        modelVersion: String? = nil
    ) {
        self.engineType = engineType
        self.locale = locale
        self.languageIdentifier = languageIdentifier
        self.asrProviderID = asrProviderID ?? engineType.providerID
        self.modelID = modelID
        self.modelVersion = modelVersion
    }
}

@MainActor
final class DictationOrchestrator {
    var onStateChange: (DictationState) -> Void = { _ in }
    var onTranscriptionUpdate: (String, Bool) -> Void = { _, _ in }
    var onProcessingStarted: (String) -> Void = { _ in }
    var onHistorySaved: () -> Void = {}
    var onAgentComposeCompleted: (OutputResult) -> Void = { _ in }
    var onError: (Error) -> Void = { _ in }

    private let asrEngineFactory: any ASREngineFactory
    private let audioRecorder: any AudioRecording
    private nonisolated let audioBufferForwarder: any ASREngineAudioFrameForwarding
    private let textPipeline: any TextProcessing
    private let outputService: any OutputService
    private let historyRepository: any HistoryRepository
    private let clock: any AppClock
    private let targetProvider: any DictationTargetProviding
    private let agentComposeHandler: (any AgentComposeHandling)?
    private let finalTimeoutNanoseconds: UInt64
    private var stateMachine = DictationStateMachine()
    private var transcriptionSession = TranscriptionSession()
    private var currentEngine: ASREngine?
    private var currentConfiguration: DictationConfiguration?
    private var currentTarget: DictationTarget?
    private var currentMode: VoiceTaskMode = .dictation
    private var startedAt: Date?
    private var finalTimeoutTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var recognizedTextAwaitingProcessing: String?

    var state: DictationState {
        stateMachine.state
    }

    init(
        asrEngineFactory: any ASREngineFactory,
        audioRecorder: any AudioRecording,
        audioBufferForwarder: any ASREngineAudioFrameForwarding = ASREngineAudioFrameForwarder(),
        textPipeline: any TextProcessing,
        textInjector: any TextInserting,
        historyRepository: any HistoryRepository,
        clock: any AppClock = SystemClock(),
        targetProvider: any DictationTargetProviding = WorkspaceDictationTargetProvider(),
        clipboardService: any ClipboardSetting = SystemClipboardService(),
        outputService: (any OutputService)? = nil,
        agentComposeHandler: (any AgentComposeHandling)? = nil,
        finalTimeoutNanoseconds: UInt64 = 15_000_000_000
    ) {
        self.asrEngineFactory = asrEngineFactory
        self.audioRecorder = audioRecorder
        self.audioBufferForwarder = audioBufferForwarder
        self.textPipeline = textPipeline
        self.outputService = outputService ?? DefaultOutputService(
            textInjector: textInjector,
            clipboardService: clipboardService
        )
        self.historyRepository = historyRepository
        self.clock = clock
        self.targetProvider = targetProvider
        self.agentComposeHandler = agentComposeHandler
        self.finalTimeoutNanoseconds = finalTimeoutNanoseconds
    }

    func start(
        configuration: DictationConfiguration,
        mode: VoiceTaskMode = .dictation
    ) throws {
        guard RecognitionLanguage.supportsIdentifier(configuration.languageIdentifier),
              RecognitionLanguage.supportsIdentifier(configuration.locale.identifier) else {
            throw DictationOrchestratorError.unsupportedLanguage(configuration.languageIdentifier)
        }

        guard stateMachine.startRecording() else {
            throw DictationOrchestratorError.alreadyRunning
        }

        transcriptionSession = TranscriptionSession()
        currentConfiguration = configuration
        currentTarget = targetProvider.currentTarget()
        currentMode = mode
        startedAt = clock.now
        finalTimeoutTask?.cancel()
        finalTimeoutTask = nil
        processingTask?.cancel()
        processingTask = nil
        recognizedTextAwaitingProcessing = nil

        if mode == .agentCompose {
            guard let agentComposeHandler else {
                stateMachine.reset()
                currentMode = .dictation
                throw DictationOrchestratorError.agentComposeUnavailable
            }
            do {
                try agentComposeHandler.start(
                    target: currentTarget,
                    asrMetadata: asrMetadata(for: configuration)
                )
            } catch {
                stateMachine.reset()
                currentMode = .dictation
                throw error
            }
        }

        let engine = asrEngineFactory.makeEngine(type: configuration.engineType)
        currentEngine = engine
        audioBufferForwarder.attach(engine)
        engine.configure(locale: configuration.locale)
        engine.onTranscription = { [weak self] text, isFinal in
            Task { @MainActor [weak self] in
                self?.handleTranscription(text: text, isFinal: isFinal)
            }
        }
        engine.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                await self?.handleRecognitionError(error)
            }
        }

        do {
            try engine.start()
            try audioRecorder.start()
            notifyStateChanged()
        } catch {
            audioRecorder.stop()
            engine.cancel()
            audioBufferForwarder.detach()
            currentEngine = nil
            if mode == .agentCompose {
                agentComposeHandler?.cancel()
            }
            currentMode = .dictation
            stateMachine.reset()
            notifyStateChanged()
            throw error
        }
    }

    func release() {
        guard state == .recording else {
            return
        }

        audioRecorder.stop()
        audioRecorder.drain()
        audioBufferForwarder.finish()
        currentEngine?.endAudio()

        if let completedText = transcriptionSession.release() {
            scheduleProcessing(for: completedText)
            return
        }

        guard stateMachine.waitForFinalResult() else {
            return
        }
        notifyStateChanged()
        scheduleFinalTimeout()
    }

    nonisolated func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        audioBufferForwarder.appendAudioBuffer(buffer)
    }

    func cancel() {
        guard state.isCancellable else {
            return
        }
        finalTimeoutTask?.cancel()
        finalTimeoutTask = nil
        processingTask?.cancel()
        processingTask = nil
        recognizedTextAwaitingProcessing = nil
        audioRecorder.stop()
        currentEngine?.cancel()
        audioBufferForwarder.detach()
        if currentMode == .agentCompose {
            agentComposeHandler?.cancel()
        }
        currentEngine = nil
        transcriptionSession = TranscriptionSession()
        currentTarget = nil
        currentMode = .dictation
        stateMachine.finish()
        notifyStateChanged()
    }

    func finishWithoutTextCorrection() {
        guard state == .processing,
              currentMode == .dictation,
              let rawText = recognizedTextAwaitingProcessing,
              !rawText.isEmpty else {
            cancel()
            return
        }

        processingTask?.cancel()
        processingTask = nil
        let target = currentTarget
        let processingResult = TextProcessingResult(
            rawText: rawText,
            finalText: rawText,
            warnings: ["llm_refinement_cancelled_by_user"]
        )

        guard stateMachine.startInjecting() else {
            return
        }
        notifyStateChanged()
        processingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await deliverFinalText(rawText, originalTarget: target)
            guard !Task.isCancelled, state == .injecting else { return }
            saveHistory(
                rawText: rawText,
                finalText: rawText,
                target: target,
                processingResult: processingResult
            )
            finishCurrentDictation()
        }
    }

    private func handleTranscription(text: String, isFinal: Bool) {
        guard state.isRecordingActive else {
            return
        }
        onTranscriptionUpdate(text, false)
        if let completedText = transcriptionSession.update(text: text, isFinal: isFinal) {
            scheduleProcessing(for: completedText)
        }
    }

    private func scheduleProcessing(for recognizedText: String) {
        processingTask?.cancel()
        recognizedTextAwaitingProcessing = recognizedText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        processingTask = Task { @MainActor [weak self] in
            await self?.finishRecognizedText(recognizedText)
        }
    }

    private func scheduleFinalTimeout() {
        finalTimeoutTask?.cancel()
        finalTimeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await clock.sleep(nanoseconds: finalTimeoutNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await handleFinalTimeout()
        }
    }

    private func handleFinalTimeout() async {
        guard state.isRecordingActive else {
            return
        }

        if let partialText = transcriptionSession.timeout(),
           !partialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scheduleProcessing(for: partialText)
            return
        }

        fail(DictationOrchestratorError.finalResultTimedOut)
    }

    private func handleRecognitionError(_ error: Error) async {
        guard state.isRecordingActive else {
            return
        }

        if let partialText = transcriptionSession.fallbackToLatestText(),
           !partialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scheduleProcessing(for: partialText)
            return
        }

        fail(error)
    }

    private func finishRecognizedText(_ recognizedText: String) async {
        guard !Task.isCancelled, state.isRecordingActive else {
            return
        }

        finalTimeoutTask?.cancel()
        finalTimeoutTask = nil
        audioRecorder.stop()
        currentEngine?.stop()

        let rawText = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            if currentMode == .agentCompose {
                agentComposeHandler?.cancel()
            }
            audioBufferForwarder.detach()
            currentEngine = nil
            currentTarget = nil
            currentMode = .dictation
            stateMachine.finish()
            notifyStateChanged()
            return
        }

        guard stateMachine.startProcessing() else {
            return
        }
        notifyStateChanged()
        onProcessingStarted(rawText)

        if currentMode == .agentCompose {
            await finishAgentCompose(rawText)
            return
        }

        let target = currentTarget
        let processingResult = await textPipeline.process(
            rawText,
            target: target,
            onRefinedTextUpdate: { [weak self] text in
                self?.onTranscriptionUpdate(text, true)
            }
        )
        guard !Task.isCancelled, state == .processing else {
            return
        }
        let finalText = normalizedFinalText(from: processingResult, fallback: rawText)

        guard stateMachine.startInjecting() else {
            return
        }
        notifyStateChanged()
        await deliverFinalText(finalText, originalTarget: target)

        saveHistory(rawText: rawText, finalText: finalText, target: target, processingResult: processingResult)

        finishCurrentDictation()
    }

    private func finishAgentCompose(_ rawText: String) async {
        guard let agentComposeHandler else {
            fail(DictationOrchestratorError.agentComposeUnavailable)
            return
        }

        onTranscriptionUpdate("正在结合上下文生成...", true)
        do {
            updateAgentComposeASRMetadataIfAvailable()
            let result = try await agentComposeHandler.finish(rawTranscript: rawText)
            guard !Task.isCancelled, state == .processing else {
                return
            }
            guard stateMachine.startInjecting() else {
                return
            }
            notifyStateChanged()
            audioBufferForwarder.detach()
            currentEngine = nil
            currentTarget = nil
            currentMode = .dictation
            stateMachine.finish()
            notifyStateChanged()
            onAgentComposeCompleted(result)
        } catch {
            guard !Task.isCancelled, state == .processing else {
                return
            }
            fail(error)
        }
    }

    private func normalizedFinalText(from result: TextProcessingResult, fallback: String) -> String {
        let trimmed = result.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func finishCurrentDictation() {
        audioBufferForwarder.detach()
        currentEngine = nil
        currentTarget = nil
        currentMode = .dictation
        recognizedTextAwaitingProcessing = nil
        processingTask = nil
        stateMachine.finish()
        notifyStateChanged()
    }

    private func deliverFinalText(_ text: String, originalTarget: DictationTarget?) async {
        let currentTarget = targetProvider.currentTarget()
        _ = await outputService.deliver(
            text: text,
            mode: .dictation,
            target: currentTarget,
            originalTarget: originalTarget
        )
    }

    private func saveHistory(
        rawText: String,
        finalText: String,
        target: DictationTarget?,
        processingResult: TextProcessingResult
    ) {
        guard let configuration = currentConfiguration else {
            return
        }

        let finishedAt = clock.now
        let startedAt = startedAt ?? finishedAt
        let durationMS = max(0, Int(finishedAt.timeIntervalSince(startedAt) * 1000))
        let charCount = finalText.count
        let durationMinutes = max(Double(durationMS) / 60_000.0, 1.0 / 60_000.0)

        let entry = DictationHistoryEntry(
            id: UUID().uuidString,
            rawText: rawText,
            finalText: finalText,
            language: configuration.languageIdentifier,
            asrProviderID: configuration.asrProviderID,
            llmProviderID: processingResult.llmProviderID,
            styleID: processingResult.styleID,
            durationMS: durationMS,
            charCount: charCount,
            cpm: Double(charCount) / durationMinutes,
            targetAppBundleID: target?.bundleID,
            targetAppName: target?.appName,
            processingWarningsJSON: warningsJSON(processingResult.warnings),
            processingTraceJSON: traceJSON(processingResult.trace),
            createdAt: finishedAt,
            updatedAt: finishedAt,
            deletedAt: nil
        )

        do {
            try historyRepository.save(entry)
            onHistorySaved()
        } catch {
            AppLogger.general.error("Failed to save dictation history: \(error.localizedDescription)")
        }
    }

    private func warningsJSON(_ warnings: [String]) -> String? {
        guard !warnings.isEmpty,
              let data = try? JSONEncoder().encode(warnings) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func traceJSON(_ trace: TextProcessingTrace?) -> String? {
        guard let trace,
              let data = try? JSONEncoder().encode(trace) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func asrMetadata(for configuration: DictationConfiguration) -> VoiceTaskASRMetadata {
        VoiceTaskASRMetadata(
            providerID: configuration.asrProviderID,
            modelID: configuration.modelID ?? configuration.engineType.rawValue,
            modelVersion: configuration.modelVersion,
            language: configuration.languageIdentifier
        )
    }

    private func asrMetadata(
        for configuration: DictationConfiguration,
        runtimeSnapshot: ASRRuntimeMetadataSnapshot?
    ) -> VoiceTaskASRMetadata {
        var metadata = asrMetadata(for: configuration)
        metadata.sessionID = runtimeSnapshot?.sessionID
        metadata.audioDurationMs = runtimeSnapshot?.audioDurationMs
        metadata.finalLatencyMs = runtimeSnapshot?.finalLatencyMs
        metadata.droppedFrameCount = runtimeSnapshot?.droppedFrameCount
        metadata.errorCode = runtimeSnapshot?.errorCode
        return metadata
    }

    private func updateAgentComposeASRMetadataIfAvailable() {
        guard currentMode == .agentCompose,
              let configuration = currentConfiguration,
              let agentComposeHandler else {
            return
        }
        let runtimeSnapshot = (currentEngine as? ASRRuntimeMetadataProviding)?.asrRuntimeMetadataSnapshot
        do {
            try agentComposeHandler.updateASRMetadata(
                asrMetadata(for: configuration, runtimeSnapshot: runtimeSnapshot)
            )
        } catch {
            AppLogger.general.error("Failed to update ASR metadata: \(error.localizedDescription)")
        }
    }

    private func fail(_ error: Error) {
        finalTimeoutTask?.cancel()
        finalTimeoutTask = nil
        processingTask?.cancel()
        processingTask = nil
        recognizedTextAwaitingProcessing = nil
        audioRecorder.stop()
        updateAgentComposeASRMetadataIfAvailable()
        currentEngine?.cancel()
        audioBufferForwarder.detach()
        if currentMode == .agentCompose {
            agentComposeHandler?.fail(error)
        }
        currentEngine = nil
        currentTarget = nil
        currentMode = .dictation
        stateMachine.fail(message: error.localizedDescription)
        notifyStateChanged()
        onError(error)
        stateMachine.finish()
        notifyStateChanged()
    }

    private func notifyStateChanged() {
        onStateChange(state)
    }
}

enum DictationOrchestratorError: LocalizedError, Equatable {
    case alreadyRunning
    case agentComposeUnavailable
    case finalResultTimedOut
    case unsupportedLanguage(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "听写正在进行中。"
        case .agentComposeUnavailable:
            return "帮我说尚未完成初始化，请重启随声写后重试。"
        case .finalResultTimedOut:
            return "语音识别超时，请重试。"
        case .unsupportedLanguage(let identifier):
            return "当前语音识别语言不受支持：\(identifier)。"
        }
    }
}

extension ASREngineType {
    var providerID: String {
        switch self {
        case .apple:
            return ASRProviderID.appleSpeech
        case .funASR:
            return ASRProviderID.funASR
        case .whisper:
            return ASRProviderID.whisper
        case .qwen3:
            return ASRProviderID.qwen3
        case .senseVoice:
            return ASRProviderID.senseVoice
        case .paraformer:
            return ASRProviderID.paraformer
        case .nvidiaNemotron:
            return ASRProviderID.nvidiaNemotron
        }
    }
}
