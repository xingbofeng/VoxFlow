import AVFoundation
import XCTest
@testable import VoiceInputApp

final class WhisperKitLiveSmokeTests: XCTestCase {
    func testConfiguredWhisperKitModelLoadsAndTranscribesWave() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["VOICEINPUT_TEST_WHISPERKIT_LIVE"] == "1" else {
            throw XCTSkip("Set VOICEINPUT_TEST_WHISPERKIT_LIVE=1 to run a WhisperKit model smoke test.")
        }
        let variantName = try XCTUnwrap(environment["VOICEINPUT_TEST_WHISPERKIT_VARIANT"])
        let modelPath = try XCTUnwrap(environment["VOICEINPUT_TEST_WHISPERKIT_MODEL_PATH"])
        let wavePath = environment["VOICEINPUT_TEST_WHISPERKIT_WAVE_PATH"]
            ?? URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(".build/checkouts/argmax-oss-swift/Tests/WhisperKitTests/Resources/jfk.wav")
                .path
        let variant = try XCTUnwrap(WhisperKitModelVariant(rawValue: variantName))
        let samples = try loadSamples(from: URL(fileURLWithPath: wavePath))
        let completed = expectation(description: "WhisperKit emits transcription")
        let engine = WhisperKitBatchASREngine(
            variant: variant,
            directoryURL: URL(fileURLWithPath: modelPath, isDirectory: true),
            isModelAvailable: { true }
        )
        var finalText = ""
        var receivedError: Error?
        engine.onTranscription = { text, isFinal in
            if isFinal {
                finalText = text
                completed.fulfill()
            }
        }
        engine.onError = { error in
            receivedError = error
            completed.fulfill()
        }

        try engine.start()
        engine.appendAudioBuffer(makeBuffer(samples: samples))
        engine.endAudio()

        wait(for: [completed], timeout: 180)
        XCTAssertNil(receivedError)
        XCTAssertFalse(finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func loadSamples(from url: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: AVAudioFrameCount(audioFile.length)
            )
        )
        try audioFile.read(into: buffer)
        return try XCTUnwrap(AudioPreprocessor.resampleTo16kHz(buffer))
    }

    private func makeBuffer(samples: [Float]) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        )!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channel = buffer.floatChannelData![0]
        for index in samples.indices {
            channel[index] = samples[index]
        }
        return buffer
    }
}
