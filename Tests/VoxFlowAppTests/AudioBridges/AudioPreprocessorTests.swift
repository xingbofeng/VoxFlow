import AVFoundation
import XCTest
@testable import VoxFlowApp

final class AudioPreprocessorTests: XCTestCase {
    func testResampleOutputIsCorrectSampleRate() {
        // Create a buffer at 48kHz with 1 second of audio
        let sourceRate = 48000.0
        let duration: Double = 1.0
        let sourceFrames = Int(sourceRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sourceRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sourceFrames)) else {
            XCTFail("Failed to create PCM buffer")
            return
        }
        buffer.frameLength = AVAudioFrameCount(sourceFrames)

        // Fill with a sine wave
        let sourceData = buffer.floatChannelData![0]
        let freq: Float = 440.0
        let twoPi: Float = 2.0 * Float.pi
        for i in 0..<sourceFrames {
            let phase = twoPi * freq * Float(i) / Float(sourceRate)
            sourceData[i] = sin(phase)
        }

        guard let resampled = AudioPreprocessor.resampleTo16kHz(buffer) else {
            XCTFail("Resample returned nil")
            return
        }

        // Expected output samples ≈ sourceFrames * (16000 / 48000) = sourceFrames / 3
        let expectedSamples = sourceFrames * 16000 / Int(sourceRate)
        // Allow some tolerance due to resampling filter padding
        let tolerance = max(128, expectedSamples / 20)
        XCTAssertGreaterThan(resampled.count, expectedSamples - tolerance)
        XCTAssertLessThan(resampled.count, expectedSamples + tolerance)
    }

    func testFbankOutputShapeIsPLPx80() {
        // 1 second of 16kHz audio
        let sampleRate = 16000
        let duration: Double = 1.0
        let frameCount = sampleRate * Int(duration)
        var samples = [Float](repeating: 0, count: frameCount)
        let freq: Float = 440.0
        let twoPi: Float = 2.0 * Float.pi
        for i in 0..<frameCount {
            let phase = twoPi * freq * Float(i) / Float(sampleRate)
            samples[i] = sin(phase)
        }

        let fbank = AudioPreprocessor.extractFbank(samples, sampleRate: sampleRate, nMel: 80)

        // Should produce some frames
        XCTAssertGreaterThan(fbank.count, 0)

        // Each frame should have exactly 80 mel bands
        for (i, frame) in fbank.enumerated() {
            XCTAssertEqual(frame.count, 80, "Frame \(i) should have 80 mel bands but has \(frame.count)")
        }
    }

    func testSilenceProducesNonZeroFbank() {
        // 0.5 seconds of silence at 16kHz
        let sampleRate = 16000
        let duration: Double = 0.5
        let frameCount = Int(Double(sampleRate) * duration)
        let samples = [Float](repeating: 0.0, count: frameCount)

        let fbank = AudioPreprocessor.extractFbank(samples, sampleRate: sampleRate, nMel: 80)

        XCTAssertGreaterThan(fbank.count, 0, "Should produce frames even for silence")

        // Silence produces non-zero log fbank values due to epsilon clamping
        let allZero = fbank.allSatisfy { frame in
            frame.allSatisfy { $0 == 0 }
        }
        XCTAssertFalse(allZero, "Fbank should not be all zeros for silence")
    }

    func testResamplePreservesMonoChannel() {
        let sourceRate = 44100.0
        let duration: Double = 0.5
        let sourceFrames = Int(sourceRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sourceRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sourceFrames)) else {
            XCTFail("Failed to create PCM buffer")
            return
        }
        buffer.frameLength = AVAudioFrameCount(sourceFrames)

        guard let resampled = AudioPreprocessor.resampleTo16kHz(buffer) else {
            XCTFail("Resample returned nil")
            return
        }

        // Should have meaningful output (not empty)
        XCTAssertGreaterThan(resampled.count, 0)
        // Output should be within 15% of expected size
        let expectedCount = Int(Double(sourceFrames) * 16000.0 / sourceRate)
        let tolerance = max(128, Int(Double(expectedCount) * 0.15))
        XCTAssertEqual(resampled.count, expectedCount, accuracy: tolerance)
    }
}
