import AVFoundation
import VoxFlowAudio
import VoxFlowTextInsertion
import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

@MainActor
final class DictationOrchestratorTests: XCTestCase {
    func testOrdinaryDictationPreparesContextBoostAndCancellationCleansItUp() throws {
        let pipeline = FakeTextPipeline(
            result: TextProcessingResult(rawText: "", finalText: "")
        )
        let target = DictationTarget(
            bundleID: "com.example.editor",
            appName: "Editor",
            pid: 42
        )
        let orchestrator = makeOrchestrator(
            pipeline: pipeline,
            targetProvider: StaticDictationTargetProvider(target: target)
        )

        try orchestrator.start(configuration: .appleChinese)

        XCTAssertEqual(pipeline.preparedTargets, [target])

        orchestrator.cancel()

        XCTAssertEqual(pipeline.cancelContextBoostCallCount, 1)
    }

    func testOrdinaryDictationStartFailureCancelsPreparedContextBoost() {
        let audioRecorder = FakeAudioRecorder()
        audioRecorder.startError = TestError.expected
        let pipeline = FakeTextPipeline(
            result: TextProcessingResult(rawText: "", finalText: "")
        )
        let orchestrator = makeOrchestrator(
            audioRecorder: audioRecorder,
            pipeline: pipeline
        )

        XCTAssertThrowsError(try orchestrator.start(configuration: .appleChinese))

        XCTAssertEqual(pipeline.preparedTargets.count, 1)
        XCTAssertEqual(pipeline.cancelContextBoostCallCount, 1)
    }

    func testEmptyFinalTranscriptCancelsPreparedContextBoost() async throws {
        let engine = FakeASREngine()
        let pipeline = FakeTextPipeline(
            result: TextProcessingResult(rawText: "", finalText: "")
        )
        let orchestrator = makeOrchestrator(engine: engine, pipeline: pipeline)

        try orchestrator.start(configuration: .appleChinese)
        orchestrator.release()
        engine.emit(text: "  ", isFinal: true)
        await drainMainActorTasks()

        XCTAssertEqual(pipeline.cancelContextBoostCallCount, 1)
    }

    func testRecognitionFailureCancelsPreparedContextBoost() async throws {
        let engine = FakeASREngine()
        let pipeline = FakeTextPipeline(
            result: TextProcessingResult(rawText: "", finalText: "")
        )
        let orchestrator = makeOrchestrator(engine: engine, pipeline: pipeline)

        try orchestrator.start(configuration: .appleChinese)
        engine.fail(TestError.expected)
        await drainMainActorTasks()

        XCTAssertEqual(pipeline.cancelContextBoostCallCount, 1)
    }

    func testFinalTranscriptIsProcessedInjectedAndSavedToHistory() async throws {
        let engine = FakeASREngine()
        let audioRecorder = FakeAudioRecorder()
        let pipeline = FakeTextPipeline(result: TextProcessingResult(rawText: "raw", finalText: "final"))
        let injector = FakeTextInjector()
        let history = CapturingHistoryRepository()
        let clock = MutableClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let orchestrator = makeOrchestrator(
            engine: engine,
            audioRecorder: audioRecorder,
            pipeline: pipeline,
            injector: injector,
            history: history,
            clock: clock
        )
        var historySavedCount = 0
        orchestrator.onHistorySaved = {
            historySavedCount += 1
        }

        try orchestrator.start(configuration: .appleChinese)
        clock.now = Date(timeIntervalSince1970: 1_800_000_003)
        orchestrator.release()
        engine.emit(text: "raw", isFinal: true)
        await drainMainActorTasks()

        XCTAssertEqual(injector.injectedTexts, ["final"])
        XCTAssertEqual(history.savedEntries.count, 1)
        XCTAssertEqual(history.savedEntries.first?.rawText, "raw")
        XCTAssertEqual(history.savedEntries.first?.finalText, "final")
        XCTAssertEqual(history.savedEntries.first?.language, "zh-CN")
        XCTAssertEqual(history.savedEntries.first?.asrProviderID, "apple_speech")
        XCTAssertEqual(history.savedEntries.first?.durationMS, 3000)
        XCTAssertEqual(historySavedCount, 1)
        XCTAssertEqual(orchestrator.state, .idle)
        XCTAssertFalse(audioRecorder.isRecording)
        XCTAssertTrue(engine.didStop)
    }

    func testFinalTranscriptIsSavedAsDictationAsset() async throws {
        let engine = FakeASREngine()
        let pipeline = FakeTextPipeline(result: TextProcessingResult(rawText: "原始语音", finalText: "最终语音"))
        let history = CapturingHistoryRepository()
        let assetRepository = CapturingDictationAssetRepository()
        let clock = MutableClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        let orchestrator = makeOrchestrator(
            engine: engine,
            pipeline: pipeline,
            history: history,
            clock: clock,
            targetProvider: StaticDictationTargetProvider(target: target),
            assetRepository: assetRepository
        )

        try orchestrator.start(configuration: .appleChinese)
        clock.now = Date(timeIntervalSince1970: 1_800_000_003)
        orchestrator.release()
        engine.emit(text: "原始语音", isFinal: true)
        await drainMainActorTasks()

        XCTAssertEqual(assetRepository.savedItems.count, 1)
        let asset = try XCTUnwrap(assetRepository.savedItems.first)
        XCTAssertEqual(asset.source, .dictation)
        XCTAssertEqual(asset.contentType, .text)
        XCTAssertEqual(asset.text, "最终语音")
        XCTAssertEqual(asset.rawText, "原始语音")
        XCTAssertEqual(asset.captureReason, .dictationCompleted)
        XCTAssertEqual(asset.sourceAppName, "Editor")
        XCTAssertEqual(asset.sourceAppBundleID, "com.example.editor")
        XCTAssertEqual(asset.createdAt, clock.now)
    }

    func testStartAcceptsJapaneseLanguageConfiguration() throws {
        let engine = FakeASREngine()
        let audioRecorder = FakeAudioRecorder()
        let orchestrator = makeOrchestrator(
            engine: engine,
            audioRecorder: audioRecorder
        )

        try orchestrator.start(configuration: .appleJapanese)

        XCTAssertEqual(orchestrator.state, .recording)
        XCTAssertTrue(audioRecorder.isRecording)
        XCTAssertTrue(engine.didStart)
    }

    func testAgentComposeStartIsRejectedWhileNotesRecordingOwnsAudioCapture() throws {
        let audioCaptureCoordinator = AudioCaptureCoordinator()
        let notesLease = try audioCaptureCoordinator.begin(kind: .notes)
        defer { audioCaptureCoordinator.end(notesLease) }
        let audioRecorder = FakeAudioRecorder()
        let agentHandler = FakeAgentComposeHandler(result: .copied)
        let orchestrator = makeOrchestrator(
            audioRecorder: audioRecorder,
            agentComposeHandler: agentHandler,
            audioCaptureCoordinator: audioCaptureCoordinator
        )

        XCTAssertThrowsError(try orchestrator.start(configuration: .appleChinese, mode: .agentCompose)) { error in
            guard case AudioCaptureCoordinatorError.busy(active: .notes, requested: .agentCompose) = error else {
                return XCTFail("Expected notes audio capture conflict, got \(error)")
            }
        }
        XCTAssertFalse(audioRecorder.isRecording)
        XCTAssertFalse(agentHandler.didCancel)
    }

    func testStartNotifiesRecordingBeforeStartingSlowEngine() throws {
        let engine = FakeASREngine()
        var states: [DictationState] = []
        engine.onStart = {
            XCTAssertEqual(states, [.recording])
        }
        let orchestrator = makeOrchestrator(engine: engine)
        orchestrator.onStateChange = { states.append($0) }

        try orchestrator.start(configuration: .appleChinese)

        XCTAssertEqual(states, [.recording])
        XCTAssertTrue(engine.didStart)
    }

