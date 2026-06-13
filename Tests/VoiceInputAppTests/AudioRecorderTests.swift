import AVFoundation
import XCTest
@testable import VoiceInputApp

final class AudioRecorderTests: XCTestCase {
    func testSilenceProducesZeroNormalizedRMS() throws {
        let buffer = try makeBuffer(samples: [0, 0, 0, 0])

        XCTAssertEqual(AudioRecorder.calculateRMS(from: buffer), 0, accuracy: 0.0001)
    }

    func testFullScaleSignalProducesMaximumNormalizedRMS() throws {
        let buffer = try makeBuffer(samples: [1, -1, 1, -1])

        XCTAssertEqual(AudioRecorder.calculateRMS(from: buffer), 1, accuracy: 0.0001)
    }

    func testVoiceEnhancementBoostsQuietSpeechButLeavesSilenceAndLoudAudioStable() {
        XCTAssertEqual(AudioRecorder.voiceEnhancementGain(normalizedRMS: 0), 1)
        XCTAssertGreaterThan(AudioRecorder.voiceEnhancementGain(normalizedRMS: 0.15), 1)
        XCTAssertEqual(AudioRecorder.voiceEnhancementGain(normalizedRMS: 0.6), 1)
        XCTAssertLessThanOrEqual(AudioRecorder.voiceEnhancementGain(normalizedRMS: 0.01), 2.2)
    }

    private func makeBuffer(samples: [Float]) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
            )
        )
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        for (index, sample) in samples.enumerated() {
            channel[index] = sample
        }
        return buffer
    }
}
