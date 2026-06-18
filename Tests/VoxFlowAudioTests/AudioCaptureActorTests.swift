import XCTest
import VoxFlowAudio

final class AudioCaptureActorTests: XCTestCase {
    func testCaptureActorAssignsSequenceStartSampleAndTimestamp() async {
        let capturedAt = ContinuousClock.now
        let channel = AudioFrameChannel(capacity: 4)
        let capture = AudioCaptureActor(
            channel: channel,
            currentInstant: { capturedAt }
        )

        let firstResult = await capture.append(
            samples: [0.1, 0.2],
            sampleRate: 16_000
        )
        let secondResult = await capture.append(
            samples: [0.3, 0.4, 0.5],
            sampleRate: 16_000
        )
        await capture.finish()

        XCTAssertEqual(firstResult, .enqueued)
        XCTAssertEqual(secondResult, .enqueued)

        let firstFrame = await channel.next()
        let secondFrame = await channel.next()
        XCTAssertEqual(firstFrame?.sequenceNumber, 0)
        XCTAssertEqual(firstFrame?.startSample, 0)
        XCTAssertEqual(firstFrame?.samples, [0.1, 0.2])
        XCTAssertEqual(firstFrame?.sampleRate, 16_000)
        XCTAssertEqual(firstFrame?.capturedAt, capturedAt)

        XCTAssertEqual(secondFrame?.sequenceNumber, 1)
        XCTAssertEqual(secondFrame?.startSample, 2)
        XCTAssertEqual(secondFrame?.samples, [0.3, 0.4, 0.5])
        XCTAssertEqual(secondFrame?.sampleRate, 16_000)
        XCTAssertEqual(secondFrame?.capturedAt, capturedAt)

        let end = await channel.next()
        XCTAssertNil(end)
    }

    func testCaptureActorAdvancesSequenceAndSampleCursorForDroppedFrames() async {
        let channel = AudioFrameChannel(capacity: 1)
        let capture = AudioCaptureActor(channel: channel)

        let firstResult = await capture.append(samples: [1, 1], sampleRate: 16_000)
        let droppedResult = await capture.append(samples: [2, 2, 2], sampleRate: 16_000)
        let firstFrame = await channel.next()
        let thirdResult = await capture.append(samples: [3], sampleRate: 16_000)
        await capture.finish()

        XCTAssertEqual(firstResult, .enqueued)
        XCTAssertEqual(droppedResult, .dropped)
        XCTAssertEqual(thirdResult, .enqueued)
        XCTAssertEqual(firstFrame?.sequenceNumber, 0)
        XCTAssertEqual(firstFrame?.startSample, 0)

        let thirdFrame = await channel.next()
        XCTAssertEqual(thirdFrame?.sequenceNumber, 2)
        XCTAssertEqual(thirdFrame?.startSample, 5)
        XCTAssertEqual(thirdFrame?.samples, [3])

        let snapshot = await channel.snapshot()
        XCTAssertEqual(snapshot.droppedFrameCount, 1)
    }
}