    func testStartNotifiesRecordingBeforeResolvingTargetAndCreatingEngine() throws {
        let engine = FakeASREngine()
        var states: [DictationState] = []
        let targetProvider = ObservingTargetProvider {
            XCTAssertEqual(states, [.recording])
            return DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        }
        let engineFactory = ObservingEngineFactory(engine: engine) {
            XCTAssertEqual(states, [.recording])
        }
        let orchestrator = DictationOrchestrator(
            asrEngineFactory: engineFactory,
            audioRecorder: FakeAudioRecorder(),
            textPipeline: FakeTextPipeline(
                result: TextProcessingResult(rawText: "", finalText: "")
            ),
            textInjector: FakeTextInjector(),
            historyRepository: CapturingHistoryRepository(),
            targetProvider: targetProvider
        )
        orchestrator.onStateChange = { states.append($0) }

        try orchestrator.start(configuration: .qwenEnglish)

        XCTAssertEqual(states, [.recording])
        XCTAssertTrue(engine.didStart)
    }

    func testFinalTimeoutUsesLatestPartialResult() async throws {
        let engine = FakeASREngine()
        let audioRecorder = FakeAudioRecorder()
        let pipeline = FakeTextPipeline(result: TextProcessingResult(rawText: "partial", finalText: "partial"))
        let injector = FakeTextInjector()
        let history = CapturingHistoryRepository()
        let clock = MutableClock(
            now: Date(timeIntervalSince1970: 1_800_000_000),
            returnsFromSleepImmediately: true
        )
        let orchestrator = makeOrchestrator(
            engine: engine,
            audioRecorder: audioRecorder,
            pipeline: pipeline,
            injector: injector,
            history: history,
            clock: clock,
            finalTimeoutNanoseconds: 1
        )

        try orchestrator.start(configuration: .appleChinese)
        engine.emit(text: "partial", isFinal: false)
        orchestrator.release()
        await drainMainActorTasks()

        XCTAssertEqual(injector.injectedTexts, ["partial"])
        XCTAssertEqual(history.savedEntries.first?.rawText, "partial")
        XCTAssertEqual(orchestrator.state, .idle)
    }

    func testColdLocalPseudoStreamingEnginesUseExtendedFinalTimeout() async throws {
        let engine = FakeASREngine()
        let audioRecorder = FakeAudioRecorder()
        let pipeline = FakeTextPipeline(result: TextProcessingResult(rawText: "partial", finalText: "partial"))
        let injector = FakeTextInjector()
        let history = CapturingHistoryRepository()
        let clock = CapturingSleepClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let orchestrator = makeOrchestrator(
            engine: engine,
            audioRecorder: audioRecorder,
            pipeline: pipeline,
            injector: injector,
            history: history,
            clock: clock,
            finalTimeoutNanoseconds: 1
        )

        try orchestrator.start(configuration: DictationConfiguration.paraformerChinese)
        engine.emit(text: "partial", isFinal: false)
        orchestrator.release()
        let scheduledTimeout = await waitUntil(timeout: 1.0) {
            clock.requestedNanoseconds != nil
        }

        XCTAssertTrue(scheduledTimeout)
        XCTAssertEqual(clock.requestedNanoseconds, 120_000_000_000)
        orchestrator.cancel()
    }

    func testRecognitionErrorFallsBackToLatestPartialResultAfterRelease() async throws {
        let engine = FakeASREngine()
        let audioRecorder = FakeAudioRecorder()
        let pipeline = FakeTextPipeline(result: TextProcessingResult(rawText: "partial", finalText: "partial"))
        let injector = FakeTextInjector()
        let history = CapturingHistoryRepository()
        let orchestrator = makeOrchestrator(
            engine: engine,
            audioRecorder: audioRecorder,
            pipeline: pipeline,
            injector: injector,
            history: history
        )

        try orchestrator.start(configuration: .appleChinese)
        engine.emit(text: "partial", isFinal: false)
        orchestrator.release()
        engine.fail(TestError.expected)
        await drainMainActorTasks()

        XCTAssertEqual(injector.injectedTexts, ["partial"])
        XCTAssertEqual(history.savedEntries.first?.rawText, "partial")
        XCTAssertEqual(orchestrator.state, .idle)
    }

    func testLateFinalFromCancelledSessionDoesNotEnterNewSession() async throws {
        let oldEngine = FakeASREngine()
        let newEngine = FakeASREngine()
        let audioRecorder = FakeAudioRecorder()
        let pipeline = FakeTextPipeline(result: TextProcessingResult(rawText: "", finalText: "processed"))
        let injector = FakeTextInjector()
        let history = CapturingHistoryRepository()
        let orchestrator = DictationOrchestrator(
            asrEngineFactory: QueuedASREngineFactory(engines: [oldEngine, newEngine]),
            audioRecorder: audioRecorder,
            textPipeline: pipeline,
            textInjector: injector,
            historyRepository: history
        )

        try orchestrator.start(configuration: .appleChinese)
        orchestrator.cancel()
        try orchestrator.start(configuration: .appleChinese)
        orchestrator.release()
        oldEngine.emit(text: "old final", isFinal: true)
        newEngine.emit(text: "new final", isFinal: true)
        await drainMainActorTasks()

        XCTAssertEqual(injector.injectedTexts, ["processed"])
        XCTAssertEqual(history.savedEntries.map(\.rawText), ["new final"])
    }

    func testReleaseStopsDrainsAndFlushesAudioBeforeEndingASR() throws {
        let order = CallOrderProbe()
        let engine = FakeASREngine(order: order)
        let audioRecorder = FakeAudioRecorder(order: order)
        let audioFrameForwarder = FakeAudioFrameForwarder(order: order)
        let orchestrator = DictationOrchestrator(
            asrEngineFactory: FakeASREngineFactory(engine: engine),
            audioRecorder: audioRecorder,
            audioBufferForwarder: audioFrameForwarder,
            textPipeline: FakeTextPipeline(
                result: TextProcessingResult(rawText: "", finalText: "")
            ),
            textInjector: FakeTextInjector(),
            historyRepository: CapturingHistoryRepository()
        )

        try orchestrator.start(configuration: .appleChinese)
        orchestrator.release()

        XCTAssertEqual(order.events, [
            "recorder.stop",
            "recorder.drain",
            "forwarder.finish",
            "engine.endAudio",
        ])
    }

    func testQuickReleaseKeepsDrainedBufferAndConverterTailBeforeEndAudio() throws {
        let converter = DictationAudioPCMConverter(
            convertedSamples: [[0.8]],
            tailSamples: [0.9]
        )
        let audioFrameForwarder = ASREngineAudioFrameForwarder(
            makeConverter: { converter }
        )
        let engine = FakeASREngine()
        let audioRecorder = FakeAudioRecorder()
        let buffer = try makePCMBuffer(sampleCount: 1)
        var orchestrator: DictationOrchestrator!
        audioRecorder.onDrain = {
            orchestrator.appendAudioBuffer(buffer)
        }
        orchestrator = DictationOrchestrator(
            asrEngineFactory: FakeASREngineFactory(engine: engine),
            audioRecorder: audioRecorder,
            audioBufferForwarder: audioFrameForwarder,
            textPipeline: FakeTextPipeline(
                result: TextProcessingResult(rawText: "", finalText: "")
            ),
            textInjector: FakeTextInjector(),
            historyRepository: CapturingHistoryRepository()
        )

        try orchestrator.start(configuration: .appleChinese)
        orchestrator.release()

        XCTAssertEqual(engine.appendedFrames.map(\.samples), [
            ContiguousArray([0.8]),
            ContiguousArray([0.9]),
        ])
        XCTAssertEqual(engine.endAudioFrameCount, 2)
    }

