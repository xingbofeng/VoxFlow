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
        XCTAssertEqual(descriptor.streamingSemantics, .rollingWindowConfirmedSegments)
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

    func testReadyProviderCreatesRollingWindowSessionAndEmitsPartialBeforeFinal() async throws {
        let transcriber = CapturingSenseVoiceTranscriber(result: "SenseVoice partial text")
        let provider = SenseVoiceASRProvider(
            descriptor: SenseVoiceProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/sensevoice-ready", isDirectory: true),
            transcriberFactory: CapturingSenseVoiceTranscriberFactory(transcriber: transcriber)
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "en-US"))
        let recorder = ASREventRecorder()
        let collector = Task {
            for await event in session.events {
                await recorder.append(event)
            }
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 10, sampleCount: 16_000))

        let receivedPartial = await waitUntil(timeout: 1.0) {
            await recorder.partialTexts().contains("SenseVoice partial text")
        }
        XCTAssertTrue(receivedPartial, "SenseVoice should publish rolling partial text before finish().")

        try await session.finish()
        _ = await collector.value
        let finalTexts = await recorder.finalTexts()
        XCTAssertTrue(finalTexts.contains("SenseVoice partial text"))
    }

    func testFinishDoesNotWaitForStalePartialTranscription() async throws {
        let transcriber = BlockingFirstSenseVoiceTranscriber(finalResult: "最终文本")
        let provider = SenseVoiceASRProvider(
            descriptor: SenseVoiceProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/sensevoice-ready", isDirectory: true),
            transcriberFactory: CapturingSenseVoiceTranscriberFactory(transcriber: transcriber)
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let recorder = ASREventRecorder()
        let collector = Task {
            for await event in session.events {
                await recorder.append(event)
            }
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 11, sampleCount: 16_000))

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
        let factory = DelayedSenseVoiceTranscriberFactory(
            transcriber: CapturingSenseVoiceTranscriber(result: "ready")
        )
        let provider = SenseVoiceASRProvider(
            descriptor: SenseVoiceProviderDescriptor.descriptor(modelInstallationState: .ready),
            modelURL: URL(fileURLWithPath: "/tmp/sensevoice-ready", isDirectory: true),
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

    private static func frame(sequenceNumber: UInt64, sampleCount: Int = 1_600) -> AudioFrame {
        AudioFrame(
            sequenceNumber: sequenceNumber,
            startSample: 0,
            samples: ContiguousArray(repeating: 0.1, count: sampleCount),
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
    let transcriber: any SenseVoiceTranscribing

    func makeTranscriber(directoryURL: URL) async throws -> any SenseVoiceTranscribing {
        if let transcriber = transcriber as? CapturingSenseVoiceTranscriber {
            await transcriber.markMade()
        }
        return transcriber
    }
}

private final class DelayedSenseVoiceTranscriberFactory: SenseVoiceTranscriberMaking, @unchecked Sendable {
    private let lock = NSLock()
    private let transcriber: any SenseVoiceTranscribing
    private var started = false
    private var continuation: CheckedContinuation<any SenseVoiceTranscribing, Error>?

    var hasStarted: Bool {
        lock.withLock { started }
    }

    init(transcriber: any SenseVoiceTranscribing) {
        self.transcriber = transcriber
    }

    func makeTranscriber(directoryURL: URL) async throws -> any SenseVoiceTranscribing {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                started = true
                self.continuation = continuation
            }
        }
    }

    func release() {
        let continuation = lock.withLock { () -> CheckedContinuation<any SenseVoiceTranscribing, Error>? in
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(returning: transcriber)
    }
}

private final class BlockingFirstSenseVoiceTranscriber: SenseVoiceTranscribing, @unchecked Sendable {
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
