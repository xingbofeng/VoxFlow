import XCTest
import VoxFlowASRCore
import VoxFlowAudio
@testable import VoxFlowProviderApple

final class VoxFlowProviderAppleTargetTests: XCTestCase {
    func testTargetIsAvailableForProviderContractTests() {
        XCTAssertNotNil(VoxFlowProviderAppleTargetMarker.self)
    }

    func testAppleSpeechDescriptorUsesASRCoreProviderContract() {
        let descriptor = AppleSpeechProviderDescriptor.current

        XCTAssertEqual(descriptor.id, ASRProviderID(rawValue: "apple_speech"))
        XCTAssertEqual(descriptor.displayName, "系统自带")
        XCTAssertEqual(descriptor.modelInstallationState, .ready)
        XCTAssertEqual(descriptor.supportedLanguages.map(\.bcp47Tag), ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"])
        XCTAssertEqual(descriptor.streamingSemantics, .systemStreaming)
    }

    func testAppleSpeechHealthReflectsAuthorizationWithoutCreatingFakeRuntime() async {
        let authorized = AppleSpeechASRProvider(
            authorizationStatus: { .authorized },
            makeEngine: { _ in AppleSpeechEngineProbe() }
        )
        let denied = AppleSpeechASRProvider(
            authorizationStatus: { .denied },
            makeEngine: { _ in AppleSpeechEngineProbe() }
        )

        let authorizedHealth = await authorized.healthCheck()
        let deniedHealth = await denied.healthCheck()

        XCTAssertEqual(authorizedHealth, .healthy)
        XCTAssertEqual(
            deniedHealth,
            .unhealthy(
                ASRError(
                    category: .preparationFailed,
                    message: "Apple Speech authorization is denied."
                )
            )
        )
    }

    func testAppleSpeechProviderCreatesSessionForExplicitLanguage() async throws {
        let probe = AppleSpeechProviderProbe()
        let provider = AppleSpeechASRProvider(
            authorizationStatus: { .authorized },
            makeEngine: { locale in
                probe.locales.append(locale.identifier)
                return AppleSpeechEngineProbe()
            }
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "en-US"))

        XCTAssertEqual(probe.locales, ["en-US"])
        XCTAssertEqual(session.sessionID.rawValue.hasPrefix("apple-speech-"), true)
    }

    func testAppleSpeechSessionEmitsPartialAndFinalEventsFromEngineCallbacks() async throws {
        let engine = AppleSpeechEngineProbe()
        let session = AppleSpeechASRSession(
            sessionID: ASRSessionID(rawValue: "apple-session-test"),
            engine: engine
        )
        let collector = Task {
            var events: [ASREvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 7))
        engine.emitTranscript("hello", isFinal: false)
        engine.emitTranscript("hello world", isFinal: true)

        let events = await collector.value
        XCTAssertEqual(events.map(\.sessionID), Array(repeating: ASRSessionID(rawValue: "apple-session-test"), count: 6))
        XCTAssertEqual(events.map(\.revision), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(events[0], .preparing(sessionID: ASRSessionID(rawValue: "apple-session-test"), revision: 0))
        XCTAssertEqual(events[1], .ready(sessionID: ASRSessionID(rawValue: "apple-session-test"), revision: 1))
        XCTAssertEqual(events[2], .speechStarted(sessionID: ASRSessionID(rawValue: "apple-session-test"), revision: 2, sequenceNumber: 7))
        XCTAssertEqual(
            events[3],
            .partial(
                sessionID: ASRSessionID(rawValue: "apple-session-test"),
                transcript: PartialTranscript(
                    stablePrefix: "",
                    unstableSuffix: "hello",
                    revision: 3,
                    audioDuration: .milliseconds(100)
                )
            )
        )
        XCTAssertEqual(events[4], .final(sessionID: ASRSessionID(rawValue: "apple-session-test"), revision: 4, text: "hello world"))
        XCTAssertEqual(
            events[5],
            .metrics(
                sessionID: ASRSessionID(rawValue: "apple-session-test"),
                revision: 5,
                metrics: ASRMetrics(
                    audioDuration: .milliseconds(100),
                    processedFrameCount: 1,
                    droppedFrameCount: 0
                )
            )
        )
        XCTAssertEqual(engine.acceptedFrames.map(\.sequenceNumber), [7])
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

private final class AppleSpeechProviderProbe: @unchecked Sendable {
    var locales: [String] = []
}

private final class AppleSpeechEngineProbe: AppleSpeechRecognitionEngine, @unchecked Sendable {
    var onTranscription: (@Sendable (String, Bool) -> Void)?
    var onError: (@Sendable (Error) -> Void)?
    var isAvailable = true
    private(set) var acceptedFrames: [AudioFrame] = []

    func start() throws {}

    func accept(_ frame: AudioFrame) {
        acceptedFrames.append(frame)
    }

    func finish() {}

    func cancel() {}

    func emitTranscript(_ text: String, isFinal: Bool) {
        onTranscription?(text, isFinal)
    }
}