    func testCancelStopsAudioAndEngineWithoutInjection() throws {
        let engine = FakeASREngine()
        let audioRecorder = FakeAudioRecorder()
        let injector = FakeTextInjector()
        let history = CapturingHistoryRepository()
        let orchestrator = makeOrchestrator(
            engine: engine,
            audioRecorder: audioRecorder,
            injector: injector,
            history: history
        )

        try orchestrator.start(configuration: .appleChinese)
        orchestrator.cancel()

        XCTAssertFalse(audioRecorder.isRecording)
        XCTAssertTrue(engine.didCancel)
        XCTAssertEqual(injector.injectedTexts, [])
        XCTAssertEqual(history.savedEntries, [])
        XCTAssertEqual(orchestrator.state, .idle)
    }

    func testEscapeCancellationDuringProcessingPreventsLateInjection() async throws {
        let engine = FakeASREngine()
        let pipeline = SuspendedTextPipeline()
        let injector = FakeTextInjector()
        let history = CapturingHistoryRepository()
        let orchestrator = makeOrchestrator(
            engine: engine,
            pipeline: pipeline,
            injector: injector,
            history: history
        )

        try orchestrator.start(configuration: .appleChinese)
        orchestrator.release()
        engine.emit(text: "raw", isFinal: true)
        await drainMainActorTasks()

        XCTAssertEqual(orchestrator.state, .processing)
        XCTAssertTrue(pipeline.hasStarted)

        orchestrator.cancel()
        pipeline.complete(finalText: "late result")
        await drainMainActorTasks()

        XCTAssertEqual(orchestrator.state, .idle)
        XCTAssertTrue(engine.didCancel)
        XCTAssertEqual(injector.injectedTexts, [])
        XCTAssertEqual(history.savedEntries, [])
    }

    func testFinishWithoutTextCorrectionCancelsLLMAndImmediatelyInjectsRawText() async throws {
        let engine = FakeASREngine()
        let pipeline = SuspendedTextPipeline()
        let injector = FakeTextInjector()
        let history = CapturingHistoryRepository()
        let orchestrator = makeOrchestrator(
            engine: engine,
            pipeline: pipeline,
            injector: injector,
            history: history
        )

        try orchestrator.start(configuration: .appleChinese)
        orchestrator.release()
        engine.emit(text: "ASR 原文", isFinal: true)
        await drainMainActorTasks()
        XCTAssertEqual(orchestrator.state, .processing)

        orchestrator.finishWithoutTextCorrection()
        await drainMainActorTasks()

        XCTAssertEqual(injector.injectedTexts, ["ASR 原文"])
        XCTAssertEqual(history.savedEntries.first?.rawText, "ASR 原文")
        XCTAssertEqual(history.savedEntries.first?.finalText, "ASR 原文")
        XCTAssertEqual(orchestrator.state, .idle)

        pipeline.complete(finalText: "迟到的纠错结果")
        await drainMainActorTasks()
        XCTAssertEqual(injector.injectedTexts, ["ASR 原文"])
    }

    func testEscapeDuringTextCorrectionInjectsRawTextInsteadOfCancelling() async throws {
        let engine = FakeASREngine()
        let pipeline = SuspendedTextPipeline()
        let injector = FakeTextInjector()
        let history = CapturingHistoryRepository()
        let orchestrator = makeOrchestrator(
            engine: engine,
            pipeline: pipeline,
            injector: injector,
            history: history
        )

        try orchestrator.start(configuration: .appleChinese)
        orchestrator.release()
        engine.emit(text: "纠错前原文", isFinal: true)
        await drainMainActorTasks()
        XCTAssertEqual(orchestrator.state, .processing)

        XCTAssertTrue(orchestrator.handleEscapeKey())
        await drainMainActorTasks()

        XCTAssertFalse(engine.didCancel)
        XCTAssertEqual(injector.injectedTexts, ["纠错前原文"])
        XCTAssertEqual(history.savedEntries.first?.rawText, "纠错前原文")
        XCTAssertEqual(history.savedEntries.first?.finalText, "纠错前原文")
        XCTAssertEqual(orchestrator.state, .idle)
    }

    func testEscapeWhileWaitingForFinalWithVisibleTranscriptInjectsRawTextInsteadOfCancelling() async throws {
        let engine = FakeASREngine()
        let injector = FakeTextInjector()
        let history = CapturingHistoryRepository()
        let clock = CapturingSleepClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let orchestrator = makeOrchestrator(
            engine: engine,
            injector: injector,
            history: history,
            clock: clock,
            finalTimeoutNanoseconds: 1
        )

        try orchestrator.start(configuration: .appleChinese)
        engine.emit(text: "截图里看到的原文", isFinal: false)
        orchestrator.release()
        let scheduledTimeout = await waitUntil(timeout: 1.0) {
            clock.requestedNanoseconds != nil
        }
        XCTAssertTrue(scheduledTimeout)
        XCTAssertEqual(orchestrator.state, .waitingForFinal)

        XCTAssertTrue(orchestrator.handleEscapeKey())
        await drainMainActorTasks()

        XCTAssertFalse(engine.didCancel)
        XCTAssertEqual(injector.injectedTexts, ["截图里看到的原文"])
        XCTAssertEqual(history.savedEntries.first?.rawText, "截图里看到的原文")
        XCTAssertEqual(history.savedEntries.first?.finalText, "截图里看到的原文")
        XCTAssertEqual(orchestrator.state, .idle)
    }

    func testEscapeBeforeTextCorrectionStillCancelsWithoutInjection() throws {
        let engine = FakeASREngine()
        let injector = FakeTextInjector()
        let history = CapturingHistoryRepository()
        let orchestrator = makeOrchestrator(
            engine: engine,
            injector: injector,
            history: history
        )

        try orchestrator.start(configuration: .appleChinese)

        XCTAssertFalse(orchestrator.handleEscapeKey())

        XCTAssertTrue(engine.didCancel)
        XCTAssertEqual(injector.injectedTexts, [])
        XCTAssertEqual(history.savedEntries, [])
        XCTAssertEqual(orchestrator.state, .idle)
    }

