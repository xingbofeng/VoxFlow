import AVFoundation
import Foundation
import VoxFlowTextInsertion
import VoxFlowVoiceCorrection

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
    private static let coldLocalModelFinalTimeoutNanoseconds: UInt64 = 120_000_000_000

    var onStateChange: (DictationState) -> Void = { _ in }
    var onTranscriptionUpdate: (String, Bool) -> Void = { _, _ in }
    var onProcessingStarted: (String) -> Void = { _ in }
    var onHistorySaved: () -> Void = {}
    var onAgentComposeCompleted: (OutputResult) -> Void = { _ in }
    var onAgentDispatchPresentation: (AgentDispatchHUDPresentation) -> Void = { _ in }
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
    private let agentDispatchHandler: (any AgentDispatchHandling)?
    private let audioCaptureCoordinator: any AudioCaptureCoordinating
    private let correctionObservationScheduler: (any CorrectionObservationScheduling)?
    private let isFocusedTextFieldSecure: @MainActor () -> Bool
    private let assetRepository: (any AssetRepository)?
    private let finalTimeoutNanoseconds: UInt64
    private var stateMachine = DictationStateMachine()
    private var transcriptionSession = TranscriptionSession()
    private var currentEngine: ASREngine?
    private var currentCallbackSessionID: String?
    private var currentConfiguration: DictationConfiguration?
    private var currentTarget: DictationTarget?
    private var currentMode: VoiceTaskMode = .dictation
    private var startedAt: Date?
    private var finalTimeoutTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    private var recognizedTextAwaitingProcessing: String?
    private var agentDispatchFallbackInputAwaitingCorrection: String?
    private var audioCaptureLease: AudioCaptureLease?

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
        clipboardService: any ClipboardSetting = DictationOrchestrator.defaultClipboardService,
        outputService: (any OutputService)? = nil,
        agentComposeHandler: (any AgentComposeHandling)? = nil,
        agentDispatchHandler: (any AgentDispatchHandling)? = nil,
        audioCaptureCoordinator: any AudioCaptureCoordinating = AudioCaptureCoordinator(),
        correctionObservationScheduler: (any CorrectionObservationScheduling)? = nil,
        isFocusedTextFieldSecure: @escaping @MainActor () -> Bool = { false },
        finalTimeoutNanoseconds: UInt64 = 15_000_000_000,
        assetRepository: (any AssetRepository)? = nil
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
        self.agentDispatchHandler = agentDispatchHandler
        self.audioCaptureCoordinator = audioCaptureCoordinator
        self.correctionObservationScheduler = correctionObservationScheduler
        self.isFocusedTextFieldSecure = isFocusedTextFieldSecure
        self.assetRepository = assetRepository
        self.finalTimeoutNanoseconds = finalTimeoutNanoseconds
    }

    private static var defaultClipboardService: any ClipboardSetting {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return TestClipboardService()
        }
        return SystemClipboardService()
    }

    func start(
        configuration: DictationConfiguration,
        mode: VoiceTaskMode = .dictation
    ) throws {
        AppLogger.dictation.info(
            "Dictation start requested: mode=\(mode.rawValue), engine=\(configuration.engineType.rawValue), lang=\(configuration.languageIdentifier), hasModelID=\(configuration.modelID != nil)"
        )
        guard RecognitionLanguage.supportsIdentifier(configuration.languageIdentifier),
              RecognitionLanguage.supportsIdentifier(configuration.locale.identifier) else {
            AppLogger.dictation.warning("Dictation start rejected: unsupported language \(configuration.languageIdentifier)")
            throw DictationOrchestratorError.unsupportedLanguage(configuration.languageIdentifier)
        }

        if mode == .agentCompose, agentComposeHandler == nil {
            AppLogger.dictation.warning("Dictation start rejected: agentCompose handler unavailable")
            throw DictationOrchestratorError.agentComposeUnavailable
        }
        if mode == .agentDispatch, agentDispatchHandler == nil {
            AppLogger.dictation.warning("Dictation start rejected: agentDispatch handler unavailable")
            throw DictationOrchestratorError.agentDispatchUnavailable
        }

        let lease = try audioCaptureCoordinator.begin(kind: audioCaptureKind(for: mode))
        guard stateMachine.startRecording() else {
            audioCaptureCoordinator.end(lease)
            AppLogger.dictation.warning("Dictation start rejected: state=\(stateLogName(stateMachine.state))")
            throw DictationOrchestratorError.alreadyRunning
        }
        audioCaptureLease = lease
        AppLogger.dictation.debug("Dictation session lease acquired: kind=\(audioCaptureKind(for: mode).rawValue)")

        transcriptionSession = TranscriptionSession()
        let callbackSessionID = UUID().uuidString
        AppLogger.dictation.debug("Dictation session initialized id=\(callbackSessionID)")
        currentCallbackSessionID = callbackSessionID
        currentConfiguration = configuration
        currentTarget = nil
        currentMode = mode
        startedAt = clock.now
        finalTimeoutTask?.cancel()
        finalTimeoutTask = nil
        processingTask?.cancel()
        processingTask = nil
        recognizedTextAwaitingProcessing = nil

        notifyStateChanged()

        currentTarget = targetProvider.currentTarget()

        if mode == .dictation,
           !isFocusedTextFieldSecure() {
            textPipeline.prepareContextBoost(target: currentTarget)
        }
        AppLogger.dictation.debug("Dictation target resolved: \(currentTarget?.bundleID ?? "nil")")

        if mode == .agentCompose {
            guard let agentComposeHandler else {
                stateMachine.reset()
                currentMode = .dictation
                endCurrentAudioCapture()
                notifyStateChanged()
                throw DictationOrchestratorError.agentComposeUnavailable
            }
            do {
                AppLogger.dictation.debug("Dictation start: preparing agentCompose handler")
                try agentComposeHandler.start(
                    target: currentTarget,
                    asrMetadata: asrMetadata(for: configuration)
                )
            } catch {
                AppLogger.dictation.error("Start agentCompose handler failed: \(error.localizedDescription)")
                stateMachine.reset()
                currentMode = .dictation
                endCurrentAudioCapture()
                notifyStateChanged()
                throw error
            }
        } else if mode == .agentDispatch {
            guard let agentDispatchHandler else {
                stateMachine.reset()
                currentMode = .dictation
                endCurrentAudioCapture()
                notifyStateChanged()
                throw DictationOrchestratorError.agentDispatchUnavailable
            }
            do {
                AppLogger.dictation.debug("Dictation start: preparing agentDispatch handler")
                agentDispatchHandler.onPresentationChange = { [weak self] presentation in
                    self?.onAgentDispatchPresentation(presentation)
                }
                try agentDispatchHandler.start(
                    target: currentTarget,
                    asrMetadata: asrMetadata(for: configuration)
                )
            } catch {
                AppLogger.dictation.error("Start agentDispatch handler failed: \(error.localizedDescription)")
                stateMachine.reset()
                currentMode = .dictation
                endCurrentAudioCapture()
                notifyStateChanged()
                throw error
            }
        }

        let engine = asrEngineFactory.makeEngine(type: configuration.engineType)
        currentEngine = engine
        audioBufferForwarder.attach(engine)
        engine.configure(locale: configuration.locale)
        engine.onTranscription = { [weak self] text, isFinal in
            Task { @MainActor [weak self] in
                self?.handleTranscription(
                    text: text,
                    isFinal: isFinal,
                    callbackSessionID: callbackSessionID
                )
            }
        }
        engine.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                await self?.handleRecognitionError(error, callbackSessionID: callbackSessionID)
            }
        }

        do {
            try engine.start()
            try audioRecorder.start()
            AppLogger.dictation.info("Dictation engine started: \(configuration.engineType.rawValue)")
        } catch {
            textPipeline.cancelContextBoost()
            audioRecorder.stop()
            engine.cancel()
            audioBufferForwarder.detach()
            currentEngine = nil
            currentCallbackSessionID = nil
            if mode == .agentCompose {
                agentComposeHandler?.cancel()
            } else if mode == .agentDispatch {
                agentDispatchHandler?.cancel()
            }
            currentMode = .dictation
            stateMachine.reset()
            endCurrentAudioCapture()
            notifyStateChanged()
            AppLogger.dictation.error("Dictation startup failed: \(error.localizedDescription)")
            throw error
        }
    }

    func release() {
        guard state == .recording else {
            AppLogger.dictation.debug("release ignored: state=\(stateLogName(state))")
            return
        }
        AppLogger.dictation.debug("release called in state=\(stateLogName(state))")

        audioRecorder.stop()
        audioRecorder.drain()
        endCurrentAudioCapture()
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
        AppLogger.dictation.debug("release entered waitingForFinal and scheduled timeout")
        scheduleFinalTimeout()
    }

    nonisolated func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        audioBufferForwarder.appendAudioBuffer(buffer)
    }

    func cancel() {
        AppLogger.dictation.info("cancel called state=\(stateLogName(state)) mode=\(currentMode.rawValue)")
        guard state.isCancellable else {
            return
        }
        finalTimeoutTask?.cancel()
        finalTimeoutTask = nil
        processingTask?.cancel()
        processingTask = nil
        recognizedTextAwaitingProcessing = nil
        agentDispatchFallbackInputAwaitingCorrection = nil
        textPipeline.cancelContextBoost()
        audioRecorder.stop()
        endCurrentAudioCapture()
        currentEngine?.cancel()
        audioBufferForwarder.detach()
        if currentMode == .agentCompose {
            agentComposeHandler?.cancel()
        } else if currentMode == .agentDispatch {
            agentDispatchHandler?.cancel()
        }
        currentEngine = nil
        currentCallbackSessionID = nil
        transcriptionSession = TranscriptionSession()
        currentTarget = nil
        currentMode = .dictation
        stateMachine.finish()
        notifyStateChanged()
    }

    @discardableResult
    func handleEscapeKey() -> Bool {
        AppLogger.dictation.debug("handleEscapeKey pressed state=\(stateLogName(state))")
        switch state {
        case .processing:
            if agentDispatchFallbackInputAwaitingCorrection != nil {
                return finishAgentDispatchFallbackInputWithoutTextCorrection()
            }
            return finishWithoutTextCorrection()
        case .waitingForFinal:
            return finishWaitingForFinalWithoutTextCorrection()
        default:
            cancel()
            return false
        }
    }

    private func finishWaitingForFinalWithoutTextCorrection() -> Bool {
        guard currentMode == .dictation,
              let rawText = transcriptionSession.fallbackToLatestText()?.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ),
              !rawText.isEmpty else {
            AppLogger.dictation.warning("finishWaitingForFinalWithoutTextCorrection aborted: no fallback text")
            cancel()
            return false
        }

        finalTimeoutTask?.cancel()
        finalTimeoutTask = nil
        audioRecorder.stop()
        endCurrentAudioCapture()
        currentEngine?.stop()
        recognizedTextAwaitingProcessing = rawText

        guard stateMachine.startProcessing() else {
            AppLogger.dictation.warning("finishWaitingForFinalWithoutTextCorrection blocked: stateMachine startProcessing failed")
            cancel()
            return false
        }
        notifyStateChanged()
        onProcessingStarted(rawText)
        return finishWithoutTextCorrection()
    }

    @discardableResult
    func finishWithoutTextCorrection() -> Bool {
        guard state == .processing,
              currentMode == .dictation,
              let rawText = recognizedTextAwaitingProcessing,
              !rawText.isEmpty else {
            AppLogger.dictation.warning("finishWithoutTextCorrection aborted: invalid state or empty text")
            cancel()
            return false
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
            AppLogger.dictation.warning("finishWithoutTextCorrection blocked: startInjecting failed")
            return false
        }
        notifyStateChanged()
        let sessionID = currentCallbackSessionID
        processingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let outputResult = await deliverFinalText(
                rawText,
                originalTarget: target,
                sessionID: sessionID
            )
            guard !Task.isCancelled,
                  isCurrentSession(sessionID),
                  state == .injecting else { return }
            if case .cancelled = outputResult {
                finishCurrentDictation()
                return
            }
            saveHistory(
                rawText: rawText,
                finalText: rawText,
                target: target,
                processingResult: processingResult,
                outputResult: outputResult
            )
            finishCurrentDictation()
        }
        return true
    }

    private func finishAgentDispatchFallbackInputWithoutTextCorrection() -> Bool {
        guard state == .processing,
              currentMode == .agentDispatch,
              let rawText = agentDispatchFallbackInputAwaitingCorrection,
              !rawText.isEmpty else {
            AppLogger.dictation.warning("finishAgentDispatchFallbackInputWithoutTextCorrection aborted: invalid state/text")
            cancel()
            return false
        }

        processingTask?.cancel()
        processingTask = nil
        agentDispatchFallbackInputAwaitingCorrection = nil
        let target = currentTarget

        guard stateMachine.startInjecting() else {
            AppLogger.dictation.warning("finishAgentDispatchFallbackInputWithoutTextCorrection blocked: startInjecting failed")
            return false
        }
        notifyStateChanged()
        let sessionID = currentCallbackSessionID
        processingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let outputResult = await deliverFinalText(
                rawText,
                originalTarget: target,
                sessionID: sessionID
            )
            guard !Task.isCancelled,
                  isCurrentSession(sessionID),
                  state == .injecting else {
                return
            }
            if case .cancelled = outputResult {
                finishCurrentDictation()
                return
            }

            do {
                try agentDispatchHandler?.completeFallbackInput(
                    finalText: rawText,
                    outputResult: outputResult
                )
                onAgentDispatchPresentation(.fallbackInput(text: rawText))
            } catch {
                AppLogger.general.error(
                    "Failed to complete Agent Dispatch fallback input: \(error.localizedDescription)"
                )
            }
            finishCurrentDictation()
        }
        return true
    }

    private func handleTranscription(
        text: String,
        isFinal: Bool,
        callbackSessionID: String
    ) {
        guard currentCallbackSessionID == callbackSessionID,
              state.isRecordingActive else {
            return
        }
        if isFinal {
            AppLogger.dictation.debug("received final transcription chunk chars=\(text.count)")
        } else if text.count < 40 {
            AppLogger.dictation.debug("received transient transcription=\(text)")
        }
        if !isFinal {
            onTranscriptionUpdate(text, false)
        }
        if let completedText = transcriptionSession.update(text: text, isFinal: isFinal) {
            AppLogger.dictation.debug("transcription session completed text length=\(completedText.count)")
            scheduleProcessing(for: completedText)
        }
    }

    private func scheduleProcessing(for recognizedText: String) {
        processingTask?.cancel()
        let sessionID = currentCallbackSessionID
        AppLogger.dictation.debug("scheduleProcessing state=\(stateLogName(state)) chars=\(recognizedText.count)")
        recognizedTextAwaitingProcessing = recognizedText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        processingTask = Task { @MainActor [weak self] in
            await self?.finishRecognizedText(recognizedText, sessionID: sessionID)
        }
    }

    private func scheduleFinalTimeout() {
        finalTimeoutTask?.cancel()
        let sessionID = currentCallbackSessionID
        let timeoutNanoseconds = activeFinalTimeoutNanoseconds()
        finalTimeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await clock.sleep(nanoseconds: timeoutNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await handleFinalTimeout(sessionID: sessionID)
        }
    }

    private func activeFinalTimeoutNanoseconds() -> UInt64 {
        guard let currentConfiguration else {
            return finalTimeoutNanoseconds
        }
        switch currentConfiguration.engineType {
        case .funASR, .senseVoice, .paraformer, .groqWhisper, .tencentCloud,
             .aliyunDashScope, .parakeetStreaming, .omnilingualASR:
            return max(finalTimeoutNanoseconds, Self.coldLocalModelFinalTimeoutNanoseconds)
        case .apple, .whisper, .qwen3, .nvidiaNemotron:
            return finalTimeoutNanoseconds
        }
    }

    private func handleFinalTimeout(sessionID: String?) async {
        guard isCurrentSession(sessionID),
              state.isRecordingActive else {
            return
        }

        if let partialText = transcriptionSession.timeout(),
           !partialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AppLogger.dictation.debug("handleFinalTimeout fallback to partial text length=\(partialText.count)")
            scheduleProcessing(for: partialText)
            return
        }

        AppLogger.dictation.warning("handleFinalTimeout reached without text")
        fail(DictationOrchestratorError.finalResultTimedOut)
    }

    private func handleRecognitionError(_ error: Error, callbackSessionID: String) async {
        guard currentCallbackSessionID == callbackSessionID,
              state.isRecordingActive else {
            return
        }

        if let partialText = transcriptionSession.fallbackToLatestText(),
           !partialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AppLogger.dictation.debug("handleRecognitionError fallback to partial text length=\(partialText.count)")
            scheduleProcessing(for: partialText)
            return
        }

        AppLogger.dictation.error("handleRecognitionError no fallback text: \(error.localizedDescription)")
        fail(error)
    }

    private func finishRecognizedText(_ recognizedText: String, sessionID: String?) async {
        AppLogger.dictation.debug("finishRecognizedText entered session=\(sessionID ?? "nil") mode=\(currentMode.rawValue) chars=\(recognizedText.count)")
        guard !Task.isCancelled,
              isCurrentSession(sessionID),
              state.isRecordingActive else {
            return
        }

        finalTimeoutTask?.cancel()
        finalTimeoutTask = nil
        audioRecorder.stop()
        endCurrentAudioCapture()
        currentEngine?.stop()

        let rawText = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            AppLogger.dictation.warning("finishRecognizedText aborted: empty recognized text")
            textPipeline.cancelContextBoost()
            if currentMode == .agentCompose {
                agentComposeHandler?.cancel()
            } else if currentMode == .agentDispatch {
                agentDispatchHandler?.cancel()
            }
            audioBufferForwarder.detach()
            currentEngine = nil
            currentCallbackSessionID = nil
            currentTarget = nil
            currentMode = .dictation
            stateMachine.finish()
            notifyStateChanged()
            return
        }

        guard stateMachine.startProcessing() else {
            AppLogger.dictation.warning("finishRecognizedText blocked: stateMachine startProcessing failed")
            return
        }
        notifyStateChanged()
        onProcessingStarted(rawText)
        AppLogger.dictation.debug("finishRecognizedText start processing mode=\(currentMode.rawValue)")

        if currentMode == .agentCompose {
            AppLogger.dictation.debug("finishRecognizedText route to agent compose")
            await finishAgentCompose(rawText)
            return
        }
        if currentMode == .agentDispatch {
            AppLogger.dictation.debug("finishRecognizedText route to agent dispatch")
            await finishAgentDispatch(rawText)
            return
        }

        let target = currentTarget
        AppLogger.dictation.debug("finishRecognizedText dictation target=\(target?.bundleID ?? "nil")")
        let correctionContext = CorrectionContext(
            mode: .dictation,
            providerID: currentConfiguration?.asrProviderID ?? "unknown",
            modelID: currentConfiguration?.modelID,
            language: currentConfiguration?.languageIdentifier,
            bundleIdentifier: target?.bundleID,
            isFinalTranscript: true,
            isSecureField: isFocusedTextFieldSecure()
        )
        let processingResult = await textPipeline.process(
            rawText,
            target: target,
            correctionContext: correctionContext,
            onRefinedTextUpdate: { [weak self] text in
                guard let self,
                      self.isCurrentSession(sessionID),
                      self.state == .processing else {
                    return
                }
                self.onTranscriptionUpdate(text, true)
            }
        )
        guard !Task.isCancelled,
              isCurrentSession(sessionID),
              state == .processing else {
            return
        }
        let finalText = normalizedFinalText(from: processingResult, fallback: rawText)

        guard stateMachine.startInjecting() else {
            AppLogger.dictation.warning("finishRecognizedText blocked: stateMachine startInjecting failed")
            return
        }
        notifyStateChanged()
        let outputResult = await deliverFinalText(
            finalText,
            originalTarget: target,
            sessionID: sessionID
        )
        guard !Task.isCancelled,
              isCurrentSession(sessionID),
              state == .injecting else {
            return
        }
        if case .cancelled = outputResult {
            finishCurrentDictation()
            return
        }

        saveHistory(
            rawText: rawText,
            finalText: finalText,
            target: target,
            processingResult: processingResult,
            outputResult: outputResult
        )
        scheduleCorrectionObservationIfNeeded(
            insertedText: finalText,
            context: correctionContext,
            processingResult: processingResult,
            outputResult: outputResult
        )

        finishCurrentDictation()
    }

    private func finishAgentCompose(_ rawText: String) async {
        guard let agentComposeHandler else {
            fail(DictationOrchestratorError.agentComposeUnavailable)
            return
        }
        guard let sessionID = currentCallbackSessionID else {
            return
        }

        AppLogger.dictation.debug("finishAgentCompose invoked rawLen=\(rawText.count)")
        onTranscriptionUpdate("正在结合上下文生成...", true)
        do {
            updateAgentComposeASRMetadataIfAvailable()
            let result = try await agentComposeHandler.finish(rawTranscript: rawText)
            guard !Task.isCancelled,
                  isCurrentSession(sessionID),
                  state == .processing else {
                return
            }
            if case .cancelled = result {
                finishCurrentDictation()
                return
            }
            AppLogger.dictation.debug("finishAgentCompose completed, preparing inject state")
            guard stateMachine.startInjecting() else {
                return
            }
            notifyStateChanged()
            audioBufferForwarder.detach()
            currentEngine = nil
            currentCallbackSessionID = nil
            currentTarget = nil
            currentMode = .dictation
            stateMachine.finish()
            notifyStateChanged()
            onAgentComposeCompleted(result)
        } catch {
            guard !Task.isCancelled,
                  isCurrentSession(sessionID),
                  state == .processing else {
                return
            }
            AppLogger.dictation.error("finishAgentCompose failed: \(error.localizedDescription)")
            fail(error)
        }
    }

    private func finishAgentDispatch(_ rawText: String) async {
        guard let agentDispatchHandler else {
            fail(DictationOrchestratorError.agentDispatchUnavailable)
            return
        }
        guard let sessionID = currentCallbackSessionID else { return }

        do {
            updateAgentASRMetadataIfAvailable()
            let presentation = try await agentDispatchHandler.finish(rawTranscript: rawText)
            AppLogger.dictation.debug("finishAgentDispatch completed presentation=\(presentation)")
            guard !Task.isCancelled,
                  isCurrentSession(sessionID),
                  state == .processing else {
                return
            }
            if case let .fallbackInput(text) = presentation {
                AppLogger.dictation.debug("finishAgentDispatch requires fallbackInput path")
                await finishAgentDispatchFallbackInput(
                    text: text,
                    rawText: rawText,
                    sessionID: sessionID
                )
                return
            }
            audioBufferForwarder.detach()
            currentEngine = nil
            currentCallbackSessionID = nil
            currentTarget = nil
            currentMode = .dictation
            stateMachine.finish()
            notifyStateChanged()
            onAgentDispatchPresentation(presentation)
        } catch {
            guard !Task.isCancelled,
                  isCurrentSession(sessionID),
                  state == .processing else {
                return
            }
            AppLogger.dictation.error("finishAgentDispatch failed: \(error.localizedDescription)")
            fail(error)
        }
    }

    private func finishAgentDispatchFallbackInput(
        text: String,
        rawText: String,
        sessionID: String
    ) async {
        AppLogger.dictation.debug("finishAgentDispatchFallbackInput start textLen=\(text.count) rawLen=\(rawText.count)")
        let target = currentTarget
        agentDispatchFallbackInputAwaitingCorrection = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let processingResult = await textPipeline.process(
            text,
            target: target,
            onRefinedTextUpdate: { [weak self] refinedText in
                guard let self,
                      self.isCurrentSession(sessionID),
                      self.state == .processing else {
                    return
                }
                self.onTranscriptionUpdate(refinedText, true)
            }
        )
        guard !Task.isCancelled,
              isCurrentSession(sessionID),
              state == .processing else {
            return
        }
        agentDispatchFallbackInputAwaitingCorrection = nil
        let finalText = normalizedFinalText(from: processingResult, fallback: text)

        guard stateMachine.startInjecting() else {
            AppLogger.dictation.warning("finishAgentDispatchFallbackInput blocked: stateMachine startInjecting failed")
            return
        }
        notifyStateChanged()
        let outputResult = await deliverFinalText(
            finalText,
            originalTarget: target,
            sessionID: sessionID
        )
        guard !Task.isCancelled,
              isCurrentSession(sessionID),
              state == .injecting else {
            return
        }
        if case .cancelled = outputResult {
            finishCurrentDictation()
            return
        }

        do {
            try agentDispatchHandler?.completeFallbackInput(
                finalText: finalText,
                outputResult: outputResult
            )
            onAgentDispatchPresentation(.fallbackInput(text: finalText))
        } catch {
            AppLogger.general.error("Failed to complete Agent Dispatch fallback input: \(error.localizedDescription)")
        }
        finishCurrentDictation()
    }

    private func normalizedFinalText(from result: TextProcessingResult, fallback: String) -> String {
        let trimmed = result.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func finishCurrentDictation() {
        audioBufferForwarder.detach()
        endCurrentAudioCapture()
        currentEngine = nil
        currentCallbackSessionID = nil
        currentTarget = nil
        currentMode = .dictation
        recognizedTextAwaitingProcessing = nil
        agentDispatchFallbackInputAwaitingCorrection = nil
        processingTask = nil
        stateMachine.finish()
        notifyStateChanged()
    }

    private func deliverFinalText(
        _ text: String,
        originalTarget: DictationTarget?,
        sessionID: String?
    ) async -> OutputResult {
        guard isCurrentSession(sessionID),
              state == .injecting else {
            AppLogger.dictation.debug("deliverFinalText blocked for session=\(sessionID ?? "nil") state=\(stateLogName(state))")
            return .cancelled
        }
        let currentTarget = targetProvider.currentTarget()
        AppLogger.dictation.debug("deliverFinalText target=\(currentTarget?.bundleID ?? "nil"), originalTarget=\(originalTarget?.bundleID ?? "nil"), textLen=\(text.count)")
        let outputResult = await outputService.deliver(
            text: text,
            mode: .dictation,
            target: currentTarget,
            originalTarget: originalTarget
        )
        AppLogger.dictation.debug("deliverFinalText completed kind=\(outputResult.kind.rawValue)")
        return outputResult
    }

    private func isCurrentSession(_ sessionID: String?) -> Bool {
        guard let sessionID else { return false }
        return currentCallbackSessionID == sessionID
    }

    private func saveHistory(
        rawText: String,
        finalText: String,
        target: DictationTarget?,
        processingResult: TextProcessingResult,
        outputResult: OutputResult
    ) {
        guard let configuration = currentConfiguration else {
            AppLogger.dictation.warning("saveHistory skipped: missing currentConfiguration")
            return
        }

        let finishedAt = clock.now
        let startedAt = startedAt ?? finishedAt
        let durationMS = max(0, Int(finishedAt.timeIntervalSince(startedAt) * 1000))
        let charCount = finalText.count
        let durationMinutes = max(Double(durationMS) / 60_000.0, 1.0 / 60_000.0)

        let historyID = UUID().uuidString
        let entry = DictationHistoryEntry(
            id: historyID,
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
            processingTraceJSON: traceJSON(
                processingResult.trace,
                outputResult: outputResult,
                diagnosticID: historyID
            ),
            createdAt: finishedAt,
            updatedAt: finishedAt,
            deletedAt: nil
        )

        do {
            try historyRepository.save(entry)
            try saveDictationAsset(
                id: historyID,
                rawText: rawText,
                finalText: finalText,
                target: target,
                createdAt: finishedAt
            )
            onHistorySaved()
            AppLogger.dictation.debug("saveHistory success id=\(historyID)")
        } catch {
            AppLogger.general.error("Failed to save dictation history: \(error.localizedDescription)")
        }
    }

    private func saveDictationAsset(
        id: String,
        rawText: String,
        finalText: String,
        target: DictationTarget?,
        createdAt: Date
    ) throws {
        guard let assetRepository else { return }
        let title = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = try AssetItem.makeText(
            id: "dictation-\(id)",
            source: .dictation,
            title: title.isEmpty ? "语音输入" : title,
            text: finalText,
            rawText: rawText,
            previewText: title.isEmpty ? rawText : title,
            contentHash: "dictation-\(id)",
            captureReason: .dictationCompleted,
            metadataJSON: nil,
            sourceAppName: target?.appName,
            sourceAppBundleID: target?.bundleID,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        try assetRepository.save(item)
    }

    private func scheduleCorrectionObservationIfNeeded(
        insertedText: String,
        context: CorrectionContext,
        processingResult: TextProcessingResult,
        outputResult: OutputResult
    ) {
        guard case .injected = outputResult,
              !context.isSecureField else {
            return
        }
        if processingResult.trace?.llm?.succeeded == true,
           processingResult.finalText != processingResult.rawText {
            return
        }
        correctionObservationScheduler?.scheduleObservation(
            insertedText: insertedText,
            context: context,
            appliedEvents: processingResult.appliedCorrectionEvents
        )
    }

    private func warningsJSON(_ warnings: [String]) -> String? {
        guard !warnings.isEmpty,
              let data = try? JSONEncoder().encode(warnings) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func traceJSON(
        _ trace: TextProcessingTrace?,
        outputResult: OutputResult,
        diagnosticID: String
    ) -> String? {
        var trace = trace ?? TextProcessingTrace()
        trace.output = OutputDeliveryTrace(resultKind: outputResult.kind.rawValue)
        LLMDiagnosticCapture.shared.capture(taskID: diagnosticID, trace: trace)
        guard let data = try? JSONEncoder().encode(trace.safeForPersistence()) else {
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

    private func updateAgentASRMetadataIfAvailable() {
        guard let configuration = currentConfiguration else { return }
        let runtimeSnapshot = (currentEngine as? ASRRuntimeMetadataProviding)?.asrRuntimeMetadataSnapshot
        let metadata = asrMetadata(for: configuration, runtimeSnapshot: runtimeSnapshot)
        do {
            switch currentMode {
            case .agentCompose:
                try agentComposeHandler?.updateASRMetadata(metadata)
            case .agentDispatch:
                try agentDispatchHandler?.updateASRMetadata(metadata)
            case .dictation:
                break
            }
        } catch {
            AppLogger.general.error("Failed to update ASR metadata: \(error.localizedDescription)")
        }
    }

    private func fail(_ error: Error) {
        AppLogger.dictation.error("dictation failed mode=\(currentMode.rawValue) state=\(stateLogName(state)) reason=\(error.localizedDescription)")
        finalTimeoutTask?.cancel()
        finalTimeoutTask = nil
        processingTask?.cancel()
        processingTask = nil
        recognizedTextAwaitingProcessing = nil
        agentDispatchFallbackInputAwaitingCorrection = nil
        textPipeline.cancelContextBoost()
        audioRecorder.stop()
        endCurrentAudioCapture()
        updateAgentComposeASRMetadataIfAvailable()
        currentEngine?.cancel()
        audioBufferForwarder.detach()
        if currentMode == .agentCompose {
            agentComposeHandler?.fail(error)
        } else if currentMode == .agentDispatch {
            agentDispatchHandler?.fail(error)
        }
        currentEngine = nil
        currentCallbackSessionID = nil
        currentTarget = nil
        currentMode = .dictation
        stateMachine.fail(message: error.localizedDescription)
        notifyStateChanged()
        onError(error)
        stateMachine.finish()
        notifyStateChanged()
    }

    private func notifyStateChanged() {
        AppLogger.dictation.info(
            "dictation_state_changed state=\(stateLogName(state)) mode=\(currentMode.rawValue) hasSession=\(currentCallbackSessionID != nil)"
        )
        onStateChange(state)
    }

    private func stateLogName(_ state: DictationState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .recording:
            return "recording"
        case .waitingForFinal:
            return "waitingForFinal"
        case .processing:
            return "processing"
        case .injecting:
            return "injecting"
        case .failed:
            return "failed"
        }
    }

    private func audioCaptureKind(for mode: VoiceTaskMode) -> AudioCaptureKind {
        switch mode {
        case .dictation:
            return .dictation
        case .agentCompose:
            return .agentCompose
        case .agentDispatch:
            return .agentCompose
        }
    }

    private func endCurrentAudioCapture() {
        guard let audioCaptureLease else { return }
        AppLogger.dictation.debug("endCurrentAudioCapture end lease")
        audioCaptureCoordinator.end(audioCaptureLease)
        self.audioCaptureLease = nil
    }
}

private final class TestClipboardService: ClipboardSetting {
    func setString(_ text: String) -> Bool {
        true
    }
}

enum DictationOrchestratorError: LocalizedError, Equatable {
    case alreadyRunning
    case agentComposeUnavailable
    case agentDispatchUnavailable
    case finalResultTimedOut
    case unsupportedLanguage(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "听写正在进行中。"
        case .agentComposeUnavailable:
            return "任务助手尚未完成初始化，请重启码上写后重试。"
        case .agentDispatchUnavailable:
            return "AI 编程控制台尚未完成初始化，请重启码上写后重试。"
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
        case .parakeetStreaming:
            return ASRProviderID.parakeetStreaming
        case .omnilingualASR:
            return ASRProviderID.omnilingualASR
        case .groqWhisper:
            return ASRProviderID.groqWhisper
        case .tencentCloud:
            return ASRProviderID.tencentCloudASR
        case .aliyunDashScope:
            return ASRProviderID.qwenCloudASR
        }
    }
}
