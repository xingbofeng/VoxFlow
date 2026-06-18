import VoxFlowASRCore
import VoxFlowAudio
@testable import VoxFlowProviderSenseVoice
import XCTest

final class SenseVoiceASRProviderTests: XCTestCase {
    func testDescriptorUsesASRCoreContractForMenuSupportedLocales() {
        let descriptor = SenseVoiceProviderDescriptor.descriptor(modelInstallationState: .ready)

        XCTAssertEqual(descriptor.id, ASRProviderID(rawValue: "sense_voice"))
        XCTAssertEqual(descriptor.displayName, "SenseVoice Small")
        XCTAssertEqual(descriptor.modelInstallationState, .ready)
        XCTAssertEqual(descriptor.supportedLanguages.map(\.bcp47Tag), ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"])
        XCTAssertEqual(descriptor.streamingSemantics, .offlineFinalOnly)
    }

    func testJapaneseLanguageCreatesSessionInsteadOfBeingRejected() async throws {
        let transcriber = CapturingSenseVoiceTranscriber(result: "SenseVoice final text")
        let provider = SenseVoiceASRProvider(
            descriptor: SenseVoiceProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/sensevoice-ready", isDirectory: true),
            transcriberFactory: CapturingSenseVoiceTranscriberFactory(transcriber: transcriber)
        )

        _ = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "ja-JP"))

        let makeCount = await transcriber.makeCount
        XCTAssertEqual(makeCount, 0)
    }

    func testReadyProviderCreatesASRCoreSessionAndEmitsFinal() async throws {
        let transcriber = CapturingSenseVoiceTranscriber(result: "SenseVoice final text")
        let provider = SenseVoiceASRProvider(
            descriptor: SenseVoiceProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/sensevoice-ready", isDirectory: true),
            transcriberFactory: CapturingSenseVoiceTranscriberFactory(transcriber: transcriber)
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
        XCTAssertTrue(events.contains(.final(sessionID: session.sessionID, revision: 3, text: "SenseVoice final text")))
        let sampleCount = await transcriber.sampleCount
        XCTAssertGreaterThan(sampleCount, 0)
    }

    func testNotReadyProviderRejectsSessionBeforeRuntimeCreation() async {
        let transcriber = CapturingSenseVoiceTranscriber(result: "unused")
        let provider = SenseVoiceASRProvider(
            descriptor: SenseVoiceProviderDescriptor.descriptor(modelInstallationState: .notInstalled),
            modelURL: nil,
            transcriberFactory: CapturingSenseVoiceTranscriberFactory(transcriber: transcriber)
        )

        await XCTAssertThrowsErrorAsync(
            try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        ) { error in
            XCTAssertEqual(error as? SenseVoiceProviderError, .modelNotInstalled)
        }
        let makeCount = await transcriber.makeCount
        XCTAssertEqual(makeCount, 0)
    }

    func testEmptyFinalFailsInsteadOfPublishingSuccessfulFinal() async throws {
        let provider = SenseVoiceASRProvider(
            descriptor: SenseVoiceProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/sensevoice-ready", isDirectory: true),
            transcriberFactory: CapturingSenseVoiceTranscriberFactory(
                transcriber: CapturingSenseVoiceTranscriber(result: " \n ")
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

    func testSilenceFailsWithoutInvokingSenseVoiceDecoder() async throws {
        let transcriber = CapturingSenseVoiceTranscriber(result: "그")
        let provider = SenseVoiceASRProvider(
            descriptor: SenseVoiceProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/sensevoice-ready", isDirectory: true),
            transcriberFactory: CapturingSenseVoiceTranscriberFactory(transcriber: transcriber)
        )
        let session = try await provider.makeSession(
            language: ASRLanguageCapability(bcp47Tag: "zh-CN")
        )

        try await session.start()
        try await session.accept(
            AudioFrame(
                sequenceNumber: 3,
                startSample: 0,
                samples: ContiguousArray(repeating: 0, count: 16_000),
                sampleRate: 16_000,
                capturedAt: ContinuousClock.now
            )
        )
        do {
            try await session.finish()
        } catch {
        }

        let sampleCount = await transcriber.sampleCount
        XCTAssertEqual(sampleCount, 0)
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

private actor CapturingSenseVoiceTranscriber: SenseVoiceTranscribing {
    let result: String
    private(set) var sampleCount = 0
    private(set) var makeCount = 0

    init(result: String) {
        self.result = result
    }

    func markMade() {
        makeCount += 1
    }

    func transcribe(audio: [Float]) async throws -> String {
        sampleCount = audio.count
        return result
    }
}

private struct CapturingSenseVoiceTranscriberFactory: SenseVoiceTranscriberMaking {
    let transcriber: CapturingSenseVoiceTranscriber

    func makeTranscriber(directoryURL: URL) async throws -> any SenseVoiceTranscribing {
        await transcriber.markMade()
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
