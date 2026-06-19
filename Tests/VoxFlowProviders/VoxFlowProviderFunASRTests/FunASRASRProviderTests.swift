import VoxFlowASRCore
import VoxFlowAudio
@testable import VoxFlowProviderFunASR
import XCTest

final class FunASRASRProviderTests: XCTestCase {
    func testDescriptorUsesASRCoreContractForMenuSupportedLocales() {
        let descriptor = FunASRProviderDescriptor.descriptor(
            precision: .int8,
            modelInstallationState: .ready
        )

        XCTAssertEqual(descriptor.id, ASRProviderID(rawValue: "funasr"))
        XCTAssertEqual(descriptor.displayName, "FunASR Nano")
        XCTAssertEqual(descriptor.modelInstallationState, .ready)
        XCTAssertEqual(descriptor.supportedLanguages.map(\.bcp47Tag), ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"])
        XCTAssertEqual(descriptor.streamingSemantics, .rollingWindowConfirmedSegments)
    }

    func testJapaneseLanguageCreatesSessionInsteadOfBeingRejected() async throws {
        let transcriber = CapturingFunASRTranscriber(result: "FunASR final text")
        let provider = FunASRASRProvider(
            descriptor: FunASRProviderDescriptor.descriptor(
                precision: .int8,
                modelInstallationState: .ready
            ),
            variant: .int8,
            modelURL: URL(fileURLWithPath: "/tmp/funasr-ready", isDirectory: true),
            transcriberFactory: CapturingFunASRTranscriberFactory(transcriber: transcriber)
        )

        _ = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "ja-JP"))

        let makeCount = await transcriber.makeCount
        XCTAssertEqual(makeCount, 0)
    }

    func testReadyProviderCreatesASRCoreSessionAndEmitsFinal() async throws {
        let transcriber = CapturingFunASRTranscriber(result: "FunASR final text")
        let provider = FunASRASRProvider(
            descriptor: FunASRProviderDescriptor.descriptor(
                precision: .int8,
                modelInstallationState: .ready
            ),
            variant: .int8,
            modelURL: URL(fileURLWithPath: "/tmp/funasr-ready", isDirectory: true),
            transcriberFactory: CapturingFunASRTranscriberFactory(transcriber: transcriber)
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
        try await session.accept(Self.frame(sequenceNumber: 1))
        try await session.finish()

        let events = await collector.value
        XCTAssertTrue(events.contains(.final(sessionID: session.sessionID, revision: 3, text: "FunASR final text")))
        let sampleCount = await transcriber.sampleCount
        XCTAssertGreaterThan(sampleCount, 0)
    }

    func testSessionEmitsRollingPartialBeforeFinish() async throws {
        let transcriber = CapturingFunASRTranscriber(result: "实时中文")
        let provider = FunASRASRProvider(
            descriptor: FunASRProviderDescriptor.descriptor(
                precision: .int8,
                modelInstallationState: .ready
            ),
            variant: .int8,
            modelURL: URL(fileURLWithPath: "/tmp/funasr-ready", isDirectory: true),
            transcriberFactory: CapturingFunASRTranscriberFactory(transcriber: transcriber)
        )

        let session = try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "zh-CN"))
        let recorder = ASREventRecorder()
        let collector = Task {
            for await event in session.events {
                await recorder.append(event)
            }
        }

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 3, sampleCount: 16_000))

        let receivedPartial = await waitUntil(timeout: 1.0) {
            await recorder.partialTexts().contains("实时中文")
        }
        XCTAssertTrue(receivedPartial, "FunASR should publish rolling partial text before finish().")

        try await session.finish()
        _ = await collector.value
    }

    func testStartWaitsForTranscriberBeforePublishingReady() async throws {
        let factory = DelayedFunASRTranscriberFactory(
            transcriber: CapturingFunASRTranscriber(result: "ready")
        )
        let provider = FunASRASRProvider(
            descriptor: FunASRProviderDescriptor.descriptor(
                precision: .int8,
                modelInstallationState: .ready
            ),
            variant: .int8,
            modelURL: URL(fileURLWithPath: "/tmp/funasr-ready", isDirectory: true),
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
        let transcriber = CapturingFunASRTranscriber(result: "unused")
        let provider = FunASRASRProvider(
            descriptor: FunASRProviderDescriptor.descriptor(
                precision: .fp32,
                modelInstallationState: .notInstalled
            ),
            variant: .fp32,
            modelURL: nil,
            transcriberFactory: CapturingFunASRTranscriberFactory(transcriber: transcriber)
        )

        await XCTAssertThrowsErrorAsync(
            try await provider.makeSession(language: ASRLanguageCapability(bcp47Tag: "en-US"))
        ) { error in
            XCTAssertEqual(error as? FunASRProviderError, .modelNotInstalled)
        }
        let makeCount = await transcriber.makeCount
        XCTAssertEqual(makeCount, 0)
    }

    func testEmptyFinalFailsInsteadOfPublishingSuccessfulFinal() async throws {
        let provider = FunASRASRProvider(
            descriptor: FunASRProviderDescriptor.descriptor(
                precision: .int8,
                modelInstallationState: .ready
            ),
            variant: .int8,
            modelURL: URL(fileURLWithPath: "/tmp/funasr-ready", isDirectory: true),
            transcriberFactory: CapturingFunASRTranscriberFactory(
                transcriber: CapturingFunASRTranscriber(result: " \n ")
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

    func testSilenceFailsEmptyWithoutInvokingFunASRDecoder() async throws {
        let transcriber = CapturingFunASRTranscriber(result: "嗯。")
        let provider = FunASRASRProvider(
            descriptor: FunASRProviderDescriptor.descriptor(
                precision: .int8,
                modelInstallationState: .ready
            ),
            variant: .int8,
            modelURL: URL(fileURLWithPath: "/tmp/funasr-ready", isDirectory: true),
            transcriberFactory: CapturingFunASRTranscriberFactory(transcriber: transcriber)
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
        try await session.accept(Self.frame(sequenceNumber: 4, sampleCount: 16_000, amplitude: 0))
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
        let sampleCount = await transcriber.sampleCount
        XCTAssertEqual(sampleCount, 0)
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

    func readyCount() -> Int {
        events.filter { event in
            guard case .ready = event else { return false }
            return true
        }.count
    }
}

private actor CapturingFunASRTranscriber: FunASRTranscribing {
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

private struct CapturingFunASRTranscriberFactory: FunASRTranscriberMaking {
    let transcriber: CapturingFunASRTranscriber

    func makeTranscriber(
        for variant: FunASRModelVariant,
        directoryURL: URL
    ) async throws -> any FunASRTranscribing {
        await transcriber.markMade()
        return transcriber
    }
}

private final class DelayedFunASRTranscriberFactory: FunASRTranscriberMaking, @unchecked Sendable {
    private let lock = NSLock()
    private let transcriber: any FunASRTranscribing
    private var started = false
    private var continuation: CheckedContinuation<any FunASRTranscribing, Error>?

    var hasStarted: Bool {
        lock.withLock { started }
    }

    init(transcriber: any FunASRTranscribing) {
        self.transcriber = transcriber
    }

    func makeTranscriber(
        for variant: FunASRModelVariant,
        directoryURL: URL
    ) async throws -> any FunASRTranscribing {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                started = true
                self.continuation = continuation
            }
        }
    }

    func release() {
        let continuation = lock.withLock { () -> CheckedContinuation<any FunASRTranscribing, Error>? in
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(returning: transcriber)
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
    pollInterval: UInt64 = 10_000_000,
    condition: @escaping () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: pollInterval)
    }
    return await condition()
}
