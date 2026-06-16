import AVFoundation
import XCTest
@testable import VoiceInputApp

final class Qwen3ASREngineTests: XCTestCase {
    func testEngineIsNotAvailableWithoutModel() {
        let engine = Qwen3ASREngine(modelPath: nil)
        XCTAssertFalse(engine.isAvailable)
    }

    func testEngineIsNotAvailableWithEmptyModelDirectory() throws {
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: modelURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: modelURL) }

        let engine = Qwen3ASREngine(modelPath: modelURL.path)
        XCTAssertFalse(engine.isAvailable)
    }

    func testEngineIsAvailableWithLoadableModelDirectory() throws {
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try createLoadableQwen3ModelDirectory(at: modelURL)
        defer { try? FileManager.default.removeItem(at: modelURL) }

        let engine = Qwen3ASREngine(modelPath: modelURL.path)
        XCTAssertTrue(engine.isAvailable)
    }

    func testEngineIsNotAvailableWithMissingModelPath() {
        let engine = Qwen3ASREngine(modelPath: "/tmp/missing-\(UUID().uuidString).mlmodelc")
        XCTAssertFalse(engine.isAvailable)
        XCTAssertThrowsError(try engine.start())
    }

    func testStartClearsBuffer() {
        let engine = makeEngineWithExistingModelPath()
        XCTAssertNoThrow(try engine.start())

        // Buffer should be empty after start
        var receivedText: String?
        var receivedIsFinal = false
        engine.onTranscription = { text, isFinal in
            receivedText = text
            receivedIsFinal = isFinal
        }
        engine.endAudio()
        XCTAssertEqual(receivedText, "")
        XCTAssertTrue(receivedIsFinal)
    }

    func testCancelClearsBuffer() {
        let engine = makeEngineWithExistingModelPath()
        try! engine.start()

        // Append some audio then cancel
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) else {
            XCTFail("Failed to create PCM buffer")
            return
        }
        buffer.frameLength = 1024
        engine.appendAudioBuffer(buffer)
        engine.cancel()

        // After cancel, endAudio should produce empty result
        try! engine.start()
        var receivedText: String?
        engine.onTranscription = { text, isFinal in
            receivedText = text
        }
        engine.endAudio()
        XCTAssertEqual(receivedText, "")
    }

    func testOnTranscriptionCallbackIsCalled() {
        let engine = makeEngineWithExistingModelPath()

        var receivedText: String?
        var receivedIsFinal = false
        engine.onTranscription = { text, isFinal in
            receivedText = text
            receivedIsFinal = isFinal
        }

        try! engine.start()
        engine.endAudio()

        XCTAssertNotNil(receivedText)
        XCTAssertTrue(receivedIsFinal)
    }

    func testAppendAudioEmitsStreamingPartial() async throws {
        let session = FakeQwen3StreamingSession(
            partial: Qwen3StreamingUpdate(transcript: "实时片段", isFinal: false),
            final: Qwen3StreamingUpdate(transcript: "最终文本", isFinal: true)
        )
        let engine = makeEngineWithExistingModelPath(
            sessionFactory: FakeQwen3StreamingSessionFactory(session: session)
        )
        let partial = expectation(description: "Qwen3 emits a streaming partial")
        engine.onTranscription = { text, isFinal in
            if text == "实时片段" && !isFinal {
                partial.fulfill()
            }
        }

        try engine.start()
        engine.appendAudioBuffer(makeAudioBuffer(sampleCount: 16_000))

        await fulfillment(of: [partial], timeout: 1.0)
    }

    func testEndAudioEmitsStreamingFinal() async throws {
        let session = FakeQwen3StreamingSession(
            partial: Qwen3StreamingUpdate(transcript: "实时片段", isFinal: false),
            final: Qwen3StreamingUpdate(transcript: "最终文本", isFinal: true)
        )
        let engine = makeEngineWithExistingModelPath(
            sessionFactory: FakeQwen3StreamingSessionFactory(session: session)
        )
        let final = expectation(description: "Qwen3 emits a final streaming result")
        engine.onTranscription = { text, isFinal in
            if text == "最终文本" && isFinal {
                final.fulfill()
            }
        }

        try engine.start()
        engine.appendAudioBuffer(makeAudioBuffer(sampleCount: 16_000))
        engine.endAudio()

        await fulfillment(of: [final], timeout: 1.0)
    }

    func testEndAudioIgnoresLateAudioBuffers() async throws {
        let session = FakeQwen3StreamingSession(
            partial: nil,
            final: Qwen3StreamingUpdate(transcript: "最终文本", isFinal: true)
        )
        let engine = makeEngineWithExistingModelPath(
            sessionFactory: FakeQwen3StreamingSessionFactory(session: session)
        )
        let final = expectation(description: "Qwen3 emits a final result")
        engine.onTranscription = { _, isFinal in
            if isFinal {
                final.fulfill()
            }
        }

        try engine.start()
        engine.appendAudioBuffer(makeAudioBuffer(sampleCount: 16_000))
        engine.endAudio()
        engine.appendAudioBuffer(makeAudioBuffer(sampleCount: 16_000))

        await fulfillment(of: [final], timeout: 1.0)
        try await Task.sleep(nanoseconds: 100_000_000)
        let chunkCount = await session.receivedChunkCount
        XCTAssertEqual(chunkCount, 1)
    }

    func testEndAudioDoesNotFinishAgainAfterStreamingFinal() async throws {
        let session = FakeQwen3StreamingSession(
            partial: Qwen3StreamingUpdate(transcript: "流式最终文本", isFinal: true),
            final: Qwen3StreamingUpdate(transcript: "不应再次完成", isFinal: true)
        )
        let engine = makeEngineWithExistingModelPath(
            sessionFactory: FakeQwen3StreamingSessionFactory(session: session)
        )
        let streamingFinal = expectation(description: "Qwen3 emits streaming final")
        engine.onTranscription = { text, isFinal in
            if text == "流式最终文本" && isFinal {
                streamingFinal.fulfill()
            }
        }

        try engine.start()
        engine.appendAudioBuffer(makeAudioBuffer(sampleCount: 16_000))
        await fulfillment(of: [streamingFinal], timeout: 1.0)

        engine.endAudio()
        try await Task.sleep(nanoseconds: 100_000_000)

        let finishCount = await session.finishCount
        XCTAssertEqual(finishCount, 0)
    }

    func testOnErrorCallbackIsSet() {
        // onError is nil by default on a new engine
        let engine = makeEngineWithExistingModelPath()
        XCTAssertNil(engine.onError)

        engine.onError = { _ in }
        XCTAssertNotNil(engine.onError)
    }

    func testConfigureIsNoOp() {
        let engine = makeEngineWithExistingModelPath()
        // configure should not crash for any locale
        engine.configure(locale: Locale(identifier: "zh_CN"))
        engine.configure(locale: Locale(identifier: "en_US"))
        engine.configure(locale: Locale(identifier: "ja_JP"))
    }

    func testConformsToASREngineProtocol() {
        let engine: ASREngine = makeEngineWithExistingModelPath()
        XCTAssertNil(engine.onTranscription)
        XCTAssertNil(engine.onError)
        XCTAssertTrue(engine.isAvailable)
    }

    private func makeEngineWithExistingModelPath(
        sessionFactory: any Qwen3StreamingSessionMaking = FluidAudioQwen3StreamingSessionFactory()
    ) -> Qwen3ASREngine {
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try! createLoadableQwen3ModelDirectory(at: modelURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        return Qwen3ASREngine(modelPath: modelURL.path, sessionFactory: sessionFactory)
    }

    private func makeAudioBuffer(sampleCount: Int) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(sampleCount)
        )!
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<sampleCount {
            channel[index] = sin(Float(index) / 40.0) * 0.1
        }
        return buffer
    }

    private func createLoadableQwen3ModelDirectory(at modelURL: URL) throws {
        for relativePath in Qwen3ModelManifest.requiredLoadablePaths {
            let fileURL = modelURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            XCTAssertTrue(FileManager.default.createFile(atPath: fileURL.path, contents: Data()))
        }
        let embeddingURL = modelURL.appendingPathComponent("qwen3_asr_embeddings.bin")
        var header = Data()
        var vocabSize = UInt32(151_936).littleEndian
        var hiddenSize = UInt32(1_024).littleEndian
        withUnsafeBytes(of: &vocabSize) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: &hiddenSize) { header.append(contentsOf: $0) }
        try header.write(to: embeddingURL)
        let handle = try FileHandle(forWritingTo: embeddingURL)
        try handle.truncate(atOffset: 8 + UInt64(151_936) * 1_024 * 2)
        try handle.close()
    }
}

private final class FakeQwen3StreamingSessionFactory: Qwen3StreamingSessionMaking, @unchecked Sendable {
    let session: FakeQwen3StreamingSession

    init(session: FakeQwen3StreamingSession) {
        self.session = session
    }

    func makeSession(modelURL: URL, languageHint: String?) async throws -> any Qwen3StreamingSession {
        session
    }
}

private actor FakeQwen3StreamingSession: Qwen3StreamingSession {
    let partial: Qwen3StreamingUpdate?
    let final: Qwen3StreamingUpdate
    private(set) var receivedChunkCount = 0
    private(set) var finishCount = 0

    init(partial: Qwen3StreamingUpdate?, final: Qwen3StreamingUpdate) {
        self.partial = partial
        self.final = final
    }

    func addAudio(_ samples: [Float]) async throws -> Qwen3StreamingUpdate? {
        receivedChunkCount += 1
        return partial
    }

    func finish() async throws -> Qwen3StreamingUpdate {
        finishCount += 1
        return final
    }

    func cancel() async {}
}
