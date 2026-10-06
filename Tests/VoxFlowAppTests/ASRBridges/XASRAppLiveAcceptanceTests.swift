@preconcurrency import AVFoundation
import VoxFlowASRCore
import VoxFlowAudio
import VoxFlowProviderXASR
import XCTest
@testable import VoxFlowApp

/// Real capture conversion/channel/bridge/provider; only the physical microphone
/// ingress is replaced with an explicitly supplied public diagnostic recording.
final class XASRAppLiveAcceptanceTests: XCTestCase, @unchecked Sendable {
    func testRealAudioPipelineFlushesTheTailWithoutDroppedFrames() async throws {
        guard let model = ProcessInfo.processInfo.environment["VOICEINPUT_TEST_XASR_MODEL_DIR"],
              let pcm = ProcessInfo.processInfo.environment["VOICEINPUT_TEST_XASR_PCM"] else {
            throw XCTSkip("Set native X-ASR model and PCM paths for actual inference")
        }
        let bytes = try Data(contentsOf: URL(fileURLWithPath: pcm))
        let source = bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        guard !source.isEmpty else { throw XCTSkip("Diagnostic PCM input is empty") }
        let long = ProcessInfo.processInfo.environment["VOICEINPUT_TEST_XASR_LONG_SMOKE"] == "1"
        let total = long ? 300 * 16_000 : source.count
        let runtime = XASRRuntime()
        let provider = XASRASRProvider(descriptor: XASRProviderDescriptor.descriptor(modelInstallationState: .ready), modelURL: URL(fileURLWithPath: model), streamFactory: runtime)
        let engine = ASRCoreBackedASREngine(provider: provider, defaultLanguage: .init(bcp47Tag: "zh-CN"), releaseIdleResources: { await runtime.releaseIdleResources() }, errorPresentation: XASRErrorPresentation.localizedError)
        let finished = expectation(description: "real native final through App bridge")
        let callbacks = CapturingXASRLiveCallbacks()
        engine.onTranscription = { text, final in
            let firstFinal = callbacks.record(text: text, final: final)
            if firstFinal { finished.fulfill() }
        }
        engine.onError = { error in callbacks.record(error: error) }
        let channel = AudioFrameChannel(capacity: 96)
        let capture = AudioCaptureSession(channel: channel, converter: try PersistentAudioConverter())
        let consumer = Task {
            while let frame = await channel.next() { engine.appendAudioFrame(frame) }
        }
        defer {
            engine.stop()
            consumer.cancel()
            Task { await channel.finish(); await runtime.invalidate() }
        }
        try engine.start()
        let start = ContinuousClock.now
        var maxInputLag = Duration.zero
        for offset in stride(from: 0, to: total, by: 1_600) {
            let count = min(1_600, total - offset)
            let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)))
            buffer.frameLength = AVAudioFrameCount(count)
            let samples = (0..<count).map { source[(offset + $0) % source.count] }
            samples.withUnsafeBufferPointer { pointer in
                buffer.floatChannelData![0].update(from: pointer.baseAddress!, count: count)
            }
            let accepted = try await capture.append(buffer)
            XCTAssertNotEqual(accepted, .dropped)
            let deadline = start.advanced(by: .nanoseconds(Int64(offset + count) * 1_000_000_000 / 16_000))
            let remaining = ContinuousClock.now.duration(to: deadline)
            if remaining > .zero { try await Task.sleep(for: remaining) }
            else { maxInputLag = max(maxInputLag, .zero - remaining) }
        }
        let released = ContinuousClock.now
        _ = try await capture.finish()
        await consumer.value
        engine.endAudio()
        await fulfillment(of: [finished], timeout: 15)
        let metadata = engine.asrRuntimeMetadataSnapshot
        let snapshot = callbacks.snapshot
        guard let final = snapshot.finals.first, let finalAt = snapshot.finalAt else { return XCTFail("No final reached the App bridge") }
        let finishDelay = released.duration(to: finalAt)
        XCTAssertEqual(snapshot.finals.count, 1)
        XCTAssertTrue(snapshot.errors.isEmpty, snapshot.errors.joined(separator: ","))
        XCTAssertGreaterThan(snapshot.partialCount, 0)
        XCTAssertEqual(metadata.droppedFrameCount, 0)
        let channelSnapshot = await channel.snapshot()
        XCTAssertEqual(channelSnapshot.droppedFrameCount, 0)
        XCTAssertLessThan(finishDelay, .seconds(1))
        if !long { XCTAssertTrue(final.hasSuffix("星期三")) }
        print("XASR_APP_LIVE audio_samples=\(total) partials=\(snapshot.partialCount) finish_delay=\(finishDelay) max_input_lag=\(maxInputLag) dropped=\(metadata.droppedFrameCount ?? 0)")
        engine.stop()
        await runtime.invalidate()
    }
}

private final class CapturingXASRLiveCallbacks: @unchecked Sendable {
    struct Snapshot { var finals: [String] = []; var errors: [String] = []; var partialCount = 0; var finalAt: ContinuousClock.Instant? }
    private let lock = NSLock()
    private var value = Snapshot()
    var snapshot: Snapshot { lock.withLock { value } }
    func record(text: String, final: Bool) -> Bool {
        lock.withLock {
            if final { value.finals.append(text); value.finalAt = .now; return value.finals.count == 1 }
            value.partialCount += 1; return false
        }
    }
    func record(error: Error) { lock.withLock { value.errors.append(error.localizedDescription) } }
}
