import XCTest
@testable import VoxFlowASRRuntime
import VoxFlowAudio

final class CloudRealtimeASREngineTests: XCTestCase {
    private struct Configuration: Sendable {
        let complete: Bool
        let payload: String
    }

    private struct Message: Sendable {
        let text: String
        let isFinal: Bool
    }

    private final class CapturingLogger: ASRSessionLogger, @unchecked Sendable {
        let lock = NSLock()
        private(set) var debugs: [String] = []
        private(set) var infos: [String] = []
        private(set) var warnings: [String] = []
        func debug(_ message: String) { lock.withLock { debugs.append(message) } }
        func info(_ message: String) { lock.withLock { infos.append(message) } }
        func warning(_ message: String) { lock.withLock { warnings.append(message) } }
    }

    private final class CallbackHolder: @unchecked Sendable {
        let lock = NSLock()
        private var callback: (@Sendable (Message) -> Void)?
        func set(_ cb: @escaping @Sendable (Message) -> Void) { lock.withLock { callback = cb } }
        func emit(_ message: Message) { lock.withLock { callback }?(message) }
        func waitForReady() {
            while lock.withLock({ callback == nil }) {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
            }
        }
    }

    private struct TestError: Error, Equatable {
        let tag: String
    }

    private struct FailureError: Error {}

    private func makeEngine(
        complete: Bool = true,
        transcribe: @escaping @Sendable (Configuration, AsyncStream<Data>, @escaping @Sendable (Message) -> Void) async throws -> Void,
        interpret: @escaping @Sendable (Message, inout CloudRealtimeASRTranscriptState) -> CloudRealtimeASREmission? = { message, state in
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            state.latestText = text
            return CloudRealtimeASREmission(text: text, isFinal: message.isFinal)
        }
    ) -> (CloudRealtimeASREngine<Configuration, Message>, CapturingLogger) {
        let logger = CapturingLogger()
        let engine = CloudRealtimeASREngine<Configuration, Message>(
            transcribe: transcribe,
            logger: logger,
            logLabel: "TestEngine",
            sessionIDPrefix: "test-asr",
            configurationProvider: { Configuration(complete: complete, payload: "p") },
            isConfigurationComplete: { $0.complete },
            missingConfigurationError: { TestError(tag: "missing") },
            inconsistentSampleRateError: { _ in TestError(tag: "inconsistent") },
            unsupportedSampleRateError: { TestError(tag: "unsupported(\($0))") },
            interpretMessage: interpret
        )
        return (engine, logger)
    }

    func testStartThrowsWhenConfigurationIncomplete() {
        let (engine, _) = makeEngine(complete: false, transcribe: { _, _, _ in })
        XCTAssertThrowsError(try engine.start()) { error in
            XCTAssertEqual(error as? TestError, TestError(tag: "missing"))
        }
    }

    func testIsAvailableReflectsConfigurationCompleteness() {
        let (engineIncomplete, _) = makeEngine(complete: false, transcribe: { _, _, _ in })
        XCTAssertFalse(engineIncomplete.isAvailable)

        let (engineComplete, _) = makeEngine(complete: true, transcribe: { _, _, _ in })
        XCTAssertTrue(engineComplete.isAvailable)
    }

    func testAppendAudioFrameRejectsUnsupportedSampleRate() {
        let (engine, _) = makeEngine(transcribe: { _, _, _ in })
        try? engine.start()
        var capturedError: TestError?
        engine.onError = { capturedError = $0 as? TestError }

        engine.appendAudioFrame(Self.frame(sampleRate: 8_000))

        RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(capturedError, TestError(tag: "unsupported(8000)"))
        engine.cancel()
    }

    func testInconsistentSampleRatePropagatesError() {
        let (engine, _) = makeEngine(transcribe: { _, _, _ in })
        try? engine.start()
        var capturedError: TestError?
        engine.onError = { capturedError = $0 as? TestError }

        engine.appendAudioFrame(Self.frame(sampleRate: 16_000))
        engine.appendAudioFrame(Self.frame(sampleRate: 16_001))

        RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(capturedError, TestError(tag: "inconsistent"))
        engine.cancel()
    }

    func testFinalMessageEmitsFinalEmission() throws {
        let holder = CallbackHolder()
        let (engine, _) = makeEngine(
            transcribe: { _, audioChunks, callback in
                holder.set(callback)
                for await _ in audioChunks {}
            }
        )
        var emissions: [(String, Bool)] = []
        engine.onTranscription = { emissions.append(($0, $1)) }

        try engine.start()
        holder.waitForReady()
        holder.emit(Message(text: "你好", isFinal: false))
        holder.emit(Message(text: "你好世界", isFinal: true))
        RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))

        XCTAssertEqual(emissions.map(\.0), ["你好", "你好世界"])
        XCTAssertEqual(emissions.map(\.1), [false, true])
        engine.cancel()
    }

    func testTranscribeFailurePropagatesOnError() {
        let (engine, _) = makeEngine(
            transcribe: { _, _, _ in
                throw FailureError()
            }
        )
        var captured: String?
        engine.onError = { captured = String(describing: type(of: $0)) }

        try? engine.start()
        RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(captured, "FailureError")
        XCTAssertNotNil(engine.asrRuntimeMetadataSnapshot.errorCode)
        engine.cancel()
    }

    func testCancelStopsSubsequentEmissions() throws {
        let holder = CallbackHolder()
        let (engine, _) = makeEngine(
            transcribe: { _, audioChunks, callback in
                holder.set(callback)
                for await _ in audioChunks {}
            }
        )
        var emissions: [(String, Bool)] = []
        engine.onTranscription = { emissions.append(($0, $1)) }

        try engine.start()
        holder.waitForReady()
        holder.emit(Message(text: "before", isFinal: false))
        RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(emissions.count, 1)

        engine.cancel()
        // After cancel, generation is cleared; late messages must not emit.
        holder.emit(Message(text: "after cancel", isFinal: false))
        RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        XCTAssertEqual(emissions.count, 1)
    }

    func testDroppedFramesIncrementMetadata() {
        let (engine, _) = makeEngine(
            transcribe: { _, _, _ in
                // Stall: never consume the audio stream so the buffer fills and drops.
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
            }
        )
        try? engine.start()
        for index in 0..<200 {
            engine.appendAudioFrame(Self.frame(sequenceNumber: UInt64(index)))
        }
        XCTAssertGreaterThan(engine.asrRuntimeMetadataSnapshot.droppedFrameCount ?? 0, 0)
        engine.cancel()
    }

    func testRuntimeMetadataRecordsAudioDurationMs() {
        let (engine, _) = makeEngine(transcribe: { _, _, _ in })
        try? engine.start()
        engine.appendAudioFrame(Self.frame(sequenceNumber: 0, sampleRate: 16_000, sampleCount: 160))
        XCTAssertGreaterThanOrEqual(engine.asrRuntimeMetadataSnapshot.audioDurationMs ?? 0, 10)
        engine.cancel()
    }

    // MARK: - Helpers

    private static func frame(
        sequenceNumber: UInt64 = 0,
        sampleRate: Int = 16_000,
        sampleCount: Int = 160
    ) -> AudioFrame {
        AudioFrame(
            sequenceNumber: sequenceNumber,
            startSample: sequenceNumber * UInt64(sampleCount),
            samples: ContiguousArray(repeating: 0, count: sampleCount),
            sampleRate: sampleRate,
            capturedAt: ContinuousClock().now
        )
    }
}
