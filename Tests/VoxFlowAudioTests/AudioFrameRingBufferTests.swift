import XCTest
import VoxFlowAudio

final class AudioFrameRingBufferTests: XCTestCase {
    func testRingBufferEvictsOldestFramesWhenSampleCapacityIsExceeded() {
        var ringBuffer = AudioFrameRingBuffer(capacitySamples: 5)

        XCTAssertEqual(ringBuffer.append(Self.frame(sequenceNumber: 0, sampleCount: 2)), .stored)
        XCTAssertEqual(ringBuffer.append(Self.frame(sequenceNumber: 1, sampleCount: 2)), .stored)
        XCTAssertEqual(ringBuffer.append(Self.frame(sequenceNumber: 2, sampleCount: 3)), .stored)

        XCTAssertEqual(ringBuffer.frames.map(\.sequenceNumber), [1, 2])
        XCTAssertEqual(ringBuffer.snapshot.capacitySamples, 5)
        XCTAssertEqual(ringBuffer.snapshot.bufferedSampleCount, 5)
        XCTAssertEqual(ringBuffer.snapshot.evictedFrameCount, 1)
        XCTAssertEqual(ringBuffer.snapshot.droppedFrameCount, 0)
    }

    func testRingBufferDropsFrameLargerThanCapacity() {
        var ringBuffer = AudioFrameRingBuffer(capacitySamples: 4)

        XCTAssertEqual(ringBuffer.append(Self.frame(sequenceNumber: 7, sampleCount: 5)), .dropped)

        XCTAssertTrue(ringBuffer.frames.isEmpty)
        XCTAssertEqual(ringBuffer.snapshot.bufferedSampleCount, 0)
        XCTAssertEqual(ringBuffer.snapshot.evictedFrameCount, 0)
        XCTAssertEqual(ringBuffer.snapshot.droppedFrameCount, 1)
    }

    private static func frame(
        sequenceNumber: UInt64,
        sampleCount: Int
    ) -> AudioFrame {
        AudioFrame(
            sequenceNumber: sequenceNumber,
            startSample: sequenceNumber * UInt64(sampleCount),
            samples: ContiguousArray(repeating: Float(sequenceNumber), count: sampleCount),
            sampleRate: 16_000,
            capturedAt: ContinuousClock.now
        )
    }
}
