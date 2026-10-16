import AVFoundation
import VoxFlowASRRuntime
import VoxFlowAudio
import VoxFlowTextInsertion
import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

@MainActor
final class DictationOrchestratorPausePreOutputTests: XCTestCase {
    private func makePauseConfiguration() -> PausePreOutputConfiguration {
        PausePreOutputConfiguration(
            silenceThresholdNanoseconds: 10_000_000,
            minimumSegmentCharacterCount: 2
        )
    }

    private func makeOrchestrator(
        engine: PausePreOutputFakeASREngine,
        pipeline: CapturingSegmentTextPipeline,
        configuration: PausePreOutputConfiguration,
        history: PausePreOutputCapturingHistoryRepository = PausePreOutputCapturingHistoryRepository(),
        injector: PausePreOutputFakeTextInjector = PausePreOutputFakeTextInjector(),
        clipboard: PausePreOutputCapturingClipboard = PausePreOutputCapturingClipboard()
    ) -> (orchestrator: DictationOrchestrator, history: PausePreOutputCapturingHistoryRepository) {
        let orchestrator = DictationOrchestrator(
            asrEngineFactory: PausePreOutputFakeEngineFactory(engine: engine),
            audioRecorder: PausePreOutputFakeAudioRecorder(),
            textPipeline: pipeline,
            textInjector: injector,
            historyRepository: history,
            clock: PausePreOutputInstantClock(instantNanoseconds: configuration.silenceThresholdNanoseconds),
            targetProvider: StaticDictationTargetProvider(target: nil),
            clipboardService: clipboard,
            agentComposeHandler: PausePreOutputFakeComposeHandler(),
            agentDispatchHandler: PausePreOutputFakeDispatchHandler(),
            commandHandler: PausePreOutputFakeComposeHandler(),
            pausePreOutputConfiguration: configuration
        )
        return (orchestrator, history)
    }

    private static let appleChinese = DictationConfiguration(
        engineType: .apple,
        locale: Locale(identifier: "zh-CN"),
        languageIdentifier: "zh-CN"
    )

    func testPauseDuringRecordingDeliversSegmentAndKeepsRecording() async throws {
        let engine = PausePreOutputFakeASREngine()
        let pipeline = CapturingSegmentTextPipeline()
        let (orchestrator, _) = makeOrchestrator(
            engine: engine,
            pipeline: pipeline,
            configuration: makePauseConfiguration()
        )

        try orchestrator.start(configuration: Self.appleChinese)
        engine.emit(text: "今天下午开会", isFinal: false)
        await drainMainActorTasks()

        XCTAssertEqual(pipeline.deliveredTexts, ["今天下午开会"])
        XCTAssertEqual(orchestrator.state, .recording)
        XCTAssertFalse(engine.didStop)
        XCTAssertFalse(engine.didEndAudio)
    }

    func testPausePreOutputNeverProcessesOrInsertsOtherVoiceModes() async throws {
        for mode in [VoiceTaskMode.agentCompose, .agentDispatch, .command] {
            let engine = PausePreOutputFakeASREngine()
            let pipeline = CapturingSegmentTextPipeline()
            let injector = PausePreOutputFakeTextInjector()
            let (orchestrator, history) = makeOrchestrator(
                engine: engine, pipeline: pipeline,
                configuration: makePauseConfiguration(), injector: injector
            )
            try orchestrator.start(configuration: Self.appleChinese, mode: mode)
            engine.emit(text: "把这段改成英文", isFinal: false)
            await drainMainActorTasks()

            XCTAssertTrue(pipeline.deliveredTexts.isEmpty, "mode=\(mode)")
            XCTAssertTrue(injector.injectedTexts.isEmpty, "mode=\(mode)")
            XCTAssertTrue(history.savedEntries.isEmpty, "mode=\(mode)")
            orchestrator.cancel()
        }
    }

    func testRevisedFinalResultIsRetainedWithoutDuplicatingInsertedPrefix() async throws {
        let engine = PausePreOutputFakeASREngine()
        let injector = PausePreOutputFakeTextInjector()
        let clipboard = PausePreOutputCapturingClipboard()
        let (orchestrator, history) = makeOrchestrator(
            engine: engine, pipeline: CapturingSegmentTextPipeline(),
            configuration: makePauseConfiguration(), injector: injector, clipboard: clipboard
        )
        try orchestrator.start(configuration: Self.appleChinese)
        engine.emit(text: "今天下午开会", isFinal: false)
        await drainMainActorTasks()
        engine.emit(text: "今天下午开个会，讨论排期", isFinal: false)
        await drainMainActorTasks()
        orchestrator.release()
        engine.emit(text: "今天下午开个会，讨论排期和预算", isFinal: true)
        await drainMainActorTasks()

        XCTAssertEqual(injector.injectedTexts, ["今天下午开会"])
        XCTAssertEqual(clipboard.texts, ["今天下午开个会，讨论排期和预算"])
        XCTAssertEqual(history.savedEntries.last?.finalText, "今天下午开个会，讨论排期和预算")
        XCTAssertEqual(orchestrator.state, .idle)
    }

