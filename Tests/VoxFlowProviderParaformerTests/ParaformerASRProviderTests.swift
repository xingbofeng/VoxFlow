import VoxFlowASRCore
import VoxFlowAudio
@testable import VoxFlowProviderParaformer
import XCTest

final class ParaformerASRProviderTests: XCTestCase {
    func testDescriptorUsesASRCoreContractForChineseLocales() {
        let descriptor = ParaformerProviderDescriptor.descriptor(modelInstallationState: .ready)

        XCTAssertEqual(descriptor.id, ASRProviderID(rawValue: "paraformer"))
        XCTAssertEqual(descriptor.displayName, "Paraformer Large zh")
        XCTAssertEqual(descriptor.supportedLanguages.map(\.bcp47Tag), ["zh-CN", "zh-TW"])
        XCTAssertEqual(descriptor.streamingSemantics, .rollingWindowConfirmedSegments)
    }

    func testReadyProviderCreatesRollingWindowSessionAndEmitsPartialAndFinal() async throws {
        let transcriber = CapturingParaformerTranscriber(result: "海枯的声音")
        let provider = ParaformerASRProvider(
            descriptor: ParaformerProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/paraformer-ready", isDirectory: true),
            transcriberFactory: CapturingParaformerTranscriberFactory(transcriber: transcriber)
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let recorder = ASREventRecorder()
        let collector = Task {
            for await event in session.events {
                await recorder.append(event)
            }
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1, sampleCount: 16_000))

        let receivedPartial = await waitUntil(timeout: 1.0) {
            await recorder.partialTexts().contains("海枯的声音")
        }
        XCTAssertTrue(receivedPartial, "Paraformer should publish rolling partial text before finish().")

        try await session.finish()
        _ = await collector.value
        let finalTexts = await recorder.finalTexts()
        XCTAssertTrue(finalTexts.contains("海枯的声音"))
    }

    func testEnglishLanguageIsRejectedExplicitly() async {
        let provider = ParaformerASRProvider(
            descriptor: ParaformerProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/paraformer-ready", isDirectory: true),
            transcriberFactory: CapturingParaformerTranscriberFactory(
                transcriber: CapturingParaformerTranscriber(result: "unused")
            )
        )

        await XCTAssertThrowsErrorAsync(
            try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "en-US"))
        ) { error in
            XCTAssertEqual(error as? ParaformerProviderError, .unsupportedLanguage("en-US"))
        }
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

    func finalTexts() -> [String] {
        events.compactMap { event -> String? in
            guard case let .final(_, _, text) = event else { return nil }
            return text
        }
    }
}

private actor CapturingParaformerTranscriber: ParaformerTranscribing {
    let result: String

    init(result: String) {
        self.result = result
    }

    func transcribe(audio: [Float]) async throws -> String {
        result
    }
}

private struct CapturingParaformerTranscriberFactory: ParaformerTranscriberMaking {
    let transcriber: CapturingParaformerTranscriber

    func makeTranscriber(directoryURL: URL) async throws -> any ParaformerTranscribing {
        transcriber
    }
}

private func waitUntil(
    timeout: TimeInterval,
    pollInterval: TimeInterval = 0.01,
    condition: @escaping () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
    }
    return await condition()
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> some Any,
    _ validation: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected async expression to throw")
    } catch {
        validation(error)
    }
}