    func testTargetApplicationIsCapturedWhenDictationStarts() async throws {
        let engine = FakeASREngine()
        let pipeline = FakeTextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "final")
        )
        let targetProvider = MutableTargetProvider(
            target: DictationTarget(bundleID: "com.apple.dt.Xcode", appName: "Xcode")
        )
        let orchestrator = DictationOrchestrator(
            asrEngineFactory: FakeASREngineFactory(engine: engine),
            audioRecorder: FakeAudioRecorder(),
            textPipeline: pipeline,
            textInjector: FakeTextInjector(),
            historyRepository: CapturingHistoryRepository(),
            targetProvider: targetProvider
        )

        try orchestrator.start(configuration: .appleChinese)
        targetProvider.target = DictationTarget(bundleID: "com.voxflow.app", appName: "VoxFlow")
        orchestrator.release()
        engine.emit(text: "raw", isFinal: true)
        await drainMainActorTasks()

        XCTAssertEqual(pipeline.targets, [
            DictationTarget(bundleID: "com.apple.dt.Xcode", appName: "Xcode")
        ])
    }

    func testTargetApplicationChangeCopiesFinalTextWithoutInjection() async throws {
        let engine = FakeASREngine()
        let audioRecorder = FakeAudioRecorder()
        let pipeline = FakeTextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "final")
        )
        let injector = FakeTextInjector()
        let clipboard = FakeClipboardService()
        let history = CapturingHistoryRepository()
        let targetProvider = MutableTargetProvider(
            target: DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        )
        let orchestrator = DictationOrchestrator(
            asrEngineFactory: FakeASREngineFactory(engine: engine),
            audioRecorder: audioRecorder,
            textPipeline: pipeline,
            textInjector: injector,
            historyRepository: history,
            targetProvider: targetProvider,
            clipboardService: clipboard
        )

        try orchestrator.start(configuration: .appleChinese)
        targetProvider.target = DictationTarget(bundleID: "com.apple.Safari", appName: "Safari")
        orchestrator.release()
        engine.emit(text: "raw", isFinal: true)
        await drainMainActorTasks()

        XCTAssertEqual(injector.injectedTexts, [])
        XCTAssertEqual(clipboard.copiedTexts, ["final"])
        XCTAssertEqual(history.savedEntries.first?.finalText, "final")
        XCTAssertEqual(orchestrator.state, .idle)
    }

    func testDictationDeliversFinalTextThroughOutputService() async throws {
        let engine = FakeASREngine()
        let pipeline = FakeTextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "final")
        )
        let injector = FakeTextInjector()
        let clipboard = FakeClipboardService()
        let outputService = CapturingOutputService(result: .injected)
        let history = CapturingHistoryRepository()
        let originalTarget = DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        let currentTarget = DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        let targetProvider = MutableTargetProvider(target: originalTarget)
        let orchestrator = DictationOrchestrator(
            asrEngineFactory: FakeASREngineFactory(engine: engine),
            audioRecorder: FakeAudioRecorder(),
            textPipeline: pipeline,
            textInjector: injector,
            historyRepository: history,
            targetProvider: targetProvider,
            clipboardService: clipboard,
            outputService: outputService
        )

        try orchestrator.start(configuration: .appleChinese)
        targetProvider.target = currentTarget
        orchestrator.release()
        engine.emit(text: "raw", isFinal: true)
        await drainMainActorTasks()

        XCTAssertEqual(outputService.deliveries, [
            CapturingOutputService.Delivery(
                text: "final",
                mode: .dictation,
                target: currentTarget,
                originalTarget: originalTarget
            )
        ])
        XCTAssertTrue(injector.injectedTexts.isEmpty)
        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
        let traceJSON = try XCTUnwrap(history.savedEntries.first?.processingTraceJSON)
        let trace = try JSONDecoder().decode(TextProcessingTrace.self, from: Data(traceJSON.utf8))
        XCTAssertEqual(trace.output?.resultKind, OutputResultKind.inserted.rawValue)
        XCTAssertEqual(orchestrator.state, .idle)
    }

    func testCancelledDictationOutputDoesNotSaveFinalTextToHistory() async throws {
        let engine = FakeASREngine()
        let pipeline = FakeTextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "final")
        )
        let outputService = CapturingOutputService(result: .cancelled)
        let history = CapturingHistoryRepository()
        let orchestrator = DictationOrchestrator(
            asrEngineFactory: FakeASREngineFactory(engine: engine),
            audioRecorder: FakeAudioRecorder(),
            textPipeline: pipeline,
            textInjector: FakeTextInjector(),
            historyRepository: history,
            outputService: outputService
        )

        try orchestrator.start(configuration: .appleChinese)
        orchestrator.release()
        engine.emit(text: "raw", isFinal: true)
        await drainMainActorTasks()

        XCTAssertEqual(outputService.deliveries.map(\.text), ["final"])
        XCTAssertTrue(history.savedEntries.isEmpty)
        XCTAssertEqual(orchestrator.state, .idle)
    }

    func testSuccessfulInjectedDictationSchedulesCorrectionObservation() async throws {
        let engine = FakeASREngine()
        let event = CorrectionEvent(
            ruleID: UUID(),
            original: "q 问",
            replacement: "Qwen",
            range: CorrectionTextRange(location: 0, length: 4),
            scope: .global,
            source: .manual
        )
        let pipeline = FakeTextPipeline(
            result: TextProcessingResult(
                rawText: "raw",
                finalText: "Qwen",
                correctionEvents: [event]
            )
        )
        let observer = CapturingCorrectionObservationScheduler()
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        let orchestrator = makeOrchestrator(
            engine: engine,
            pipeline: pipeline,
            targetProvider: StaticDictationTargetProvider(target: target),
            correctionObservationScheduler: observer
        )

        try orchestrator.start(configuration: .appleChinese)
        orchestrator.release()
        engine.emit(text: "raw", isFinal: true)
        await drainMainActorTasks()

        XCTAssertEqual(observer.observations.map(\.insertedText), ["Qwen"])
        XCTAssertEqual(observer.observations.first?.context.bundleIdentifier, "com.example.editor")
        XCTAssertEqual(observer.observations.first?.context.isSecureField, false)
        XCTAssertEqual(observer.observations.first?.appliedEvents, [event])
    }

    func testOCRContextBoostDoesNotSkipCorrectionObservation() async throws {
        let engine = FakeASREngine()
        let pipeline = FakeTextPipeline(
            result: TextProcessingResult(
                rawText: "raw",
                finalText: "Qwen3-ASR",
                trace: TextProcessingTrace(
                    contextBoost: ContextBoostTrace(
                        appName: "Editor",
                        bundleID: "com.example.editor",
                        hotwords: ["Qwen3-ASR"],
                        source: "current_window_ocr",
                        ttlSeconds: 120,
                        appliedToLLMPrompt: true,
                        failureReason: nil
                    )
                )
            )
        )
        let observer = CapturingCorrectionObservationScheduler()
        let orchestrator = makeOrchestrator(
            engine: engine,
            pipeline: pipeline,
            targetProvider: StaticDictationTargetProvider(
                target: DictationTarget(bundleID: "com.example.editor", appName: "Editor")
            ),
            correctionObservationScheduler: observer
        )

        try orchestrator.start(configuration: .appleChinese)
        orchestrator.release()
        engine.emit(text: "raw", isFinal: true)
        await drainMainActorTasks()

        XCTAssertEqual(observer.observations.map(\.insertedText), ["Qwen3-ASR"])
        XCTAssertEqual(observer.observations.first?.context.bundleIdentifier, "com.example.editor")
    }

    func testContextBoostLLMChangeSkipsCorrectionObservation() async throws {
        let engine = FakeASREngine()
        let pipeline = FakeTextPipeline(
            result: TextProcessingResult(
                rawText: "raw",
                finalText: "Qwen3-ASR",
                trace: TextProcessingTrace(
                    llm: Self.trace(),
                    contextBoost: ContextBoostTrace(
                        appName: "Editor",
                        bundleID: "com.example.editor",
                        hotwords: ["Qwen3-ASR"],
                        source: "current_window_ocr",
                        ttlSeconds: 120,
                        appliedToLLMPrompt: true,
                        failureReason: nil
                    )
                )
            )
        )
        let observer = CapturingCorrectionObservationScheduler()
        let orchestrator = makeOrchestrator(
            engine: engine,
            pipeline: pipeline,
            targetProvider: StaticDictationTargetProvider(
                target: DictationTarget(bundleID: "com.example.editor", appName: "Editor")
            ),
            correctionObservationScheduler: observer
        )

        try orchestrator.start(configuration: .appleChinese)
        orchestrator.release()
        engine.emit(text: "raw", isFinal: true)
        await drainMainActorTasks()

        XCTAssertTrue(observer.observations.isEmpty)
    }

    func testSuccessfulLLMChangeSkipsCorrectionObservation() async throws {
        let engine = FakeASREngine()
        let pipeline = FakeTextPipeline(
            result: TextProcessingResult(
                rawText: "raw",
                finalText: "refined text",
                trace: TextProcessingTrace(llm: Self.trace(responseText: "refined text"))
            )
        )
        let observer = CapturingCorrectionObservationScheduler()
        let orchestrator = makeOrchestrator(
            engine: engine,
            pipeline: pipeline,
            targetProvider: StaticDictationTargetProvider(
                target: DictationTarget(bundleID: "com.example.editor", appName: "Editor")
            ),
            correctionObservationScheduler: observer
        )

        try orchestrator.start(configuration: .appleChinese)
        orchestrator.release()
        engine.emit(text: "raw", isFinal: true)
        await drainMainActorTasks()

        XCTAssertTrue(observer.observations.isEmpty)
    }

    func testSecureDictationSkipsCorrectionObservationAndMarksCorrectionContextSecure() async throws {
        let engine = FakeASREngine()
        let pipeline = CapturingDictationContextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "raw")
        )
        let observer = CapturingCorrectionObservationScheduler()
        let orchestrator = makeOrchestrator(
            engine: engine,
            pipeline: pipeline,
            correctionObservationScheduler: observer,
            isFocusedTextFieldSecure: { true }
        )

        try orchestrator.start(configuration: .appleChinese)
        orchestrator.release()
        engine.emit(text: "raw", isFinal: true)
        await drainMainActorTasks()

        XCTAssertEqual(pipeline.capturedContexts.map(\.isSecureField), [true])
        XCTAssertTrue(observer.observations.isEmpty)
    }

    func testSecureDictationDoesNotPrepareContextBoost() throws {
        let pipeline = FakeTextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "raw")
        )
        let orchestrator = makeOrchestrator(
            pipeline: pipeline,
            isFocusedTextFieldSecure: { true }
        )

        try orchestrator.start(configuration: .appleChinese)

        XCTAssertTrue(pipeline.preparedTargets.isEmpty)
    }

    func testAgentComposeUsesRecordingStateAndDelegatesFinalTranscript() async throws {
        let engine = FakeASREngine()
        let audioRecorder = FakeAudioRecorder()
        let injector = FakeTextInjector()
        let history = CapturingHistoryRepository()
        let agentHandler = FakeAgentComposeHandler(result: .copied)
        let target = DictationTarget(bundleID: "com.tencent.xinWeChat", appName: "微信")
        let orchestrator = DictationOrchestrator(
            asrEngineFactory: FakeASREngineFactory(engine: engine),
            audioRecorder: audioRecorder,
            textPipeline: FakeTextPipeline(
                result: TextProcessingResult(rawText: "", finalText: "")
            ),
            textInjector: injector,
            historyRepository: history,
            targetProvider: StaticDictationTargetProvider(target: target),
            agentComposeHandler: agentHandler
        )
        var states: [DictationState] = []
        orchestrator.onStateChange = { states.append($0) }

        try orchestrator.start(configuration: .appleChinese, mode: .agentCompose)

        XCTAssertEqual(orchestrator.state, .recording)
        XCTAssertEqual(agentHandler.startedTarget, target)

        orchestrator.release()
        engine.emit(text: "帮我回复今晚可以", isFinal: true)
        await drainMainActorTasks()

        XCTAssertEqual(agentHandler.finishedTranscript, "帮我回复今晚可以")
        XCTAssertEqual(injector.injectedTexts, [])
        XCTAssertEqual(history.savedEntries, [])
        XCTAssertTrue(states.contains(.recording))
        XCTAssertTrue(states.contains(.processing))
        XCTAssertEqual(orchestrator.state, .idle)
    }

    func testAgentDispatchFallbackInputDeliversThroughDictationOutput() async throws {
        let engine = FakeASREngine()
        let pipeline = FakeTextPipeline(
            result: TextProcessingResult(rawText: "检查一下按钮", finalText: "检查一下按钮。")
        )
        let outputService = CapturingOutputService(result: .injected)
        let history = CapturingHistoryRepository()
        let originalTarget = DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        let currentTarget = DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        let targetProvider = MutableTargetProvider(target: originalTarget)
        let agentHandler = FakeAgentDispatchHandler(
            presentation: .fallbackInput(text: "检查一下按钮")
        )
        agentHandler.emitsPresentationOnFinish = false
        let orchestrator = DictationOrchestrator(
            asrEngineFactory: FakeASREngineFactory(engine: engine),
            audioRecorder: FakeAudioRecorder(),
            textPipeline: pipeline,
            textInjector: FakeTextInjector(),
            historyRepository: history,
            targetProvider: targetProvider,
            outputService: outputService,
            agentDispatchHandler: agentHandler
        )
        var agentDispatchPresentations: [AgentDispatchHUDPresentation] = []
        orchestrator.onAgentDispatchPresentation = {
            agentDispatchPresentations.append($0)
        }

        try orchestrator.start(configuration: .appleChinese, mode: .agentDispatch)
        targetProvider.target = currentTarget
        orchestrator.release()
        engine.emit(text: "检查一下按钮", isFinal: true)
        await drainMainActorTasks()

        XCTAssertEqual(agentHandler.finishedTranscript, "检查一下按钮")
        XCTAssertEqual(outputService.deliveries, [
            CapturingOutputService.Delivery(
                text: "检查一下按钮。",
                mode: .dictation,
                target: currentTarget,
                originalTarget: originalTarget
            ),
        ])
        XCTAssertTrue(history.savedEntries.isEmpty)
        XCTAssertEqual(orchestrator.state, .idle)
        XCTAssertEqual(agentDispatchPresentations, [.fallbackInput(text: "检查一下按钮。")])
    }

    func testEscapeDuringAgentDispatchFallbackCorrectionInjectsFallbackRawText() async throws {
        let engine = FakeASREngine()
        let pipeline = SuspendedTextPipeline()
        let outputService = CapturingOutputService(result: .injected)
        let history = CapturingHistoryRepository()
        let originalTarget = DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        let currentTarget = DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        let targetProvider = MutableTargetProvider(target: originalTarget)
        let agentHandler = FakeAgentDispatchHandler(
            presentation: .fallbackInput(text: "检查一下按钮")
        )
        agentHandler.emitsPresentationOnFinish = false
        let orchestrator = DictationOrchestrator(
            asrEngineFactory: FakeASREngineFactory(engine: engine),
            audioRecorder: FakeAudioRecorder(),
            textPipeline: pipeline,
            textInjector: FakeTextInjector(),
            historyRepository: history,
            targetProvider: targetProvider,
            outputService: outputService,
            agentDispatchHandler: agentHandler
        )
        var agentDispatchPresentations: [AgentDispatchHUDPresentation] = []
        orchestrator.onAgentDispatchPresentation = {
            agentDispatchPresentations.append($0)
        }

        try orchestrator.start(configuration: .appleChinese, mode: .agentDispatch)
        targetProvider.target = currentTarget
        orchestrator.release()
        engine.emit(text: "检查一下按钮", isFinal: true)
        let startedCorrection = await waitUntil(timeout: 1.0) {
            pipeline.hasStarted && orchestrator.state == .processing
        }
        XCTAssertTrue(startedCorrection)

        XCTAssertTrue(orchestrator.handleEscapeKey())
        await drainMainActorTasks()

        XCTAssertFalse(engine.didCancel)
        XCTAssertEqual(outputService.deliveries, [
            CapturingOutputService.Delivery(
                text: "检查一下按钮",
                mode: .dictation,
                target: currentTarget,
                originalTarget: originalTarget
            ),
        ])
        XCTAssertEqual(agentHandler.completedFallback?.finalText, "检查一下按钮")
        XCTAssertEqual(agentHandler.completedFallback?.outputResult, .injected)
        XCTAssertEqual(history.savedEntries, [])
        XCTAssertEqual(orchestrator.state, .idle)
        XCTAssertEqual(agentDispatchPresentations, [.fallbackInput(text: "检查一下按钮")])
    }

    func testAgentComposeStartPassesASRMetadataToHandler() throws {
        let engine = FakeASREngine()
        let agentHandler = FakeAgentComposeHandler(result: .copied)
        let orchestrator = DictationOrchestrator(
            asrEngineFactory: FakeASREngineFactory(engine: engine),
            audioRecorder: FakeAudioRecorder(),
            textPipeline: FakeTextPipeline(
                result: TextProcessingResult(rawText: "", finalText: "")
            ),
            textInjector: FakeTextInjector(),
            historyRepository: CapturingHistoryRepository(),
            agentComposeHandler: agentHandler
        )

        try orchestrator.start(configuration: .qwenEnglish, mode: .agentCompose)

        XCTAssertEqual(agentHandler.startedASRMetadata?.providerID, "qwen3_asr")
        XCTAssertEqual(agentHandler.startedASRMetadata?.modelID, "qwen3-asr-0.6b-mlx-4bit")
        XCTAssertEqual(agentHandler.startedASRMetadata?.modelVersion, "bc441bd1e4295c1f42d9879f056049a925b6e013")
        XCTAssertEqual(agentHandler.startedASRMetadata?.language, "en-US")
        XCTAssertNil(agentHandler.startedASRMetadata?.sessionID)
    }

    func testAgentComposeCancelledResultDoesNotEmitCompletionResult() async throws {
        let engine = FakeASREngine()
        let agentHandler = FakeAgentComposeHandler(result: .cancelled)
        let orchestrator = DictationOrchestrator(
            asrEngineFactory: FakeASREngineFactory(engine: engine),
            audioRecorder: FakeAudioRecorder(),
            textPipeline: FakeTextPipeline(
                result: TextProcessingResult(rawText: "", finalText: "")
            ),
            textInjector: FakeTextInjector(),
            historyRepository: CapturingHistoryRepository(),
            agentComposeHandler: agentHandler
        )
        var completionResults: [OutputResult] = []
        orchestrator.onAgentComposeCompleted = { result in
            completionResults.append(result)
        }

        try orchestrator.start(configuration: .appleChinese, mode: .agentCompose)
        orchestrator.release()
        engine.emit(text: "取消这次生成", isFinal: true)
        await drainMainActorTasks()

        XCTAssertTrue(completionResults.isEmpty)
        XCTAssertEqual(orchestrator.state, .idle)
    }

    func testAgentComposeUpdatesASRMetadataFromRuntimeSnapshotBeforeFinish() async throws {
        let engine = FakeASREngine()
        engine.asrRuntimeMetadataSnapshot = ASRRuntimeMetadataSnapshot(
            sessionID: "runtime-session",
            audioDurationMs: 1_250,
            finalLatencyMs: 430,
            droppedFrameCount: 2,
            errorCode: nil
        )
        let agentHandler = FakeAgentComposeHandler(result: .copied)
        let orchestrator = DictationOrchestrator(
            asrEngineFactory: FakeASREngineFactory(engine: engine),
            audioRecorder: FakeAudioRecorder(),
            textPipeline: FakeTextPipeline(
                result: TextProcessingResult(rawText: "", finalText: "")
            ),
            textInjector: FakeTextInjector(),
            historyRepository: CapturingHistoryRepository(),
            agentComposeHandler: agentHandler
        )

        try orchestrator.start(configuration: .qwenEnglish, mode: .agentCompose)
        orchestrator.release()
        engine.emit(text: "帮我写一段回复", isFinal: true)
        await drainMainActorTasks()

        XCTAssertEqual(agentHandler.updatedASRMetadata?.providerID, "qwen3_asr")
        XCTAssertEqual(agentHandler.updatedASRMetadata?.modelID, "qwen3-asr-0.6b-mlx-4bit")
        XCTAssertEqual(agentHandler.updatedASRMetadata?.modelVersion, "bc441bd1e4295c1f42d9879f056049a925b6e013")
        XCTAssertEqual(agentHandler.updatedASRMetadata?.language, "en-US")
        XCTAssertEqual(agentHandler.updatedASRMetadata?.sessionID, "runtime-session")
        XCTAssertEqual(agentHandler.updatedASRMetadata?.audioDurationMs, 1_250)
        XCTAssertEqual(agentHandler.updatedASRMetadata?.finalLatencyMs, 430)
        XCTAssertEqual(agentHandler.updatedASRMetadata?.droppedFrameCount, 2)
    }

    func testTextCorrectionStreamingUpdateAfterCancelDoesNotUpdateHUD() async throws {
        let engine = FakeASREngine()
        let pipeline = CancellingRefinementPipeline(finalText: "stale corrected text")
        var orchestrator: DictationOrchestrator!
        orchestrator = DictationOrchestrator(
            asrEngineFactory: FakeASREngineFactory(engine: engine),
            audioRecorder: FakeAudioRecorder(),
            textPipeline: pipeline,
            textInjector: FakeTextInjector(),
            historyRepository: CapturingHistoryRepository()
        )
        pipeline.onBeforeRefinedTextUpdate = {
            orchestrator.cancel()
        }
        var transcriptionUpdates: [(text: String, isRefining: Bool)] = []
        orchestrator.onTranscriptionUpdate = { text, isRefining in
            transcriptionUpdates.append((text, isRefining))
        }

        try orchestrator.start(configuration: .appleChinese)
        orchestrator.release()
        engine.emit(text: "原始文本", isFinal: true)
        await drainMainActorTasks()

        XCTAssertEqual(transcriptionUpdates.map(\.text), ["原始文本"])
        XCTAssertEqual(transcriptionUpdates.map(\.isRefining), [false])
        XCTAssertEqual(orchestrator.state, .idle)
    }

    private func makeOrchestrator(
        engine: FakeASREngine = FakeASREngine(),
        audioRecorder: FakeAudioRecorder = FakeAudioRecorder(),
        pipeline: any TextProcessing = FakeTextPipeline(
            result: TextProcessingResult(rawText: "", finalText: "")
        ),
        injector: FakeTextInjector = FakeTextInjector(),
        history: CapturingHistoryRepository = CapturingHistoryRepository(),
        clock: any AppClock = MutableClock(now: Date(timeIntervalSince1970: 1_800_000_000)),
        agentComposeHandler: (any AgentComposeHandling)? = nil,
        audioCaptureCoordinator: any AudioCaptureCoordinating = AudioCaptureCoordinator(),
        finalTimeoutNanoseconds: UInt64 = 15_000_000_000,
        targetProvider: any DictationTargetProviding = StaticDictationTargetProvider(
            target: DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        ),
        correctionObservationScheduler: (any CorrectionObservationScheduling)? = nil,
        isFocusedTextFieldSecure: @escaping @MainActor () -> Bool = { false },
        assetRepository: (any AssetRepository)? = nil
    ) -> DictationOrchestrator {
        DictationOrchestrator(
            asrEngineFactory: FakeASREngineFactory(engine: engine),
            audioRecorder: audioRecorder,
            textPipeline: pipeline,
            textInjector: injector,
            historyRepository: history,
            clock: clock,
            targetProvider: targetProvider,
            agentComposeHandler: agentComposeHandler,
            audioCaptureCoordinator: audioCaptureCoordinator,
            correctionObservationScheduler: correctionObservationScheduler,
            isFocusedTextFieldSecure: isFocusedTextFieldSecure,
            finalTimeoutNanoseconds: finalTimeoutNanoseconds,
            assetRepository: assetRepository
        )
    }

    private func drainMainActorTasks() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    private static func trace(responseText: String = "Qwen3-ASR") -> LLMRefinementTrace {
        LLMRefinementTrace(
            providerID: "provider",
            providerName: "Provider",
            endpoint: "https://api.example.com/v1/chat/completions",
            model: "gpt-test",
            temperature: 0.0,
            timeoutSeconds: 8,
            requestBodyJSON: "{}",
            responseText: responseText,
            statusCode: 200,
            durationMS: 12,
            errorMessage: nil,
            completedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func waitUntil(
        timeout: TimeInterval,
        pollInterval: UInt64 = 10_000_000,
        condition: @escaping () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollInterval)
        }
        return await condition()
    }

    private enum TestError: Error {
        case expected
    }

    private func makePCMBuffer(sampleCount: Int) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(
            standardFormatWithSampleRate: 48_000,
            channels: 1
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ))
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        return buffer
    }
}

