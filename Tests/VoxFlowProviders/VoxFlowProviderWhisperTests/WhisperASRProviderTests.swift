import VoxFlowASRCore
import VoxFlowAudio
@testable import VoxFlowProviderWhisper
import XCTest

final class WhisperASRProviderTests: XCTestCase {
    func testDescriptorKeepsTurboAndLargeReadyWhenModelStoreStateIsReady() {
        let turbo = WhisperProviderDescriptor.descriptor(
            variant: .turbo,
            modelInstallationState: .ready
        )
        let large = WhisperProviderDescriptor.descriptor(
            variant: .largeV3,
            modelInstallationState: .ready
        )

        XCTAssertEqual(turbo.id, ASRProviderID(rawValue: "whisper"))
        XCTAssertEqual(turbo.supportedLanguages.map(\.bcp47Tag), ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"])
        XCTAssertEqual(turbo.modelInstallationState, .ready)
        XCTAssertEqual(turbo.streamingSemantics, .offlineFinalOnly)
        XCTAssertEqual(large.modelInstallationState, .ready)
        XCTAssertEqual(large.streamingSemantics, .offlineFinalOnly)
    }

    func testReadyTurboProviderCreatesASRCoreSessionAndEmitsFinal() async throws {
        let transcriber = CapturingWhisperKitTranscriber(result: "Whisper final text")
        let provider = WhisperASRProvider(
            descriptor: WhisperProviderDescriptor.descriptor(
                variant: .turbo,
                modelInstallationState: .ready
            ),
            variant: .turbo,
            modelURL: URL(fileURLWithPath: "/tmp/whisper-ready", isDirectory: true),
            transcriberFactory: CapturingWhisperKitTranscriberFactory(transcriber: transcriber)
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "en-US"))
        let collector = Task {
            var events: [ASREvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1))
        try await session.finish()

        let events = await collector.value
        XCTAssertTrue(events.contains(.final(sessionID: session.sessionID, revision: 3, text: "Whisper final text")))
        let sampleCount = await transcriber.sampleCount
        XCTAssertGreaterThan(sampleCount, 0)
        let requests = await transcriber.requests
        XCTAssertEqual(requests.map(\.languageCode), ["en"])
        XCTAssertEqual(requests.map(\.task), [.transcribe])
    }

