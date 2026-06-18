import VoxFlowASRCore
import VoxFlowAudio
import XCTest
@testable import VoxFlowApp

final class ASREngineASRSessionAdapterTests: XCTestCase {
    func testProviderCreatesSessionFromExistingASREngineAndPassesLanguage() async throws {
        let engine = CapturingLegacyASREngine()
        let provider = ASREngineASRProvider(
            descriptor: VoxFlowASRCore.ASRProviderDescriptor(
                id: VoxFlowASRCore.ASRProviderID(rawValue: "legacy-qwen3"),
                displayName: "Qwen3-ASR",
                modelInstallationState: .ready,
                supportedLanguages: [VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "en-US")],
                streamingSemantics: .companionPartialFinal
            ),
            makeEngine: { engine }
        )

        let session = try await provider.makeSession(language: VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "en-US"))

        XCTAssertEqual(provider.descriptor.displayName, "Qwen3-ASR")
        XCTAssertEqual(engine.configuredLocales.map(\.identifier), ["en-US"])
        XCTAssertEqual(session.sessionID.rawValue.hasPrefix("legacy-qwen3-"), true)
    }

    func testSessionMapsLegacyCallbacksToASREventsWithoutPromotingPartialToFinal() async throws {
        let engine = CapturingLegacyASREngine()
        let session = ASREngineASRSessionAdapter(
            sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "legacy-session-test"),
            engine: engine
        )
        let collector = Task {
            var events: [VoxFlowASRCore.ASREvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 3))
        try await session.finish()
        engine.emitTranscription("latest partial", isFinal: false)
        engine.emitTranscription("true final", isFinal: true)

        let events = await collector.value
        XCTAssertEqual(engine.startCallCount, 1)
        XCTAssertEqual(engine.endAudioCallCount, 1)
        XCTAssertEqual(engine.appendedFrames.map(\.sequenceNumber), [3])
        XCTAssertEqual(events.map(\.sessionID), Array(repeating: VoxFlowASRCore.ASRSessionID(rawValue: "legacy-session-test"), count: 6))
        XCTAssertEqual(events.map(\.revision), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(events[0], .preparing(sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "legacy-session-test"), revision: 0))
        XCTAssertEqual(events[1], .ready(sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "legacy-session-test"), revision: 1))
        XCTAssertEqual(events[2], .speechStarted(sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "legacy-session-test"), revision: 2, sequenceNumber: 3))
        XCTAssertEqual(
            events[3],
            .partial(
                sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "legacy-session-test"),
                transcript: VoxFlowASRCore.PartialTranscript(
                    stablePrefix: "",
                    unstableSuffix: "latest partial",
                    revision: 3,
                    audioDuration: .milliseconds(100)
                )
            )
        )
        XCTAssertEqual(events[4], .final(sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "legacy-session-test"), revision: 4, text: "true final"))
        XCTAssertEqual(
            events[5],
            .metrics(
                sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "legacy-session-test"),
                revision: 5,
                metrics: VoxFlowASRCore.ASRMetrics(
                    audioDuration: .milliseconds(100),
                    processedFrameCount: 1,
                    droppedFrameCount: 0
                )
            )
        )
    }

    func testCancelIgnoresLateLegacyCallbacksFromOldSession() async throws {
        let engine = CapturingLegacyASREngine()
        let session = ASREngineASRSessionAdapter(
            sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "legacy-cancelled-session"),
            engine: engine
        )
        let collector = Task {
            var events: [VoxFlowASRCore.ASREvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }

        try await session.start()
        await session.cancel()
        engine.emitTranscription("late text", isFinal: true)
        engine.emitError(LegacyEngineTestError.lateCallback)

        let events = await collector.value
        XCTAssertEqual(engine.cancelCallCount, 1)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0], .preparing(sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "legacy-cancelled-session"), revision: 0))
        XCTAssertEqual(events[1], .ready(sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "legacy-cancelled-session"), revision: 1))
        XCTAssertEqual(
            events[2],
            .failure(
                sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "legacy-cancelled-session"),
                revision: 2,
                error: VoxFlowASRCore.ASRError(
                    category: .cancelled,
                    message: "ASR engine session was cancelled."
                )
            )
        )
    }

    private static func frame(sequenceNumber: UInt64) -> AudioFrame {
        AudioFrame(
            sequenceNumber: sequenceNumber,
            startSample: 0,
            samples: ContiguousArray(repeating: 0.1, count: 1_600),
            sampleRate: 16_000,
            capturedAt: ContinuousClock.now
        )
    }
}

private enum LegacyEngineTestError: Error {
    case lateCallback
}

private final class CapturingLegacyASREngine: ASREngine, @unchecked Sendable {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?
    var isAvailable = true
    private(set) var configuredLocales: [Locale] = []
    private(set) var appendedFrames: [AudioFrame] = []
    private(set) var startCallCount = 0
    private(set) var endAudioCallCount = 0
    private(set) var cancelCallCount = 0

    func configure(locale: Locale) {
        configuredLocales.append(locale)
    }

    func start() throws {
        startCallCount += 1
    }

    func appendAudioFrame(_ frame: AudioFrame) {
        appendedFrames.append(frame)
    }

    func endAudio() {
        endAudioCallCount += 1
    }

    func stop() {}

    func cancel() {
        cancelCallCount += 1
    }

    func emitTranscription(_ text: String, isFinal: Bool) {
        onTranscription?(text, isFinal)
    }

    func emitError(_ error: Error) {
        onError?(error)
    }
}