    func testPauseAndFinalDeliveryPreserveSeparatorsAfterProcessing() async throws {
        let engine = PausePreOutputFakeASREngine()
        let injector = PausePreOutputFakeTextInjector()
        let (orchestrator, _) = makeOrchestrator(
            engine: engine, pipeline: CapturingSegmentTextPipeline(),
            configuration: makePauseConfiguration(), injector: injector
        )
        try orchestrator.start(configuration: Self.appleChinese)
        engine.emit(text: "hello", isFinal: false)
        await drainMainActorTasks()
        engine.emit(text: "hello world", isFinal: false)
        await drainMainActorTasks()
        orchestrator.release()
        engine.emit(text: "hello world\nnext paragraph", isFinal: true)
        await drainMainActorTasks()

        XCTAssertEqual(injector.injectedTexts.joined(), "hello world\nnext paragraph")
    }

    func testEscapeWhileWaitingForFinalOnlyInsertsUndeliveredTail() async throws {
        let engine = PausePreOutputFakeASREngine()
        let injector = PausePreOutputFakeTextInjector()
        let (orchestrator, _) = makeOrchestrator(
            engine: engine, pipeline: CapturingSegmentTextPipeline(),
            configuration: makePauseConfiguration(), injector: injector
        )
        try orchestrator.start(configuration: Self.appleChinese)
        engine.emit(text: "hello", isFinal: false)
        await drainMainActorTasks()
        engine.emit(text: "hello a", isFinal: false)
        await drainMainActorTasks()
        orchestrator.release()

        XCTAssertTrue(orchestrator.handleEscapeKey())
        await drainMainActorTasks()

        XCTAssertEqual(injector.injectedTexts.joined(), "hello a")
        XCTAssertEqual(orchestrator.state, .idle)
    }

    func testEscapeWhileWaitingDetectsRevisedPrefixAndCopiesFullResult() async throws {
        let engine = PausePreOutputFakeASREngine()
        let injector = PausePreOutputFakeTextInjector()
        let clipboard = PausePreOutputCapturingClipboard()
        let (orchestrator, history) = makeOrchestrator(
            engine: engine, pipeline: CapturingSegmentTextPipeline(),
            configuration: makePauseConfiguration(), injector: injector, clipboard: clipboard
        )
        var recoveredState: DictationState?
        orchestrator.onPausePreOutputRecovery = { [weak orchestrator] _ in recoveredState = orchestrator?.state }
        try orchestrator.start(configuration: Self.appleChinese)
        engine.emit(text: "hello", isFinal: false)
        await drainMainActorTasks()
        orchestrator.release()
        engine.emit(text: "hullo world", isFinal: false)
        await drainMainActorTasks()

        XCTAssertTrue(orchestrator.handleEscapeKey())
        await drainMainActorTasks()

        XCTAssertEqual(injector.injectedTexts, ["hello"])
        XCTAssertEqual(clipboard.texts, ["hullo world"])
        XCTAssertEqual(history.savedEntries.last?.finalText, "hullo world")
        XCTAssertEqual(recoveredState, .idle, "Recovery feedback must follow the idle HUD dismissal")
    }

    func testEscapeWhilePauseSegmentIsInFlightIgnoresLateFinal() async throws {
        let engine = PausePreOutputFakeASREngine()
        let injector = PausePreOutputFakeTextInjector()
        let pipeline = CapturingSegmentTextPipeline()
        var pendingSegment: CheckedContinuation<Void, Never>?
        pipeline.beforeProcessing = { _ in
            await withCheckedContinuation { pendingSegment = $0 }
        }
        let (orchestrator, _) = makeOrchestrator(
            engine: engine, pipeline: pipeline,
            configuration: makePauseConfiguration(), injector: injector
        )
        try orchestrator.start(configuration: Self.appleChinese)
        engine.emit(text: "hello", isFinal: false)
        await drainMainActorTasks()
        XCTAssertNotNil(pendingSegment)
        orchestrator.release()
        XCTAssertTrue(orchestrator.handleEscapeKey())
        engine.emit(text: "hello world", isFinal: true)
        await drainMainActorTasks()
        pipeline.beforeProcessing = nil
        pendingSegment?.resume()
        pendingSegment = nil
        await drainMainActorTasks()

        XCTAssertEqual(pipeline.deliveredTexts, ["hello"], "Escape must bypass correction even if a final arrives during the flush")
        XCTAssertEqual(injector.injectedTexts, ["hello"], "Escape commits the latest transcript and ignores a later final")
        XCTAssertEqual(orchestrator.state, .idle)
    }