private extension DictationConfiguration {
    static let appleChinese = DictationConfiguration(
        engineType: .apple,
        locale: Locale(identifier: "zh-CN"),
        languageIdentifier: "zh-CN"
    )

    static let appleJapanese = DictationConfiguration(
        engineType: .apple,
        locale: Locale(identifier: "ja-JP"),
        languageIdentifier: "ja-JP"
    )

    static let qwenEnglish = DictationConfiguration(
        engineType: .qwen3,
        locale: Locale(identifier: "en-US"),
        languageIdentifier: "en-US",
        modelID: "qwen3-asr-0.6b-mlx-4bit",
        modelVersion: "bc441bd1e4295c1f42d9879f056049a925b6e013"
    )

    static let paraformerChinese = DictationConfiguration(
        engineType: .paraformer,
        locale: Locale(identifier: "zh-CN"),
        languageIdentifier: "zh-CN",
        modelID: "paraformer-large-zh-int8",
        modelVersion: "test"
    )
}

private final class FakeASREngineFactory: ASREngineFactory {
    let engine: FakeASREngine

    init(engine: FakeASREngine) {
        self.engine = engine
    }

    func makeEngine(type: ASREngineType) -> ASREngine {
        engine
    }
}

private final class QueuedASREngineFactory: ASREngineFactory {
    private var engines: [FakeASREngine]