    func testChineseSessionForcesWhisperTranscriptionInsteadOfTranslation() async throws {
        let transcriber = CapturingWhisperKitTranscriber(result: "我不知道这个问题是什么")
        let provider = WhisperASRProvider(
            descriptor: WhisperProviderDescriptor.descriptor(
                variant: .turbo,
                modelInstallationState: .ready
            ),
            variant: .turbo,
            modelURL: URL(fileURLWithPath: "/tmp/whisper-ready", isDirectory: true),
            transcriberFactory: CapturingWhisperKitTranscriberFactory(transcriber: transcriber)
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let collector = Task {
            var events: [ASREvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 3))
        try await session.finish()

        _ = await collector.value
        let requests = await transcriber.requests
        XCTAssertEqual(requests.map(\.languageCode), ["zh"])
        XCTAssertEqual(requests.map(\.task), [.transcribe])
    }

    func testSessionDoesNotRunDecoderUntilFinishBecauseWhisperIsFinalOnly() async throws {
        let transcriber = CapturingWhisperKitTranscriber(
            result: "最终中文",
            progressTexts: ["实时中文"]
        )
        let provider = WhisperASRProvider(
            descriptor: WhisperProviderDescriptor.descriptor(
                variant: .turbo,
                modelInstallationState: .ready
            ),
            variant: .turbo,
            modelURL: URL(fileURLWithPath: "/tmp/whisper-ready", isDirectory: true),
            transcriberFactory: CapturingWhisperKitTranscriberFactory(transcriber: transcriber)
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let recorder = ASREventRecorder()
        let collector = Task {
            for await event in session.events {
                await recorder.append(event)
            }
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 6, sampleCount: 16_000))

        try await Task.sleep(nanoseconds: 50_000_000)
        let partialsBeforeFinish = await recorder.partialTexts()
        let requestsBeforeFinish = await transcriber.requests
        XCTAssertTrue(partialsBeforeFinish.isEmpty)
        XCTAssertTrue(requestsBeforeFinish.isEmpty)

        try await session.finish()
        _ = await collector.value
        let partialsAfterFinish = await recorder.partialTexts()
        let requestsAfterFinish = await transcriber.requests
        XCTAssertEqual(partialsAfterFinish, [])
        XCTAssertEqual(requestsAfterFinish.map(\.task), [.transcribe])
    }

    func testJapaneseSessionPassesWhisperLanguageCode() async throws {
        let transcriber = CapturingWhisperKitTranscriber(result: "これはテストです")
        let provider = WhisperASRProvider(
            descriptor: WhisperProviderDescriptor.descriptor(
                variant: .turbo,
                modelInstallationState: .ready
            ),
            variant: .turbo,
            modelURL: URL(fileURLWithPath: "/tmp/whisper-ready", isDirectory: true),
            transcriberFactory: CapturingWhisperKitTranscriberFactory(transcriber: transcriber)
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "ja-JP"))
        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 4))
        try await session.finish()

        let requests = await transcriber.requests
        XCTAssertEqual(requests.map(\.languageCode), ["ja"])
        XCTAssertEqual(requests.map(\.task), [.transcribe])
    }

    func testReadyLargeProviderCreatesASRCoreSessionWithLargeVariant() async throws {
        let transcriber = CapturingWhisperKitTranscriber(result: "Large V3 final text")
        let provider = WhisperASRProvider(
            descriptor: WhisperProviderDescriptor.descriptor(
                variant: .largeV3,
                modelInstallationState: .ready
            ),
            variant: .largeV3,
            modelURL: URL(fileURLWithPath: "/tmp/whisper-large", isDirectory: true),
            transcriberFactory: CapturingWhisperKitTranscriberFactory(transcriber: transcriber)
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let collector = Task {
            var events: [ASREvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 5))
        try await session.finish()

        let events = await collector.value
        XCTAssertTrue(events.contains(.final(sessionID: session.sessionID, revision: 3, text: "Large V3 final text")))
        let makeCount = await transcriber.makeCount
        XCTAssertEqual(makeCount, 1)
        let madeVariants = await transcriber.madeVariants
        XCTAssertEqual(madeVariants, [.largeV3])
    }

    func testEmptyFinalFailsInsteadOfPublishingSuccessfulFinal() async throws {
        let provider = WhisperASRProvider(
            descriptor: WhisperProviderDescriptor.descriptor(
                variant: .turbo,
                modelInstallationState: .ready
            ),
            variant: .turbo,
            modelURL: URL(fileURLWithPath: "/tmp/whisper-ready", isDirectory: true),
            transcriberFactory: CapturingWhisperKitTranscriberFactory(
                transcriber: CapturingWhisperKitTranscriber(result: " \n ")
            )
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let collector = Task {
            var events: [ASREvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 2))
        do {
            try await session.finish()
        } catch {
        }

        let events = await collector.value
        XCTAssertFalse(events.contains { event in
            guard case .final = event else { return false }
            return true
        })
        let failure = events.compactMap { event -> ASRError? in
            guard case let .failure(_, _, error) = event else { return nil }
            return error
        }.first
        XCTAssertEqual(failure?.category, .emptyTranscript)
    }

    func testSilenceFailsEmptyWithoutInvokingWhisperDecoder() async throws {
        let transcriber = CapturingWhisperKitTranscriber(result: "感谢观看")
        let provider = WhisperASRProvider(
            descriptor: WhisperProviderDescriptor.descriptor(
                variant: .turbo,
                modelInstallationState: .ready
            ),
            variant: .turbo,
            modelURL: URL(fileURLWithPath: "/tmp/whisper-ready", isDirectory: true),
            transcriberFactory: CapturingWhisperKitTranscriberFactory(transcriber: transcriber)
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let collector = Task {
            var events: [ASREvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 7, sampleCount: 16_000, amplitude: 0))
        do {
            try await session.finish()
        } catch {
        }

        let events = await collector.value
        XCTAssertFalse(events.contains { event in
            guard case .final = event else { return false }
            return true
        })
        let failure = events.compactMap { event -> ASRError? in
            guard case let .failure(_, _, error) = event else { return nil }
            return error
        }.first
        XCTAssertEqual(failure?.category, .emptyTranscript)
        let requests = await transcriber.requests
        XCTAssertTrue(requests.isEmpty)
    }

    private static func frame(
        sequenceNumber: UInt64,
        sampleCount: Int = 1_600,
        amplitude: Float = 0.1
    ) -> AudioFrame {
        AudioFrame(
            sequenceNumber: sequenceNumber,
            startSample: 0,
            samples: ContiguousArray(repeating: amplitude, count: sampleCount),
            sampleRate: 16_000,
            capturedAt: ContinuousClock.now
        )
    }
}

private actor ASREventRecorder {
    private var events: [ASREvent] = []

    func append(_ event: ASREvent) {
        events.append(event)
    }

    func partialTexts() -> [String] {
        events.compactMap { event -> String? in
            guard case let .partial(_, transcript) = event else { return nil }
            return transcript.stablePrefix + transcript.unstableSuffix
        }
    }
}

private actor CapturingWhisperKitTranscriber: WhisperKitTranscribing {
    let result: String
    let progressTexts: [String]
    private(set) var sampleCount = 0
    private(set) var makeCount = 0
    private(set) var madeVariants: [WhisperKitModelVariant] = []
    private(set) var requests: [WhisperTranscriptionRequest] = []

    init(result: String, progressTexts: [String] = []) {
        self.result = result
        self.progressTexts = progressTexts
    }

    func markMade(variant: WhisperKitModelVariant) {
        makeCount += 1
        madeVariants.append(variant)
    }

    func transcribe(
        _ request: WhisperTranscriptionRequest,
        onPartial: WhisperPartialHandler?
    ) async throws -> String {
        requests.append(request)
        let audio = request.audio
        sampleCount = audio.count
        for text in progressTexts {
            onPartial?(text)
        }
        return result
    }
}

private struct CapturingWhisperKitTranscriberFactory: WhisperKitTranscriberMaking {
    let transcriber: CapturingWhisperKitTranscriber

    func makeTranscriber(
        for variant: WhisperKitModelVariant,
        directoryURL: URL
    ) async throws -> any WhisperKitTranscribing {
        await transcriber.markMade(variant: variant)
        return transcriber
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure @escaping () async throws -> T,
    _ validation: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        validation(error)
    }
}
