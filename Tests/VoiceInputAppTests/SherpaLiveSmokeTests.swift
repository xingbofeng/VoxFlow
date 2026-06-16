import AVFoundation
import XCTest
@testable import VoiceInputApp

final class SherpaLiveSmokeTests: XCTestCase {
    func testConfiguredSherpaModelLoadsAndTranscribesWave() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["VOICEINPUT_TEST_SHERPA_LIVE"] == "1" else {
            throw XCTSkip("Set VOICEINPUT_TEST_SHERPA_LIVE=1 to run a sherpa-onnx model smoke test.")
        }
        let variantName = try XCTUnwrap(environment["VOICEINPUT_TEST_SHERPA_VARIANT"])
        let modelPath = try XCTUnwrap(environment["VOICEINPUT_TEST_SHERPA_MODEL_PATH"])
        let wavePath = try XCTUnwrap(environment["VOICEINPUT_TEST_SHERPA_WAVE_PATH"])
        let variant = try XCTUnwrap(SherpaASRModelVariant(rawValue: variantName))

        let samples = try loadSamples(from: URL(fileURLWithPath: wavePath))
        let recognizer = try SherpaOnnxRecognizer(
            variant: variant,
            directoryURL: URL(fileURLWithPath: modelPath, isDirectory: true)
        )
        let text = try recognizer.transcribe(samples: samples)

        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
}
