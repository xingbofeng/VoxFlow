import AVFoundation
import VoxFlowASRRuntime
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
    var onPausePreOutputRecovery: (OutputResult) -> Void = { _ in }
    var onAgentComposeCompleted: (OutputResult) -> Void = { _ in }
    var onCommandCompleted: (OutputResult) -> Void = { _ in }
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
    private let commandHandler: (any CommandHandling)?
    private let audioCaptureCoordinator: any AudioCaptureCoordinating
    private let correctionObservationScheduler: (any CorrectionObservationScheduling)?
    private let asrTermPromptProvider: (any ASRTermPromptProviding)?
    private let isFocusedTextFieldSecure: @MainActor () -> Bool
    private let assetRepository: (any AssetRepository)?
    private let hotwordHitCounter: HotwordHitCounter?
    private let finalTimeoutNanoseconds: UInt64
    private let pausePreOutputBaseConfiguration: PausePreOutputConfiguration?
    private let isPausePreOutputEnabled: (@MainActor () -> Bool)?
    private var stateMachine = DictationStateMachine()
    private var transcriptionSession = TranscriptionSession()
    private var pausePreOutputSession: PausePreOutputSession?
    private var pausePreOutputRecoveryResult: OutputResult?
    private var pauseSilenceTask: Task<Void, Never>?
    private var pauseSegmentTask: Task<Void, Never>?
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
        commandHandler: (any CommandHandling)? = nil,
        audioCaptureCoordinator: any AudioCaptureCoordinating = AudioCaptureCoordinator(),
        correctionObservationScheduler: (any CorrectionObservationScheduling)? = nil,
        asrTermPromptProvider: (any ASRTermPromptProviding)? = nil,
        isFocusedTextFieldSecure: @escaping @MainActor () -> Bool = { false },
        finalTimeoutNanoseconds: UInt64 = 15_000_000_000,
        assetRepository: (any AssetRepository)? = nil,
        hotwordHitCounter: HotwordHitCounter? = nil,
        pausePreOutputConfiguration: PausePreOutputConfiguration? = nil,
        isPausePreOutputEnabled: (@MainActor () -> Bool)? = nil
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
        self.commandHandler = commandHandler
        self.audioCaptureCoordinator = audioCaptureCoordinator
        self.correctionObservationScheduler = correctionObservationScheduler
        self.asrTermPromptProvider = asrTermPromptProvider
        self.isFocusedTextFieldSecure = isFocusedTextFieldSecure
        self.assetRepository = assetRepository
        self.hotwordHitCounter = hotwordHitCounter
        self.finalTimeoutNanoseconds = finalTimeoutNanoseconds
        self.pausePreOutputBaseConfiguration = pausePreOutputConfiguration
        self.isPausePreOutputEnabled = isPausePreOutputEnabled
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
        if mode == .command, commandHandler == nil {
            AppLogger.dictation.warning("Dictation start rejected: command handler unavailable")
            throw DictationOrchestratorError.commandUnavailable
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
        pausePreOutputSession = (mode == .dictation ? activePausePreOutputConfiguration() : nil).map {
            PausePreOutputSession(configuration: $0)
        }
        pausePreOutputRecoveryResult = nil
        pauseSilenceTask?.cancel()
        pauseSilenceTask = nil
        pauseSegmentTask?.cancel()
        pauseSegmentTask = nil
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
        } else if mode == .command {
            guard let commandHandler else {
                stateMachine.reset()
                currentMode = .dictation
                endCurrentAudioCapture()
                notifyStateChanged()
                throw DictationOrchestratorError.commandUnavailable
            }
            do {
                AppLogger.dictation.debug("Dictation start: preparing command handler")
                try commandHandler.start(
                    target: currentTarget,
                    asrMetadata: asrMetadata(for: configuration)
                )
            } catch {
                AppLogger.dictation.error("Start command handler failed: \(error.localizedDescription)")
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
        if let promptConfiguringEngine = engine as? any ASRTermPromptConfiguring {
            promptConfiguringEngine.configureTermPrompt(
                asrTermPromptProvider?.prompt(
                    for: configuration.engineType,
                    bundleIdentifier: currentTarget?.bundleID
                )
            )
        }
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
            } else if mode == .command {
                commandHandler?.cancel()
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

    func handleAudioCaptureFailure(_ error: Error) {
        guard state.isRecordingActive else { return }
        fail(error, notifyRecognitionError: false)
        onError(LocalizedDictationError(message: localizeProviderErrorMessage(error.localizedDescription)))
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
        pauseSilenceTask?.cancel()
        pauseSilenceTask = nil
        pauseSegmentTask?.cancel()
        pauseSegmentTask = nil
        textPipeline.cancelContextBoost()
        audioRecorder.stop()
        endCurrentAudioCapture()
        currentEngine?.cancel()
        audioBufferForwarder.detach()
        if currentMode == .agentCompose {
            agentComposeHandler?.cancel()
        } else if currentMode == .agentDispatch {
            agentDispatchHandler?.cancel()
        } else if currentMode == .command {
            commandHandler?.cancel()
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
        scheduleProcessing(for: rawText, withoutTextCorrection: true)
        return true
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
            hotwordHitCounter?.recordHits(in: rawText)
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
                    outputResult: outputResult,
                    appliedCorrectionEvents: [],
                    processingTrace: nil
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
        handlePausePreOutputTick(text: text, isFinal: isFinal)
        if let completedText = transcriptionSession.update(text: text, isFinal: isFinal) {
            AppLogger.dictation.debug("transcription session completed text length=\(completedText.count)")
            scheduleProcessing(for: completedText)
        }
    }

    // MARK: - Pause pre-output

    /// Resolves the active pause pre-output configuration for a new session:
    /// the base configuration must exist, and the dynamic enablement closure
    /// (when provided) decides whether this session uses it.
    private func activePausePreOutputConfiguration() -> PausePreOutputConfiguration? {
        guard let baseConfiguration = pausePreOutputBaseConfiguration else { return nil }
        if let isPausePreOutputEnabled, !isPausePreOutputEnabled() {
            return nil
        }
        return baseConfiguration
    }

    /// Restarts the segment silence timer on every non-final partial and
    /// flushes the pending delta when the final result arrives while a pause
    /// segment is still being processed.
    private func handlePausePreOutputTick(text: String, isFinal: Bool) {
        guard pausePreOutputSession?.isBroken == false else { return }
        if isFinal {
            // Final text arrives with the recording stopping; the regular
            // release path flushes the remaining tail beyond the watermark.
            pauseSilenceTask?.cancel()
            pauseSilenceTask = nil
            return
        }
        guard state == .recording else { return }
        schedulePauseSilenceTimer()
    }

    private func schedulePauseSilenceTimer() {
        guard let configuration = pausePreOutputBaseConfiguration else { return }
        pauseSilenceTask?.cancel()
        let sessionID = currentCallbackSessionID
        pauseSilenceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await clock.sleep(nanoseconds: configuration.silenceThresholdNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.flushPauseSegment(sessionID: sessionID)
        }
    }

    private func flushPauseSegment(sessionID: String?) {
        guard isCurrentSession(sessionID),
              state == .recording,
              pausePreOutputSession?.isBroken == false,
              // One segment in flight at a time: overlapping claims would
              // break rollback and interleave injected text ordering. The
              // next partial re-arms the timer, so no text is lost.
              pauseSegmentTask == nil else {
            return
        }
        let cumulativeText = transcriptionSession.latestTranscriptText
        guard !cumulativeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let delta = deltaForPausePreOutput(from: cumulativeText)
        switch delta {
        case .text(let segmentText):
            schedulePauseSegmentProcessing(segmentText)
        case .noDelta, .revised:
            break
        }
    }

    private func deltaForPausePreOutput(
        from cumulativeText: String,
        enforcingMinimumCharacterCount: Bool = true
    ) -> PausePreOutputDelta {
        guard var session = pausePreOutputSession else { return .noDelta }
        let delta = session.takeDelta(
            from: cumulativeText,
            enforcingMinimumCharacterCount: enforcingMinimumCharacterCount
        )
        if case .revised = delta {
            AppLogger.dictation.info("pause pre-output disabled: engine revised delivered prefix")
        }
        pausePreOutputSession = session
        return delta
    }

    private func schedulePauseSegmentProcessing(_ segmentText: String) {
        guard let sessionID = currentCallbackSessionID else { return }
        pauseSegmentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.processPauseSegment(segmentText, sessionID: sessionID)
            self.pauseSegmentTask = nil
        }
    }

    /// Processes and delivers one pause segment while recording continues.
    /// Runs as a side pipeline: the state machine stays in `.recording`, the
    /// recorder and engine are untouched, and later partials keep flowing.
    private func processPauseSegment(_ segmentText: String, sessionID: String) async {
        AppLogger.dictation.debug("pause segment processing chars=\(segmentText.count)")
        let target = currentTarget
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
            segmentText.trimmingCharacters(in: .whitespacesAndNewlines),
            target: target,
            correctionContext: correctionContext,
            onRefinedTextUpdate: { _ in
                // Segment output goes straight to injection; streaming
                // refinement updates would double-render in the HUD while
                // live partials are still arriving.
            }
        )
        guard !Task.isCancelled,
              isCurrentSession(sessionID),
              state.isRecordingActive else {
            rollbackPauseSegmentDelivery(segmentText)
            return
        }
        let finalText = preservingPauseSeparator(
            normalizedFinalText(from: processingResult, fallback: segmentText),
            from: segmentText
        )
        let outputResult = await outputService.deliver(
            text: finalText,
            mode: .dictation,
            target: targetProvider.currentTarget(),
            originalTarget: target
        )
        guard !Task.isCancelled,
              isCurrentSession(sessionID),
              state.isRecordingActive else {
            rollbackPauseSegmentDelivery(segmentText)
            return
        }
        guard outputResult.kind != .cancelled else {
            AppLogger.dictation.warning("pause segment delivery cancelled; disabling pause pre-output")
            rollbackPauseSegmentDelivery(segmentText)
            pausePreOutputSession = nil
            return
        }
        hotwordHitCounter?.recordHits(in: finalText)
        saveHistory(
            rawText: segmentText,
            finalText: finalText,
            target: target,
            processingResult: processingResult,
            outputResult: outputResult
        )
    }

    private func rollbackPauseSegmentDelivery(_ segmentText: String) {
        pausePreOutputSession?.rollbackDelivery(of: segmentText)
    }

    private func scheduleProcessing(for recognizedText: String, withoutTextCorrection: Bool = false) {
        processingTask?.cancel()
        let sessionID = currentCallbackSessionID
        let inFlightPauseSegmentTask = pauseSegmentTask
        AppLogger.dictation.debug("scheduleProcessing state=\(stateLogName(state)) chars=\(recognizedText.count)")
        processingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Let an in-flight pause segment finish first: it advances the
            // watermark, so the tail delta must be computed after it settles.
            await inFlightPauseSegmentTask?.value
            guard !Task.isCancelled,
                  self.isCurrentSession(sessionID) else {
                return
            }
            let tailText = self.pausePreOutputTailText(for: recognizedText)
            self.recognizedTextAwaitingProcessing = tailText
            await self.finishRecognizedText(
                tailText, sessionID: sessionID,
                withoutTextCorrection: withoutTextCorrection
            )
        }
    }

    /// Remaining text beyond the pause pre-output watermark. Returns an empty
    /// string only when everything was already delivered. A revised prefix
    /// retains the full final transcript for copy-only recovery.
    private func pausePreOutputTailText(for cumulativeText: String) -> String {
        guard currentMode == .dictation,
              pausePreOutputSession != nil else {
            return cumulativeText
        }
        switch deltaForPausePreOutput(from: cumulativeText, enforcingMinimumCharacterCount: false) {
        case .text(let tail):
            return tail
        case .noDelta:
            return ""
        case .revised:
            return cumulativeText
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
        case .funASR, .fireRedASR, .xasr, .senseVoice, .confucius4R2T2, .paraformer, .groqWhisper,
             .tencentCloud, .aliyunDashScope, .volcengineDoubao, .parakeetStreaming,
             .omnilingualASR:
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

    private func finishRecognizedText(
        _ recognizedText: String,
        sessionID: String?,
        withoutTextCorrection: Bool = false
    ) async {
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
            } else if currentMode == .command {
                commandHandler?.cancel()
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

        if withoutTextCorrection {
            processingTask = nil
            finishWithoutTextCorrection()
            return
        }

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
        if currentMode == .command {
            AppLogger.dictation.debug("finishRecognizedText route to voice command")
            await finishCommand(rawText)
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
        let finalText = preservingPauseSeparator(
            normalizedFinalText(from: processingResult, fallback: rawText),
            from: recognizedText
        )

        guard stateMachine.startInjecting() else {
            AppLogger.dictation.warning("finishRecognizedText blocked: stateMachine startInjecting failed")
            return
        }
        notifyStateChanged()
        let correctionObservationAnchor = correctionObservationAnchorIfNeeded(
            context: correctionContext,
            targetProcessID: target?.pid
        )
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

        hotwordHitCounter?.recordHits(in: finalText)
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
            outputResult: outputResult,
            baseline: correctionObservationBaseline(from: correctionObservationAnchor),
            targetProcessID: target?.pid
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
            onTranscriptionUpdate(
                L10n.localize("dictation.hud.context_fusion", comment: "HUD hint while generating response with context"),
                true
            )
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
            fail(error, notifyRecognitionError: false)
        }
    }

    private func finishCommand(_ rawText: String) async {
        guard let commandHandler else {
            fail(DictationOrchestratorError.commandUnavailable)
            return
        }
        guard let sessionID = currentCallbackSessionID else {
            return
        }

        AppLogger.dictation.debug("finishCommand invoked instructionLen=\(rawText.count)")
        onTranscriptionUpdate(
            L10n.localize("dictation.hud.applying_command", comment: "HUD hint while applying a voice command"),
            true
        )
        do {
            updateAgentASRMetadataIfAvailable()
            let result = try await commandHandler.finish(rawTranscript: rawText)
            guard !Task.isCancelled,
                  isCurrentSession(sessionID),
                  state == .processing else {
                return
            }
            if case .cancelled = result {
                finishCurrentDictation()
                return
            }
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
            onCommandCompleted(result)
        } catch {
            guard !Task.isCancelled,
                  isCurrentSession(sessionID),
                  state == .processing else {
                return
            }
            AppLogger.dictation.error("finishCommand failed: \(error.localizedDescription)")
            // 语音指令是用户显式发起的动作，失败必须可见（复用识别错误通道：HUD 提示 + 操作按钮）；
            // agentCompose / agentDispatch 有各自的结果展示，失败保持静默。
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
            fail(error, notifyRecognitionError: false)
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
            text,
            target: target,
            correctionContext: correctionContext,
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
        let observationTargetProcessID = target?.pid
        let correctionObservationAnchor = correctionObservationAnchorIfNeeded(
            context: correctionContext,
            targetProcessID: observationTargetProcessID
        )
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
                outputResult: outputResult,
                appliedCorrectionEvents: processingResult.appliedCorrectionEvents,
                processingTrace: processingResult.trace
            )
            onAgentDispatchPresentation(.fallbackInput(text: finalText))
            scheduleCorrectionObservationIfNeeded(
                insertedText: finalText,
                context: correctionContext,
                processingResult: processingResult,
                outputResult: outputResult,
                baseline: correctionObservationBaseline(from: correctionObservationAnchor),
                targetProcessID: observationTargetProcessID
            )
        } catch {
            AppLogger.general.error("Failed to complete Agent Dispatch fallback input: \(error.localizedDescription)")
        }
        finishCurrentDictation()
    }

    private func normalizedFinalText(from result: TextProcessingResult, fallback: String) -> String {
        let trimmed = result.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func preservingPauseSeparator(_ text: String, from rawText: String) -> String {
        guard pausePreOutputSession != nil, pausePreOutputSession?.isBroken == false else { return text }
        return String(rawText.prefix(while: \.isWhitespace)) + text
    }

    private func finishCurrentDictation() {
        let recoveryResult = pausePreOutputRecoveryResult
        pausePreOutputRecoveryResult = nil
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
        if let recoveryResult { onPausePreOutputRecovery(recoveryResult) }
    }

    private func deliverFinalText(
        _ text: String,
        originalTarget: DictationTarget?,
        sessionID: String?
    ) async -> OutputResult {
        guard !Task.isCancelled, isCurrentSession(sessionID),
              state == .injecting else {
            AppLogger.dictation.debug("deliverFinalText blocked for session=\(sessionID ?? "nil") state=\(stateLogName(state))")
            return .cancelled
        }
        if pausePreOutputSession?.isBroken == true {
            let result = await outputService.copy(text: text, mode: .dictation)
            guard !Task.isCancelled, isCurrentSession(sessionID) else { return .cancelled }
            pausePreOutputRecoveryResult = result
            return result
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
            title: title.isEmpty ? L10n.localize("dictation.asset.default_title", comment: "Default dictation asset title") : title,
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
        outputResult: OutputResult,
        baseline: FocusedTextObservation?,
        targetProcessID: Int?
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
            appliedEvents: processingResult.appliedCorrectionEvents,
            baseline: baseline,
            targetProcessID: targetProcessID
        )
    }

    private func correctionObservationAnchorIfNeeded(
        context: CorrectionContext,
        targetProcessID: Int?
    ) -> FocusedTextObservation? {
        guard !context.isSecureField else { return nil }
        return correctionObservationScheduler?.captureBaselineForObservation(targetProcessID: targetProcessID)
    }

    private func correctionObservationBaseline(from anchor: FocusedTextObservation?) -> FocusedTextObservation? {
        guard let anchor else { return nil }
        return correctionObservationScheduler?.recaptureBaselineForObservation(matching: anchor)
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
            case .command:
                try commandHandler?.updateASRMetadata(metadata)
            case .dictation:
                break
            }
        } catch {
            AppLogger.general.error("Failed to update ASR metadata: \(error.localizedDescription)")
        }
    }

    private func fail(_ error: Error, notifyRecognitionError: Bool = true) {
        // Coordinator errors already carry localized model-service reasons.
        // ASR substring fallbacks such as "failed" would erase that guidance.
        let localizedMessage = error is CoordinatorError
            ? error.localizedDescription
            : localizeProviderErrorMessage(error.localizedDescription)
        AppLogger.dictation.error("dictation failed mode=\(currentMode.rawValue) state=\(stateLogName(state)) reason=\(error.localizedDescription)")
        finalTimeoutTask?.cancel()
        finalTimeoutTask = nil
        processingTask?.cancel()
        processingTask = nil
        recognizedTextAwaitingProcessing = nil
        agentDispatchFallbackInputAwaitingCorrection = nil
        pauseSilenceTask?.cancel()
        pauseSilenceTask = nil
        pauseSegmentTask?.cancel()
        pauseSegmentTask = nil
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
        } else if currentMode == .command {
            commandHandler?.fail(error)
        }
        currentEngine = nil
        currentCallbackSessionID = nil
        currentTarget = nil
        currentMode = .dictation
        stateMachine.fail(message: localizedMessage)
        notifyStateChanged()
        if notifyRecognitionError {
            onError(LocalizedDictationError(message: localizedMessage))
        }
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
        case .command:
            return .dictation
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
    case commandUnavailable
    case finalResultTimedOut
    case unsupportedLanguage(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return String(
                L10n.localize("dictation.error.already_running", comment: "Dictation is already running")
            )
        case .agentComposeUnavailable:
            return L10n.localize("dictation.error.agent_compose_unavailable", comment: "Agent compose unavailable message")
        case .agentDispatchUnavailable:
            return L10n.localize("dictation.error.agent_dispatch_unavailable", comment: "Agent dispatch unavailable message")
        case .commandUnavailable:
            return L10n.localize("dictation.error.command_unavailable", comment: "Voice command unavailable message")
        case .finalResultTimedOut:
            return String(
                L10n.localize("dictation.error.final_result_timed_out", comment: "Dictation final result timeout message")
            )
        case .unsupportedLanguage(let identifier):
            return L10n.format("dictation.error.unsupported_language_format", comment: "Unsupported dictation language message",
                identifier
            )
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
        case .fireRedASR:
            return ASRProviderID.fireRedASR
        case .xasr:
            return ASRProviderID.xasr
        case .whisper:
            return ASRProviderID.whisper
        case .qwen3:
            return ASRProviderID.qwen3
        case .senseVoice:
            return ASRProviderID.senseVoice
        case .confucius4R2T2:
            return ASRProviderID.confucius4R2T2
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
        case .volcengineDoubao:
            return ASRProviderID.volcengineDoubao
        }
    }
}

