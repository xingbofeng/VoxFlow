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
}
