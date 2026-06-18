import XCTest
import VoxFlowAudio

final class AudioEndpointDetectorTests: XCTestCase {
    func testDetectorEmitsSpeechStartedAndEndedAfterTrailingSilence() {
        var detector = AudioEndpointDetector(
            speechThreshold: 0.1,
            trailingSilenceSamples: 320
        )

        XCTAssertEqual(
            detector.process(Self.frame(sequenceNumber: 0, samples: [0.2, 0.2])),
            [.speechStarted(sequenceNumber: 0)]
        )
        XCTAssertEqual(
            detector.process(Self.frame(sequenceNumber: 1, samples: [0, 0], sampleCount: 160)),
            []
        )
        XCTAssertEqual(
            detector.process(Self.frame(sequenceNumber: 2, samples: [0, 0], sampleCount: 160)),
            [.speechEnded(sequenceNumber: 2, trailingSilenceSamples: 320)]
        )
    }

    func testDetectorDoesNotEmitFalseEndpointBeforeTrailingSilenceThreshold() {
        var detector = AudioEndpointDetector(
            speechThreshold: 0.1,
            trailingSilenceSamples: 480
        )

        _ = detector.process(Self.frame(sequenceNumber: 0, samples: [0.2, 0.2]))

        XCTAssertEqual(
            detector.process(Self.frame(sequenceNumber: 1, samples: [0, 0], sampleCount: 160)),
            []
        )
        XCTAssertEqual(
            detector.process(Self.frame(sequenceNumber: 2, samples: [0.2, 0.2])),
            []
        )
    }

    func testDetectorTreatsShortSpeechFrameAsSpeechStarted() {
        var detector = AudioEndpointDetector(
            speechThreshold: 0.1,
            trailingSilenceSamples: 320
        )

        XCTAssertEqual(
            detector.process(Self.frame(sequenceNumber: 0, samples: [0.2])),
            [.speechStarted(sequenceNumber: 0)]
        )
    }

    private static func frame(
        sequenceNumber: UInt64,
        samples: ContiguousArray<Float>,
        sampleCount: Int? = nil
    ) -> AudioFrame {
        let repeatedSamples: ContiguousArray<Float>
        if let sampleCount,
           let firstSample = samples.first {
            repeatedSamples = ContiguousArray(repeating: firstSample, count: sampleCount)
        } else {
            repeatedSamples = samples
        }
        return AudioFrame(
            sequenceNumber: sequenceNumber,
            startSample: sequenceNumber * UInt64(repeatedSamples.count),
            samples: repeatedSamples,
            sampleRate: 16_000,
            capturedAt: ContinuousClock.now
        )
    }
}
