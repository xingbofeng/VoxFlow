import AVFoundation
import XCTest
import VoxFlowAudio
@testable import VoxFlowApp

@MainActor
final class NotesRecordingServiceTests: XCTestCase {
    func testStartConfiguresEngineWithCurrentLanguage() async throws {
        let engine = CapturingNotesASREngine()
        let recorder = NotesAudioRecorderSpy()
        let forwarder = NotesAudioFrameForwarderSpy()
        let service = NotesRecordingService(
            recorder: recorder,
            audioBufferForwarder: forwarder,
            currentLanguage: { .english },
            selectedEngineType: { .apple },
            makeEngine: { engineType in
                XCTAssertEqual(engineType, .apple)
                return engine
            },
            microphonePermission: { true },
            speechRecognitionPermission: { true }
        )

        try await service.start()

        XCTAssertEqual(engine.configuredLocaleIdentifiers, ["en-US"])
        XCTAssertEqual(recorder.startCallCount, 1)
        XCTAssertTrue(forwarder.attachedEngine === engine)
    }

    func testStartConfiguresEngineWithJapaneseLanguage() async throws {
        let engine = CapturingNotesASREngine()
        let recorder = NotesAudioRecorderSpy()
        let service = NotesRecordingService(
            recorder: recorder,
            audioBufferForwarder: NotesAudioFrameForwarderSpy(),
            currentLanguage: { .japanese },
            selectedEngineType: { .apple },
            makeEngine: { _ in engine },
            microphonePermission: { true },
            speechRecognitionPermission: { true }
        )

        try await service.start()

        XCTAssertEqual(engine.configuredLocaleIdentifiers, ["ja-JP"])
        XCTAssertEqual(recorder.startCallCount, 1)
    }

    func testFinishFallsBackToLatestPartialWhenFinalTimesOut() async throws {
        let engine = CapturingNotesASREngine()
        let recorder = NotesAudioRecorderSpy()
        let clock = ImmediateNotesClock()
        let service = NotesRecordingService(
            recorder: recorder,
            audioBufferForwarder: NotesAudioFrameForwarderSpy(),
            currentLanguage: { .english },
            selectedEngineType: { .apple },
            makeEngine: { _ in engine },
            microphonePermission: { true },
            speechRecognitionPermission: { true },
            clock: clock,
            finalTimeoutNanoseconds: 1
        )
        var events: [(String, Bool)] = []
        service.onTranscription = { text, isFinal in
            events.append((text, isFinal))
        }

        try await service.start()
        engine.emit(text: "partial result", isFinal: false)
        service.finish()
        await drainMainActorTasks()

        XCTAssertEqual(events.map(\.0), ["partial result", "partial result"])
        XCTAssertEqual(events.map(\.1), [false, true])
        XCTAssertEqual(recorder.stopCallCount, 1)
        XCTAssertEqual(recorder.drainCallCount, 1)
    }

    func testRecognitionErrorAfterFinishFallsBackToLatestPartial() async throws {
        let engine = CapturingNotesASREngine()
        let recorder = NotesAudioRecorderSpy()
        let service = NotesRecordingService(
            recorder: recorder,
            audioBufferForwarder: NotesAudioFrameForwarderSpy(),
            currentLanguage: { .english },
            selectedEngineType: { .apple },
            makeEngine: { _ in engine },
            microphonePermission: { true },
            speechRecognitionPermission: { true }
        )
        var transcriptions: [(String, Bool)] = []
        var errors: [String] = []
        service.onTranscription = { text, isFinal in
            transcriptions.append((text, isFinal))
        }
        service.onError = { error in
            errors.append(error.localizedDescription)
        }

        try await service.start()
        engine.emit(text: "latest partial", isFinal: false)
        service.finish()
        engine.fail(NotesRecordingServiceTestError.expected)
        await drainMainActorTasks()

        XCTAssertEqual(transcriptions.map(\.0), ["latest partial", "latest partial"])
        XCTAssertEqual(transcriptions.map(\.1), [false, true])
        XCTAssertTrue(errors.isEmpty)
    }

    func testTencentCloudFinishUsesInteractiveTimeoutInsteadOfColdLocalModelTimeout() async throws {
        let engine = CapturingNotesASREngine()
        let clock = CapturingNotesClock()
        let service = NotesRecordingService(
            recorder: NotesAudioRecorderSpy(),
            audioBufferForwarder: NotesAudioFrameForwarderSpy(),
            currentLanguage: { .simplifiedChinese },
            selectedEngineType: { .tencentCloud },
            makeEngine: { _ in engine },
            microphonePermission: { true },
            speechRecognitionPermission: { true },
            clock: clock,
            finalTimeoutNanoseconds: 1
        )

        try await service.start()
        engine.emit(text: "云端 partial", isFinal: false)
        service.finish()
        await drainMainActorTasks()

        XCTAssertEqual(clock.sleepDurations, [1])
    }
}

@MainActor
private final class NotesAudioRecorderSpy: NotesAudioRecording {
    weak var delegate: AudioRecorder.Delegate?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var drainCallCount = 0

    func start() throws {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func drain() {
        drainCallCount += 1
    }
}

private final class NotesAudioFrameForwarderSpy: ASREngineAudioFrameForwarding, @unchecked Sendable {
    private(set) var attachedEngine: ASREngine?

    func attach(_ engine: ASREngine) {
        attachedEngine = engine
    }

    func detach() {}
    func appendAudioFrame(_ frame: AudioFrame) {}
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {}
    func finish() {}
}

private final class CapturingNotesASREngine: ASREngine {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?
    let isAvailable = true
    private(set) var configuredLocaleIdentifiers: [String] = []

    func configure(locale: Locale) {
        configuredLocaleIdentifiers.append(locale.identifier)
    }

    func start() throws {}
    func appendAudioFrame(_ frame: AudioFrame) {}
    func endAudio() {}
    func stop() {}
    func cancel() {}

    func emit(text: String, isFinal: Bool) {
        onTranscription?(text, isFinal)
    }

    func fail(_ error: Error) {
        onError?(error)
    }
}

private struct NotesRecordingServiceTestError: LocalizedError {
    static let expected = NotesRecordingServiceTestError()

    var errorDescription: String? {
        "expected"
    }
}

private final class ImmediateNotesClock: AppClock, @unchecked Sendable {
    var now: Date = Date()

    func sleep(nanoseconds: UInt64) async throws {}
}

private final class CapturingNotesClock: AppClock, @unchecked Sendable {
    var now: Date = Date()
    private(set) var sleepDurations: [UInt64] = []

    func sleep(nanoseconds: UInt64) async throws {
        sleepDurations.append(nanoseconds)
    }
}

private func drainMainActorTasks() async {
    await Task.yield()
    await Task.yield()
}
