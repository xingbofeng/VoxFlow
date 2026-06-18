import XCTest
import VoxFlowAudio

final class AudioFrameChannelTests: XCTestCase {
    func testAudioFrameCarriesCaptureMetadata() {
        let capturedAt = ContinuousClock.now
        let frame = AudioFrame(
            sequenceNumber: 7,
            startSample: 3_200,
            samples: [0.1, -0.2, 0.3],
            sampleRate: 16_000,
            capturedAt: capturedAt
        )

        XCTAssertEqual(frame.sequenceNumber, 7)
        XCTAssertEqual(frame.startSample, 3_200)
        XCTAssertEqual(frame.samples, [0.1, -0.2, 0.3])
        XCTAssertEqual(frame.sampleRate, 16_000)
        XCTAssertEqual(frame.capturedAt, capturedAt)
    }

    func testChannelDeliversFramesInFIFOOrder() async {
        let channel = AudioFrameChannel(capacity: 3)
        let first = Self.frame(sequenceNumber: 1)
        let second = Self.frame(sequenceNumber: 2)

        let firstSendResult = await channel.send(first)
        let secondSendResult = await channel.send(second)
        XCTAssertEqual(firstSendResult, .enqueued)
        XCTAssertEqual(secondSendResult, .enqueued)
        await channel.finish()

        let receivedFirst = await channel.next()
        let receivedSecond = await channel.next()
        let receivedEnd = await channel.next()
        XCTAssertEqual(receivedFirst?.sequenceNumber, 1)
        XCTAssertEqual(receivedSecond?.sequenceNumber, 2)
        XCTAssertNil(receivedEnd)
    }

    func testChannelIsBoundedAndReportsDroppedFrames() async {
        let channel = AudioFrameChannel(capacity: 2)

        let firstSendResult = await channel.send(Self.frame(sequenceNumber: 1))
        let secondSendResult = await channel.send(Self.frame(sequenceNumber: 2))
        let thirdSendResult = await channel.send(Self.frame(sequenceNumber: 3))
        XCTAssertEqual(firstSendResult, .enqueued)
        XCTAssertEqual(secondSendResult, .enqueued)
        XCTAssertEqual(thirdSendResult, .dropped)

        let snapshot = await channel.snapshot()
        XCTAssertEqual(snapshot.capacity, 2)
        XCTAssertEqual(snapshot.bufferedFrameCount, 2)
        XCTAssertEqual(snapshot.droppedFrameCount, 1)
    }

    private static func frame(sequenceNumber: UInt64) -> AudioFrame {
        AudioFrame(
            sequenceNumber: sequenceNumber,
            startSample: sequenceNumber * 160,
            samples: [Float(sequenceNumber)],
            sampleRate: 16_000,
            capturedAt: ContinuousClock.now
        )
    }
}