    func testNextSegmentDeliversOnlyDeltaBeyondFirstPause() async throws {
        let engine = PausePreOutputFakeASREngine()
        let pipeline = CapturingSegmentTextPipeline()
        let (orchestrator, _) = makeOrchestrator(
            engine: engine,
            pipeline: pipeline,
            configuration: makePauseConfiguration()
        )

        try orchestrator.start(configuration: Self.appleChinese)
        engine.emit(text: "今天下午开会", isFinal: false)
        await drainMainActorTasks()
        engine.emit(text: "今天下午开会 讨论排期", isFinal: false)
        await drainMainActorTasks()

        XCTAssertEqual(pipeline.deliveredTexts, ["今天下午开会", "讨论排期"])
        XCTAssertEqual(orchestrator.state, .recording)
    }

    func testShortSegmentBelowMinimumCharacterCountIsNotDelivered() async throws {
        let engine = PausePreOutputFakeASREngine()
        let pipeline = CapturingSegmentTextPipeline()
        let (orchestrator, _) = makeOrchestrator(
            engine: engine,
            pipeline: pipeline,
            configuration: makePauseConfiguration()
        )

        try orchestrator.start(configuration: Self.appleChinese)
        engine.emit(text: "今天下午开会", isFinal: false)
        await drainMainActorTasks()
        engine.emit(text: "今天下午开会 好", isFinal: false)
        await drainMainActorTasks()

        XCTAssertEqual(pipeline.deliveredTexts, ["今天下午开会"])
    }

    func testPauseSegmentIsSavedToHistoryIndependently() async throws {
        let engine = PausePreOutputFakeASREngine()
        let pipeline = CapturingSegmentTextPipeline()
        let (orchestrator, history) = makeOrchestrator(
            engine: engine,
            pipeline: pipeline,
            configuration: makePauseConfiguration()
        )

        try orchestrator.start(configuration: Self.appleChinese)
        engine.emit(text: "今天下午开会", isFinal: false)
        await drainMainActorTasks()

        XCTAssertEqual(history.savedEntries.count, 1)
        XCTAssertEqual(history.savedEntries.first?.rawText, "今天下午开会")
    }

    func testEngineRevisionMarksSessionBrokenAndStopsPreOutput() async throws {
        let engine = PausePreOutputFakeASREngine()
        let pipeline = CapturingSegmentTextPipeline()
        let (orchestrator, _) = makeOrchestrator(
            engine: engine,
            pipeline: pipeline,
            configuration: makePauseConfiguration()
        )

        try orchestrator.start(configuration: Self.appleChinese)
        engine.emit(text: "今天下午开会", isFinal: false)
        await drainMainActorTasks()
        engine.emit(text: "你们好世界", isFinal: false)
        await drainMainActorTasks()
        engine.emit(text: "你们好世界更多内容", isFinal: false)
        await drainMainActorTasks()

        XCTAssertEqual(pipeline.deliveredTexts, ["今天下午开会"])
    }

    func testReleaseAfterPauseDeliversTailDeltaOnly() async throws {
        let engine = PausePreOutputFakeASREngine()
        let pipeline = CapturingSegmentTextPipeline()
        let (orchestrator, _) = makeOrchestrator(
            engine: engine,
            pipeline: pipeline,
            configuration: makePauseConfiguration()
        )

        try orchestrator.start(configuration: Self.appleChinese)
        engine.emit(text: "今天下午开会", isFinal: false)
        await drainMainActorTasks()
        orchestrator.release()
        engine.emit(text: "今天下午开会 讨论排期", isFinal: true)
        await drainMainActorTasks()

        XCTAssertEqual(pipeline.deliveredTexts, ["今天下午开会", "讨论排期"])
        XCTAssertEqual(orchestrator.state, .idle)
    }

    private func drainMainActorTasks() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}

private final class PausePreOutputInstantClock: AppClock, @unchecked Sendable {
    private let instantNanoseconds: UInt64

    init(instantNanoseconds: UInt64) {
        self.instantNanoseconds = instantNanoseconds
    }