    init(engines: [FakeASREngine]) {
        self.engines = engines
    }

    func makeEngine(type: ASREngineType) -> ASREngine {
        engines.removeFirst()
    }
}

private final class ObservingEngineFactory: ASREngineFactory {
    let engine: FakeASREngine
    let onMakeEngine: () -> Void

    init(engine: FakeASREngine, onMakeEngine: @escaping () -> Void) {
        self.engine = engine
        self.onMakeEngine = onMakeEngine
    }

    func makeEngine(type: ASREngineType) -> ASREngine {
        onMakeEngine()
        return engine
    }
}

private final class FakeASREngine: ASREngine, ASRRuntimeMetadataProviding {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?
    var onStart: (() -> Void)?
    var asrRuntimeMetadataSnapshot = ASRRuntimeMetadataSnapshot()
    private(set) var isAvailable = true
    private(set) var didStart = false
    private(set) var didStop = false
    private(set) var didCancel = false
    private(set) var didEndAudio = false
    private(set) var appendedFrames: [AudioFrame] = []
    private(set) var endAudioFrameCount = 0
    private let order: CallOrderProbe?

    init(order: CallOrderProbe? = nil) {
        self.order = order
    }

    func configure(locale: Locale) {}

    func start() throws {
        onStart?()
        didStart = true
    }

