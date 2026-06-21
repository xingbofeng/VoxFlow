import XCTest
import VoxFlowASRCore
import VoxFlowAudio

final class ASRSmokeRunnerTests: XCTestCase {
    func testRunnerPassesSpeechSampleWhenStreamingProviderEmitsPartialAndFinal() async throws {
        let provider = FakeSmokeProvider(
            streamingSemantics: .nativeStreaming,
            sessionFactory: {
                FakeSmokeSession(eventsToEmit: [
                    .partialText("今天我们测试"),
                    .finalText("今天我们测试码上写"),
                ])
            }
        )
        let sample = ASRSmokeSample(
            id: "zh_short",
            language: "zh-CN",
            audioPath: "zh_short.wav",
            transcriptPath: "zh_short.txt",
            expectsSpeech: true,
            allowsEmptyFinal: false,
            requiresPartialWhenStreaming: true,
            maxFinalLatencyMilliseconds: 30_000
        )

        let result = try await ASRSmokeRunner().run(sample: sample, provider: provider)

        XCTAssertEqual(result.outcome, .passed)
        XCTAssertTrue(result.sawPartial)
        XCTAssertTrue(result.sawFinal)
        XCTAssertEqual(result.finalText, "今天我们测试码上写")
    }

    func testRunnerWarnsWhenNonStreamingProviderDoesNotEmitPartial() async throws {
        let provider = FakeSmokeProvider(
            streamingSemantics: .rollingWindowConfirmedSegments,
            sessionFactory: {
                FakeSmokeSession(eventsToEmit: [
                    .finalText("This is a simple voice input test."),
                ])
            }
        )
        let sample = ASRSmokeSample(
            id: "en_short",
            language: "en-US",
            audioPath: "en_short.wav",
            transcriptPath: "en_short.txt",
            expectsSpeech: true,
            allowsEmptyFinal: false,
            requiresPartialWhenStreaming: false,
            maxFinalLatencyMilliseconds: 30_000
        )

        let result = try await ASRSmokeRunner().run(sample: sample, provider: provider)

        XCTAssertEqual(result.outcome, .passed)
        XCTAssertFalse(result.sawPartial)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testRunnerFailsStreamingProviderWhenPartialIsMissing() async throws {
        let provider = FakeSmokeProvider(
            streamingSemantics: .nativeStreaming,
            sessionFactory: {
                FakeSmokeSession(eventsToEmit: [
                    .finalText("今天我们测试码上写"),
                ])
            }
        )
        let sample = ASRSmokeSample(
            id: "zh_short",
            language: "zh-CN",
            audioPath: "zh_short.wav",
            transcriptPath: "zh_short.txt",
            expectsSpeech: true,
            allowsEmptyFinal: false,
            requiresPartialWhenStreaming: true,
            maxFinalLatencyMilliseconds: 30_000
        )

        let result = try await ASRSmokeRunner().run(sample: sample, provider: provider)

        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(result.issues.contains(.missingPartial))
    }

    func testRunnerAllowsEmptyFinalForSilenceSample() async throws {
        let provider = FakeSmokeProvider(
            streamingSemantics: .nativeStreaming,
            sessionFactory: {
                FakeSmokeSession(eventsToEmit: [
                    .failure(.emptyTranscript),
                ])
            }
        )
        let sample = ASRSmokeSample(
            id: "silence",
            language: "zh-CN",
            audioPath: "silence.wav",
            transcriptPath: nil,
            expectsSpeech: false,
            allowsEmptyFinal: true,
            requiresPartialWhenStreaming: false,
            maxFinalLatencyMilliseconds: 30_000
        )

        let result = try await ASRSmokeRunner().run(sample: sample, provider: provider)

        XCTAssertEqual(result.outcome, .passed)
        XCTAssertFalse(result.sawFinal)
        XCTAssertTrue(result.finalText.isEmpty)
    }

    func testRunnerRejectsHallucinatedTextForSilenceSample() async throws {
        let provider = FakeSmokeProvider(
            streamingSemantics: .companionPartialFinal,
            sessionFactory: {
                FakeSmokeSession(eventsToEmit: [
                    .partialText("嗯。"),
                    .finalText("嗯。"),
                ])
            }
        )
        let sample = ASRSmokeSample(
            id: "silence",
            language: "zh-CN",
            audioPath: "silence.wav",
            transcriptPath: nil,
            expectsSpeech: false,
            allowsEmptyFinal: true,
            requiresPartialWhenStreaming: false,
            maxFinalLatencyMilliseconds: 30_000
        )

        let result = try await ASRSmokeRunner().run(sample: sample, provider: provider)

        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(result.issues.contains(.unexpectedSpeechOnSilence))
    }

    func testRunnerConvertsFinishErrorIntoFailedSpeechSampleResult() async throws {
        let provider = FakeSmokeProvider(
            streamingSemantics: .nativeStreaming,
            sessionFactory: {
                FakeSmokeSession(
                    eventsToEmit: [
                        .failure(.emptyTranscript),
                    ],
                    finishError: FakeSmokeError.emptyTranscript
                )
            }
        )
        let sample = ASRSmokeSample(
            id: "zh_short",
            language: "zh-CN",
            audioPath: "zh_short.wav",
            transcriptPath: "zh_short.txt",
            expectsSpeech: true,
            allowsEmptyFinal: false,
            requiresPartialWhenStreaming: false,
            maxFinalLatencyMilliseconds: 30_000
        )

        let result = try await ASRSmokeRunner().run(sample: sample, provider: provider)

        XCTAssertEqual(result.outcome, .failed)
        XCTAssertTrue(result.issues.contains(.emptyFinal))
    }

    func testRunnerDoesNotRequirePartialForShortStreamingSample() async throws {
        let provider = FakeSmokeProvider(
            streamingSemantics: .nativeStreaming,
            sessionFactory: {
                FakeSmokeSession(eventsToEmit: [
                    .finalText("This is a simple voice input test."),
                ])
            }
        )
        let sample = ASRSmokeSample(
            id: "en_short",
            language: "en-US",
            audioPath: "en_short.wav",
            transcriptPath: "en_short.txt",
            expectsSpeech: true,
            allowsEmptyFinal: false,
            requiresPartialWhenStreaming: false,
            maxFinalLatencyMilliseconds: 30_000
        )

        let result = try await ASRSmokeRunner().run(sample: sample, provider: provider)

        XCTAssertEqual(result.outcome, .passed)
        XCTAssertFalse(result.sawPartial)
        XCTAssertTrue(result.sawFinal)
    }
}

private struct FakeSmokeProvider: ASRProvider {
    let descriptor: ASRProviderDescriptor
    private let sessionFactory: @Sendable () -> FakeSmokeSession

