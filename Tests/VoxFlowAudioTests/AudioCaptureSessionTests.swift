import AVFoundation
import XCTest
import VoxFlowAudio

final class AudioCaptureSessionTests: XCTestCase {
    func testFinishFlushesConverterTailBeforeClosingChannel() async throws {
        let channel = AudioFrameChannel(capacity: 4)
        let converter = CapturingAudioConverter(
            convertOutput: [0.1, 0.2],
            finishOutput: [0.3]
        )
        let session = AudioCaptureSession(
            channel: channel,
            converter: converter,
            currentInstant: { ContinuousClock.now }
        )
        let input = try Self.buffer(sampleRate: 48_000, frameCount: 4_800)

        let appendResult = try await session.append(input)
        let finishResult = try await session.finish()

        XCTAssertEqual(appendResult, .enqueued)
        XCTAssertEqual(finishResult, .enqueued)
        XCTAssertEqual(converter.calls, [.convert, .finish])

        let firstFrame = await channel.next()
        let tailFrame = await channel.next()
        let end = await channel.next()
        XCTAssertEqual(firstFrame?.sequenceNumber, 0)
        XCTAssertEqual(firstFrame?.startSample, 0)
        XCTAssertEqual(firstFrame?.samples, [0.1, 0.2])
        XCTAssertEqual(firstFrame?.sampleRate, 16_000)
        XCTAssertEqual(tailFrame?.sequenceNumber, 1)
        XCTAssertEqual(tailFrame?.startSample, 2)
        XCTAssertEqual(tailFrame?.samples, [0.3])
        XCTAssertEqual(tailFrame?.sampleRate, 16_000)
        XCTAssertNil(end)
    }

    func testFinishWaitsForChannelDrainBeforeEnqueuingTail() async throws {
        let channel = AudioFrameChannel(capacity: 1)
        let converter = CapturingAudioConverter(
            convertOutput: [0.1],
            finishOutput: [0.2]
        )
        let session = AudioCaptureSession(
            channel: channel,
            converter: converter,
            currentInstant: { ContinuousClock.now }
        )
        let input = try Self.buffer(sampleRate: 48_000, frameCount: 4_800)

        let appendResult = try await session.append(input)
        let finishTask = Task {
            try await session.finish()
        }
        try await Task.sleep(nanoseconds: 10_000_000)

        let snapshotBeforeDrain = await channel.snapshot()
        XCTAssertEqual(appendResult, .enqueued)
        XCTAssertEqual(snapshotBeforeDrain.bufferedFrameCount, 1)
        XCTAssertEqual(snapshotBeforeDrain.droppedFrameCount, 0)

        let firstFrame = await channel.next()
        let finishResult = try await finishTask.value
        let tailFrame = await channel.next()
        let end = await channel.next()
        let snapshotAfterDrain = await channel.snapshot()

        XCTAssertEqual(firstFrame?.samples, [0.1])
        XCTAssertEqual(finishResult, .enqueued)
        XCTAssertEqual(tailFrame?.sequenceNumber, 1)
        XCTAssertEqual(tailFrame?.startSample, 1)
        XCTAssertEqual(tailFrame?.samples, [0.2])
        XCTAssertNil(end)
        XCTAssertEqual(snapshotAfterDrain.droppedFrameCount, 0)
    }

    private static func buffer(
        sampleRate: Double,
        frameCount: Int
    ) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            )
        )
        buffer.frameLength = AVAudioFrameCount(frameCount)
        return buffer
    }
}

private final class CapturingAudioConverter: AudioPCMConverting, @unchecked Sendable {
    enum Call: Equatable {
        case convert
        case finish
    }

    let targetSampleRate: Double = 16_000
    private(set) var calls: [Call] = []
    private let convertOutput: ContiguousArray<Float>
    private let finishOutput: ContiguousArray<Float>

    init(
        convertOutput: ContiguousArray<Float>,
        finishOutput: ContiguousArray<Float>
    ) {
        self.convertOutput = convertOutput
        self.finishOutput = finishOutput
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> ContiguousArray<Float> {
        calls.append(.convert)
        return convertOutput
    }

    func finish() throws -> ContiguousArray<Float> {
        calls.append(.finish)
        return finishOutput
    }
}
