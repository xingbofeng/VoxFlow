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

    func testFinishDoesNotWaitForStalePartialTranscription() async throws {
        let transcriber = BlockingFirstParaformerTranscriber(finalResult: "最终文本")
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
        try await session.accept(Self.frame(sequenceNumber: 2, sampleCount: 16_000))

        let partialStarted = await waitUntil(timeout: 1.0) {
            transcriber.callCount >= 1
        }
        XCTAssertTrue(partialStarted)

        let finishTask = Task {
            try await session.finish()
        }
        let receivedFinal = await waitUntil(timeout: 1.0) {
            await recorder.finalTexts().contains("最终文本")
        }
        XCTAssertTrue(receivedFinal, "finish() should not wait for an already-running partial transcription.")

        transcriber.releaseBlockedPartial()
        try await finishTask.value
        _ = await collector.value
    }

    func testStartWaitsForTranscriberBeforePublishingReady() async throws {
        let factory = DelayedParaformerTranscriberFactory(
            transcriber: CapturingParaformerTranscriber(result: "预热完成")
        )
        let provider = ParaformerASRProvider(
            descriptor: ParaformerProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/paraformer-ready", isDirectory: true),
            transcriberFactory: factory
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let recorder = ASREventRecorder()
        let collector = Task {
            for await event in session.events {
                await recorder.append(event)
            }
        }

        let startTask = Task {
            try await session.start()
        }
        let factoryStarted = await waitUntil(timeout: 1.0) {
            factory.hasStarted
        }
        XCTAssertTrue(factoryStarted)
        let readyBeforeRuntime = await waitUntil(timeout: 0.05) {
            await recorder.readyCount() > 0
        }
        XCTAssertFalse(readyBeforeRuntime)

        factory.release()
        try await startTask.value
        let readyAfterRuntime = await waitUntil(timeout: 1.0) {
            await recorder.readyCount() == 1
        }
        XCTAssertTrue(readyAfterRuntime)

        await session.cancel()
        _ = await collector.value
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

    func readyCount() -> Int {
        events.filter { event in
            guard case .ready = event else { return false }
            return true
        }.count
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
    let transcriber: any ParaformerTranscribing

    func makeTranscriber(directoryURL: URL) async throws -> any ParaformerTranscribing {
        transcriber
    }
}

private final class DelayedParaformerTranscriberFactory: ParaformerTranscriberMaking, @unchecked Sendable {
    private let lock = NSLock()
    private let transcriber: any ParaformerTranscribing
    private var started = false
    private var continuation: CheckedContinuation<any ParaformerTranscribing, Error>?

    var hasStarted: Bool {
        lock.withLock { started }
    }

    init(transcriber: any ParaformerTranscribing) {
        self.transcriber = transcriber
    }

    func makeTranscriber(directoryURL: URL) async throws -> any ParaformerTranscribing {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                started = true
                self.continuation = continuation
            }
        }
    }

    func release() {
        let continuation = lock.withLock { () -> CheckedContinuation<any ParaformerTranscribing, Error>? in
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(returning: transcriber)
    }
}

private final class BlockingFirstParaformerTranscriber: ParaformerTranscribing, @unchecked Sendable {
    private let lock = NSLock()
    private let finalResult: String
    private var calls = 0
    private var blockedPartialContinuation: CheckedContinuation<String, Error>?

    var callCount: Int {
        lock.withLock { calls }
    }

    init(finalResult: String) {
        self.finalResult = finalResult
    }

    func transcribe(audio: [Float]) async throws -> String {
        let callNumber = lock.withLock { () -> Int in
            calls += 1
            return calls
        }
        if callNumber == 1 {
            return try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    blockedPartialContinuation = continuation
                }
            }
        }
        return finalResult
    }

    func releaseBlockedPartial() {
        let continuation = lock.withLock { () -> CheckedContinuation<String, Error>? in
            let continuation = blockedPartialContinuation
            blockedPartialContinuation = nil
            return continuation
        }
        continuation?.resume(returning: "过期 partial")
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