    func appendAudioFrame(_ frame: AudioFrame) {
        appendedFrames.append(frame)
    }

    func endAudio() {
        didEndAudio = true
        endAudioFrameCount = appendedFrames.count
        order?.append("engine.endAudio")
    }

    func stop() {
        didStop = true
    }

    func cancel() {
        didCancel = true
    }

    func emit(text: String, isFinal: Bool) {
        onTranscription?(text, isFinal)
    }

    func fail(_ error: Error) {
        onError?(error)
    }
}

private final class FakeAudioRecorder: AudioRecording {
    private(set) var isRecording = false
    var startError: Error?
    var onDrain: (() -> Void)?
    private let order: CallOrderProbe?

    init(order: CallOrderProbe? = nil) {
        self.order = order
    }

    func start() throws {
        if let startError {
            throw startError
        }
        isRecording = true
    }

    func stop() {
        isRecording = false
        order?.append("recorder.stop")
    }

    func drain() {
        order?.append("recorder.drain")
        onDrain?()
    }
}

private final class FakeAudioFrameForwarder: ASREngineAudioFrameForwarding {
    private let order: CallOrderProbe

    init(order: CallOrderProbe) {
        self.order = order
    }

    func attach(_ engine: ASREngine) {}

    func detach() {}

    func appendAudioFrame(_ frame: AudioFrame) {}

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {}

    func finish() {
        order.append("forwarder.finish")
    }
}

private final class CallOrderProbe: @unchecked Sendable {
    private(set) var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }
}

private final class DictationAudioPCMConverter: AudioPCMConverting, @unchecked Sendable {
    let targetSampleRate: Double
    private var convertedSamples: [ContiguousArray<Float>]
    private let tailSamples: ContiguousArray<Float>

    init(
        convertedSamples: [[Float]],
        tailSamples: [Float] = [],
        targetSampleRate: Double = 16_000
    ) {
        self.convertedSamples = convertedSamples.map(ContiguousArray.init)
        self.tailSamples = ContiguousArray(tailSamples)
        self.targetSampleRate = targetSampleRate
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> ContiguousArray<Float> {
        if convertedSamples.isEmpty {
            return []
        }
        return convertedSamples.removeFirst()
    }

    func finish() throws -> ContiguousArray<Float> {
        tailSamples
    }
}

@MainActor
private final class SuspendedTextPipeline: TextProcessing {
    private var continuation: CheckedContinuation<TextProcessingResult, Never>?
    private(set) var hasStarted = false

    func process(_ rawText: String) async -> TextProcessingResult {
        hasStarted = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func process(
        _ rawText: String,
        target: DictationTarget?,
        onRefinedTextUpdate: @escaping @MainActor (String) -> Void
    ) async -> TextProcessingResult {
        await process(rawText)
    }

    func complete(finalText: String) {
        continuation?.resume(
            returning: TextProcessingResult(rawText: "raw", finalText: finalText)
        )
        continuation = nil
    }
}

@MainActor
private final class FakeTextPipeline: TextProcessing {
    let result: TextProcessingResult
    private(set) var targets: [DictationTarget?] = []
    private(set) var preparedTargets: [DictationTarget?] = []
    private(set) var cancelContextBoostCallCount = 0

    init(result: TextProcessingResult) {
        self.result = result
    }

    func prepareContextBoost(target: DictationTarget?) {
        preparedTargets.append(target)
    }

    func cancelContextBoost() {
        cancelContextBoostCallCount += 1
    }

    func process(_ rawText: String) async -> TextProcessingResult {
        TextProcessingResult(
            rawText: rawText,
            finalText: result.finalText,
            llmProviderID: result.llmProviderID,
            styleID: result.styleID,
            warnings: result.warnings,
            correctionEvents: result.correctionEvents,
            appliedCorrectionEvents: result.appliedCorrectionEvents
        )
    }

    func process(_ rawText: String, target: DictationTarget?) async -> TextProcessingResult {
        targets.append(target)
        return await process(rawText)
    }

    func process(
        _ rawText: String,
        target: DictationTarget?,
        onRefinedTextUpdate: @escaping @MainActor (String) -> Void
    ) async -> TextProcessingResult {
        targets.append(target)
        onRefinedTextUpdate(result.finalText)
        return await process(rawText)
    }

    func process(
        _ rawText: String,
        target: DictationTarget?,
        correctionContext: CorrectionContext?,
        onRefinedTextUpdate: @escaping @MainActor (String) -> Void
    ) async -> TextProcessingResult {
        targets.append(target)
        onRefinedTextUpdate(result.finalText)
        return TextProcessingResult(
            rawText: rawText,
            finalText: result.finalText,
            llmProviderID: result.llmProviderID,
            styleID: result.styleID,
            warnings: result.warnings,
            trace: result.trace,
            correctionEvents: result.correctionEvents,
            appliedCorrectionEvents: result.appliedCorrectionEvents
        )
    }
}

@MainActor
private final class CapturingDictationContextPipeline: TextProcessing {
    let result: TextProcessingResult
    private(set) var capturedContexts: [CorrectionContext] = []

    init(result: TextProcessingResult) {
        self.result = result
    }

    func process(_ rawText: String) async -> TextProcessingResult {
        result
    }

    func process(_ rawText: String, target: DictationTarget?) async -> TextProcessingResult {
        result
    }