    init(
        streamingSemantics: ASRStreamingSemantics,
        sessionFactory: @escaping @Sendable () -> FakeSmokeSession
    ) {
        descriptor = ASRProviderDescriptor(
            id: ASRProviderID(rawValue: "fake"),
            displayName: "Fake",
            modelInstallationState: .ready,
            supportedLanguages: [
                ASRLanguageCapability(bcp47Tag: "zh-CN"),
                ASRLanguageCapability(bcp47Tag: "en-US"),
            ],
            streamingSemantics: streamingSemantics
        )
        self.sessionFactory = sessionFactory
    }

    func install() async throws {}
    func delete() async throws {}
    func prepare() async throws {}
    func healthCheck() async -> ASRProviderHealth { .healthy }
    func makeSession(language: ASRLanguageCapability) async throws -> any ASRSession {
        sessionFactory()
    }
}

private final class FakeSmokeSession: ASRSession, @unchecked Sendable {
    enum PlannedEvent: Sendable {
        case partialText(String)
        case finalText(String)
        case failure(ASRErrorCategory)
    }

    let sessionID = ASRSessionID(rawValue: UUID().uuidString)
    private(set) var revision: UInt64 = 0
    let events: AsyncStream<ASREvent>

    private let eventStream = ASREventStream()
    private let eventsToEmit: [PlannedEvent]
    private let finishError: (any Error)?

    init(eventsToEmit: [PlannedEvent], finishError: (any Error)? = nil) {
        self.eventsToEmit = eventsToEmit
        self.finishError = finishError
        events = eventStream.stream
    }

    func start() async throws {
        revision += 1
        eventStream.yield(.ready(sessionID: sessionID, revision: revision))
    }

    func accept(_ frame: AudioFrame) async throws {}

    func finish() async throws {
        for plannedEvent in eventsToEmit {
            revision += 1
            switch plannedEvent {
            case let .partialText(text):
                eventStream.yield(.partial(
                    sessionID: sessionID,
                    transcript: PartialTranscript(
                        stablePrefix: text,
                        unstableSuffix: "",
                        revision: revision,
                        audioDuration: .seconds(1)
                    )
                ))
            case let .finalText(text):
                eventStream.yield(.final(sessionID: sessionID, revision: revision, text: text))
            case let .failure(category):
                eventStream.yield(.failure(
                    sessionID: sessionID,
                    revision: revision,
                    error: ASRError(category: category, message: category.rawValue)
                ))
            }
        }
        eventStream.finish()
        if let finishError {
            throw finishError
        }
    }

    func cancel() async {
        eventStream.finish()
    }
}

private enum FakeSmokeError: Error {
    case emptyTranscript
}