    var now = Date(timeIntervalSince1970: 1_800_000_000)

    func sleep(nanoseconds: UInt64) async throws {
        // Pause timers return immediately so tests stay deterministic; every
        // other sleep (final-result timeout) blocks like real time.
        guard nanoseconds == instantNanoseconds else {
            try await Task.sleep(nanoseconds: nanoseconds)
            return
        }
    }
}

@MainActor
private final class CapturingSegmentTextPipeline: TextProcessing {
    private(set) var deliveredTexts: [String] = []
    var beforeProcessing: ((String) async -> Void)?

    func process(_ rawText: String) async -> TextProcessingResult {
        deliveredTexts.append(rawText)
        await beforeProcessing?(rawText)
        return TextProcessingResult(rawText: rawText, finalText: rawText)
    }

    func process(_ rawText: String, target: DictationTarget?) async -> TextProcessingResult {
        await process(rawText)
    }

    func process(
        _ rawText: String,
        target: DictationTarget?,
        onRefinedTextUpdate: @escaping @MainActor (String) -> Void
    ) async -> TextProcessingResult {
        await process(rawText)
    }

    func process(
        _ rawText: String,
        target: DictationTarget?,
        correctionContext: CorrectionContext?,
        onRefinedTextUpdate: @escaping @MainActor (String) -> Void
    ) async -> TextProcessingResult {
        await process(rawText)
    }
}

private final class PausePreOutputFakeEngineFactory: ASREngineFactory {
    let engine: PausePreOutputFakeASREngine

    init(engine: PausePreOutputFakeASREngine) {
        self.engine = engine
    }

    func makeEngine(type: ASREngineType) -> ASREngine {
        engine
    }
}

private final class PausePreOutputFakeASREngine: ASREngine {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?
    private(set) var isAvailable = true
    private(set) var didStart = false
    private(set) var didStop = false
    private(set) var didCancel = false
    private(set) var didEndAudio = false

    func configure(locale: Locale) {}

    func start() throws {
        didStart = true
    }

    func appendAudioFrame(_ frame: AudioFrame) {}

    func endAudio() {
        didEndAudio = true
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
}

private final class PausePreOutputFakeAudioRecorder: AudioRecording {
    private(set) var isRecording = false

    func start() throws {
        isRecording = true
    }

    func stop() {
        isRecording = false
    }

    func drain() {}
}

private final class PausePreOutputFakeTextInjector: TextInserting {
    private(set) var injectedTexts: [String] = []

    func insert(_ text: String) async -> TextInsertionResult {
        injectedTexts.append(text)
        return .success
    }
}

@MainActor
private final class PausePreOutputCapturingClipboard: ClipboardSetting {
    private(set) var texts: [String] = []
    func setString(_ text: String) -> Bool {
        texts.append(text)
        return true
    }
}

@MainActor
private final class PausePreOutputFakeComposeHandler: AgentComposeHandling, CommandHandling {
    var onStageChange: ((AgentComposeHUDStage) -> Void)?
    var onStreamingDelta: ((String) -> Void)?
    var onRuntimeCompleted: ((String) -> Void)?
    var lastFailedTaskID: String? { nil }
    var isConfigured: Bool { true }
    func hasEditableText() -> Bool { true }
    func start(target: DictationTarget?) throws {}
    func start(target: DictationTarget?, asrMetadata: VoiceTaskASRMetadata?) throws {}
    func updateASRMetadata(_ metadata: VoiceTaskASRMetadata) throws {}
    func finish(rawTranscript: String) async throws -> OutputResult { .copied }
    func cancel() {}
    func fail(_ error: Error) {}
}

@MainActor
private final class PausePreOutputFakeDispatchHandler: AgentDispatchHandling {
    var onPresentationChange: ((AgentDispatchHUDPresentation) -> Void)?
    func start(target: DictationTarget?, asrMetadata: VoiceTaskASRMetadata?) throws {}
    func updateASRMetadata(_ metadata: VoiceTaskASRMetadata) throws {}
    func finish(rawTranscript: String) async throws -> AgentDispatchHUDPresentation { .idle }
    func beginDefaultOutput() {}
    func completeFallbackInput(finalText: String, outputResult: OutputResult, appliedCorrectionEvents: [CorrectionEvent], processingTrace: TextProcessingTrace?) throws {}
    func confirm(agentID: String, utterance: String, message: String, alias: String?) async {}
    func cancel() {}
    func fail(_ error: Error) {}
}

private final class PausePreOutputCapturingHistoryRepository: HistoryRepository {
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