    func process(
        _ rawText: String,
        target: DictationTarget?,
        correctionContext: CorrectionContext?,
        onRefinedTextUpdate: @escaping @MainActor (String) -> Void
    ) async -> TextProcessingResult {
        if let correctionContext {
            capturedContexts.append(correctionContext)
        }
        return result
    }
}

@MainActor
private final class CapturingCorrectionObservationScheduler: CorrectionObservationScheduling {
    private(set) var observations: [(insertedText: String, context: CorrectionContext, appliedEvents: [CorrectionEvent])] = []

    func scheduleObservation(
        insertedText: String,
        context: CorrectionContext,
        appliedEvents: [CorrectionEvent]
    ) {
        observations.append((insertedText, context, appliedEvents))
    }
}

@MainActor
private final class CancellingRefinementPipeline: TextProcessing {
    let finalText: String
    var onBeforeRefinedTextUpdate: (() -> Void)?

    init(finalText: String) {
        self.finalText = finalText
    }

    func process(_ rawText: String) async -> TextProcessingResult {
        TextProcessingResult(rawText: rawText, finalText: finalText)
    }

    func process(_ rawText: String, target: DictationTarget?) async -> TextProcessingResult {
        await process(rawText)
    }

    func process(
        _ rawText: String,
        target: DictationTarget?,
        onRefinedTextUpdate: @escaping @MainActor (String) -> Void
    ) async -> TextProcessingResult {
        onBeforeRefinedTextUpdate?()
        onRefinedTextUpdate(finalText)
        return await process(rawText)
    }
}

@MainActor
private final class MutableTargetProvider: DictationTargetProviding {
    var target: DictationTarget?

    init(target: DictationTarget?) {
        self.target = target
    }

    func currentTarget() -> DictationTarget? {
        target
    }
}

@MainActor
private final class ObservingTargetProvider: DictationTargetProviding {
    let currentTargetHandler: () -> DictationTarget?

    init(currentTarget: @escaping () -> DictationTarget?) {
        currentTargetHandler = currentTarget
    }

    func currentTarget() -> DictationTarget? {
        currentTargetHandler()
    }
}

@MainActor
private final class FakeTextInjector: TextInserting {
    private(set) var injectedTexts: [String] = []

    func insert(_ text: String) async -> TextInsertionResult {
        injectedTexts.append(text)
        return .success
    }
}

private final class FakeClipboardService: ClipboardSetting {
    private(set) var copiedTexts: [String] = []

    func setString(_ text: String) -> Bool {
        copiedTexts.append(text)
        return true
    }
}

@MainActor
private final class CapturingOutputService: OutputService {
    struct Delivery: Equatable {
        let text: String
        let mode: VoiceTaskMode
        let target: DictationTarget?
        let originalTarget: DictationTarget?
    }

    let result: OutputResult
    private(set) var deliveries: [Delivery] = []

    init(result: OutputResult) {
        self.result = result
    }

    func deliver(
        text: String,
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?
    ) async -> OutputResult {
        deliveries.append(
            Delivery(
                text: text,
                mode: mode,
                target: target,
                originalTarget: originalTarget
            )
        )
        return result
    }
}

@MainActor
private final class FakeAgentComposeHandler: AgentComposeHandling {
    let result: OutputResult
    private(set) var startedTarget: DictationTarget?
    private(set) var startedASRMetadata: VoiceTaskASRMetadata?
    private(set) var updatedASRMetadata: VoiceTaskASRMetadata?
    private(set) var finishedTranscript: String?
    private(set) var didCancel = false
    var onStageChange: ((AgentComposeHUDStage) -> Void)?
    var onStreamingDelta: ((String) -> Void)?
    var lastFailedTaskID: String?

    init(result: OutputResult) {
        self.result = result
    }

    func start(target: DictationTarget?) throws {
        startedTarget = target
    }

    func start(target: DictationTarget?, asrMetadata: VoiceTaskASRMetadata?) throws {
        startedTarget = target
        startedASRMetadata = asrMetadata
    }

    func updateASRMetadata(_ metadata: VoiceTaskASRMetadata) throws {
        updatedASRMetadata = metadata
    }

    func finish(rawTranscript: String) async throws -> OutputResult {
        finishedTranscript = rawTranscript
        return result
    }

    func cancel() {
        didCancel = true
    }

    func fail(_ error: Error) {}
}

@MainActor
private final class FakeAgentDispatchHandler: AgentDispatchHandling {
    let presentation: AgentDispatchHUDPresentation
    private(set) var startedTarget: DictationTarget?
    private(set) var startedASRMetadata: VoiceTaskASRMetadata?
    private(set) var updatedASRMetadata: VoiceTaskASRMetadata?
    private(set) var finishedTranscript: String?
    private(set) var completedFallback: (finalText: String, outputResult: OutputResult)?
    private(set) var didBeginDefaultOutput = false
    var emitsPresentationOnFinish = true
    var onPresentationChange: ((AgentDispatchHUDPresentation) -> Void)?

    init(presentation: AgentDispatchHUDPresentation) {
        self.presentation = presentation
    }

    func start(target: DictationTarget?, asrMetadata: VoiceTaskASRMetadata?) throws {
        startedTarget = target
        startedASRMetadata = asrMetadata
    }

    func updateASRMetadata(_ metadata: VoiceTaskASRMetadata) throws {
        updatedASRMetadata = metadata
    }

    func finish(rawTranscript: String) async throws -> AgentDispatchHUDPresentation {
        finishedTranscript = rawTranscript
        if emitsPresentationOnFinish {
            onPresentationChange?(presentation)
        }
        return presentation
    }

    func completeFallbackInput(finalText: String, outputResult: OutputResult) throws {
        completedFallback = (finalText, outputResult)
    }

    func beginDefaultOutput() {
        didBeginDefaultOutput = true
    }

    func confirm(agentID: String, utterance: String, message: String, alias: String?) async {}
    func cancel() {}
    func fail(_ error: Error) {}
}

private final class CapturingHistoryRepository: HistoryRepository {
    private(set) var savedEntries: [DictationHistoryEntry] = []

    func save(_ entry: DictationHistoryEntry) throws {
        savedEntries.append(entry)
    }

    func entry(id: String) throws -> DictationHistoryEntry? {
        savedEntries.first { $0.id == id }
    }

    func listRecent(limit: Int) throws -> [DictationHistoryEntry] {
        Array(savedEntries.prefix(limit))
    }

    func search(_ query: String, limit: Int) throws -> [DictationHistoryEntry] {
        Array(savedEntries.filter { $0.finalText.contains(query) }.prefix(limit))
    }

    func softDelete(id: String, deletedAt: Date) throws {}
}

private final class CapturingDictationAssetRepository: AssetRepository {
    private(set) var savedItems: [AssetItem] = []
    private(set) var deletedIDs: [String] = []

    func save(_ item: AssetItem) throws {
        savedItems.append(item)
    }

    func asset(id: String) throws -> AssetItem? {
        savedItems.first { $0.id == id && $0.deletedAt == nil }
    }

    func page(query: AssetQuery) throws -> AssetPage {
        AssetPage(items: savedItems, totalCount: savedItems.count)
    }

    func softDelete(id: String, deletedAt: Date) throws {
        deletedIDs.append(id)
    }
}

private final class MutableClock: AppClock, @unchecked Sendable {
    var now: Date
    private let returnsFromSleepImmediately: Bool

    init(now: Date, returnsFromSleepImmediately: Bool = false) {
        self.now = now
        self.returnsFromSleepImmediately = returnsFromSleepImmediately
    }

    func sleep(nanoseconds: UInt64) async throws {
        guard !returnsFromSleepImmediately else {
            return
        }
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

private final class CapturingSleepClock: AppClock, @unchecked Sendable {
    var now: Date
    private(set) var requestedNanoseconds: UInt64?

    init(now: Date) {
        self.now = now
    }

    func sleep(nanoseconds: UInt64) async throws {
        requestedNanoseconds = nanoseconds
        try await Task.sleep(nanoseconds: 10_000_000_000)
    }
}
