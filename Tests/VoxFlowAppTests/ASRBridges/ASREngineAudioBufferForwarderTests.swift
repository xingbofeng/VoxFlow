import AVFoundation
import VoxFlowASRRuntime
import VoxFlowAudio
import XCTest
@testable import VoxFlowApp

final class ASREngineAudioBufferForwarderTests: XCTestCase {
    func testAppendCanForwardAudioFrameFromBackgroundQueue() async throws {
        let forwarder = ASREngineAudioFrameForwarder()
        let engine = CapturingAudioFrameEngine()
        forwarder.attach(engine)
        let frame = makeFrame(samples: [0.1, 0.2, 0.3])
        let forwarded = expectation(description: "audio buffer forwarded")

        DispatchQueue.global(qos: .userInitiated).async {
            forwarder.appendAudioFrame(frame)
            forwarded.fulfill()
        }

        await fulfillment(of: [forwarded], timeout: 1)

        XCTAssertEqual(engine.appendCallCount, 1)
        XCTAssertEqual(engine.appendCallWasOnMainThread, [false])
        XCTAssertEqual(engine.appendedFrames.map(\.samples), [
            ContiguousArray([0.1, 0.2, 0.3])
        ])
    }

    func testDetachDropsLaterAudioFrames() {
        let forwarder = ASREngineAudioFrameForwarder()
        let engine = CapturingAudioFrameEngine()
        forwarder.attach(engine)
        forwarder.detach()

        forwarder.appendAudioFrame(makeFrame(samples: [0.4]))

        XCTAssertEqual(engine.appendCallCount, 0)
    }

    func testAppendAudioBufferConvertsRecorderBufferIntoAudioFrame() throws {
        let converter = FakeAudioPCMConverter(convertedSamples: [[0.7, 0.8, 0.9]])
        let forwarder = ASREngineAudioFrameForwarder(
            makeConverter: { converter }
        )
        let engine = CapturingAudioFrameEngine()
        forwarder.attach(engine)

        forwarder.appendAudioBuffer(try makePCMBuffer(sampleCount: 3))

        let frame = try XCTUnwrap(engine.appendedFrames.first)
        XCTAssertEqual(frame.sequenceNumber, 0)
        XCTAssertEqual(frame.startSample, 0)
        XCTAssertEqual(frame.sampleRate, 16_000)
        XCTAssertEqual(frame.samples, ContiguousArray([0.7, 0.8, 0.9]))
    }

    func testFinishFlushesConverterTailBeforeASREngineEndAudio() throws {
        let converter = FakeAudioPCMConverter(
            convertedSamples: [[0.1, 0.2]],
            tailSamples: [0.3, 0.4]
        )
        let forwarder = ASREngineAudioFrameForwarder(
            makeConverter: { converter }
        )
        let engine = CapturingAudioFrameEngine()
        forwarder.attach(engine)

        forwarder.appendAudioBuffer(try makePCMBuffer(sampleCount: 2))
        forwarder.finish()

        XCTAssertEqual(engine.appendedFrames.map(\.samples), [
            ContiguousArray([0.1, 0.2]),
            ContiguousArray([0.3, 0.4]),
        ])
        XCTAssertEqual(engine.appendedFrames.map(\.sequenceNumber), [0, 1])
        XCTAssertEqual(engine.appendedFrames.map(\.startSample), [0, 2])
    }

    func testFinishClosesCurrentAudioInputUntilNextAttach() throws {
        let converter = FakeAudioPCMConverter(
            convertedSamples: [[0.1], [0.9]],
            tailSamples: [0.2]
        )
        let forwarder = ASREngineAudioFrameForwarder(
            makeConverter: { converter }
        )
        let engine = CapturingAudioFrameEngine()
        forwarder.attach(engine)

        forwarder.appendAudioBuffer(try makePCMBuffer(sampleCount: 1))
        forwarder.finish()
        forwarder.appendAudioBuffer(try makePCMBuffer(sampleCount: 1))
        forwarder.appendAudioFrame(makeFrame(samples: [1.0]))

        XCTAssertEqual(engine.appendedFrames.map(\.samples), [
            ContiguousArray([0.1]),
            ContiguousArray([0.2]),
        ])
    }

    /// 录音中途切换输入设备会让采集格式变化（采样率/声道数）。转换器锁定首个 buffer 的源格式，
    /// 遇到新格式必须重建后继续转发——否则切换设备之后的整段录音会被全部丢掉。
    func testAppendAudioBufferKeepsForwardingAfterSourceFormatChange() throws {
        let forwarder = ASREngineAudioFrameForwarder()
        let engine = CapturingAudioFrameEngine()
        forwarder.attach(engine)

        forwarder.appendAudioBuffer(try makePCMBuffer(sampleCount: 4_096))
        forwarder.appendAudioBuffer(
            try makePCMBuffer(sampleCount: 4_096, sampleRate: 44_100, channels: 2)
        )

        let frames = engine.appendedFrames
        XCTAssertEqual(frames.map(\.sequenceNumber), [0, 1])
        XCTAssertTrue(frames.allSatisfy { !$0.samples.isEmpty }, "格式变化后必须继续产出音频帧")
        XCTAssertEqual(frames[1].startSample, UInt64(frames[0].samples.count))
        XCTAssertTrue(frames.allSatisfy { $0.sampleRate == 16_000 })
    }

    private func makeFrame(samples: [Float]) -> AudioFrame {
        AudioFrame(
            sequenceNumber: 0,
            startSample: 0,
            samples: ContiguousArray(samples),
            sampleRate: 16_000,
            capturedAt: .now
        )
    }

    private func makePCMBuffer(
        sampleCount: Int,
        sampleRate: Double = 48_000,
        channels: AVAudioChannelCount = 1
    ) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channels
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ))
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        return buffer
    }
}

private final class CapturingAudioFrameEngine: ASREngine, @unchecked Sendable {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?
    private(set) var isAvailable = true
    private let lock = NSLock()
    private var frames: [AudioFrame] = []
    private var appendMainThreadFlags: [Bool] = []

    var appendCallCount: Int {
        lock.withLock { appendMainThreadFlags.count }
    }

    var appendCallWasOnMainThread: [Bool] {
        lock.withLock { appendMainThreadFlags }
    }

    var appendedFrames: [AudioFrame] {
        lock.withLock { frames }
    }

    func configure(locale: Locale) {}

    func start() throws {}

    func appendAudioFrame(_ frame: AudioFrame) {
        lock.withLock {
            frames.append(frame)
            appendMainThreadFlags.append(Thread.isMainThread)
        }
    }

    func endAudio() {}

    func stop() {}

    func cancel() {}
}

private final class FakeAudioPCMConverter: AudioPCMConverting, @unchecked Sendable {
    let targetSampleRate: Double
    private var convertedSamples: [ContiguousArray<Float>]
    private let tailSamples: ContiguousArray<Float>

    init(
        convertedSamples: [[Float]],
        tailSamples: [Float] = [],
        targetSampleRate: Double = 16_000
    ) {
        self.convertedSamples = convertedSamples.map(ContiguousArray.init)
        self.tailSamples = ContiguousArray(tailSamples)
        self.targetSampleRate = targetSampleRate
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> ContiguousArray<Float> {
        if convertedSamples.isEmpty {
            return []
        }
        return convertedSamples.removeFirst()
    }

    func finish() throws -> ContiguousArray<Float> {
        tailSamples
    }
}