// MARK: - Provider error localization

private struct LocalizedDictationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func localizeProviderErrorMessage(_ message: String) -> String {
    let knownPatterns: [(pattern: String, key: String)] = [
        ("not installed",                 "asr.error.model_not_installed"),
        ("模型文件可能已损坏",            "asr.error.model_corrupt"),
        ("不完整，请重新下载",            "asr.error.model_corrupt"),
        ("does not support language",     "asr.error.unsupported_language"),
        ("暂不支持",                       "asr.error.unsupported_language"),
        ("磁盘空间不够",                  "asr.error.disk_space"),
        ("disk space",                    "asr.error.disk_space"),
        ("下载链接不安全",                "asr.error.download_url_insecure"),
        ("下载已暂停",                    "asr.error.download_paused"),
        ("下载已取消",                    "asr.error.download_cancelled"),
        ("下载中断",                      "asr.error.download_interrupted"),
        ("final result was empty",        "asr.error.empty_transcript"),
        ("没有识别到可用文本",            "asr.error.empty_transcript"),
        ("hardware",                      "asr.error.hardware_unsupported"),
        ("连接超时",                      "asr.error.connection_timeout"),
        ("timeout",                       "asr.error.connection_timeout"),
        // 「API Key」单独出现说明不了什么：provider 的欠费/限额报文里也带这个短语
        // （例如 “The account associated with the API Key is in arrears”），
        // 所以只匹配明确的「缺失/无效」措辞，其余留给下面的通用规则。
        ("配置 api key",                  "asr.error.api_key_missing"),
        ("api key 未配置",                "asr.error.api_key_missing"),
        ("api key 无效",                  "asr.error.api_key_missing"),
        ("missing api key",               "asr.error.api_key_missing"),
        ("no api key",                    "asr.error.api_key_missing"),
        ("api key not set",               "asr.error.api_key_missing"),
        ("api key is not configured",     "asr.error.api_key_missing"),
        ("api key is required",           "asr.error.api_key_missing"),
        ("invalid api key",               "asr.error.api_key_missing"),
        ("incorrect api key",             "asr.error.api_key_missing"),
        ("未配置",                        "asr.error.api_key_missing"),
        ("音频文件",                      "asr.error.audio_read_failed"),
        ("audio file",                    "asr.error.audio_read_failed"),
        ("无法读取",                      "asr.error.audio_read_failed"),
        ("无效响应",                      "asr.error.invalid_response"),
        ("无效的响应",                    "asr.error.invalid_response"),
        ("签名地址无效",                  "asr.error.invalid_response"),
        ("地址无效",                      "asr.error.invalid_response"),
        ("失败（",                        "asr.error.cloud_service_failed"),
        ("failed",                        "asr.error.cloud_service_failed"),
        ("HTTP ",                         "asr.error.cloud_service_failed"),
        ("健康检查",                      "asr.error.health_check"),
        ("连接正常",                      "asr.error.health_check_ok"),
    ]
    for (pattern, key) in knownPatterns {
        if message.localizedCaseInsensitiveContains(pattern) {
            let localized = L10n.localize(key, comment: "")
            if localized != key { return localized }
        }
    }
    return message
}
