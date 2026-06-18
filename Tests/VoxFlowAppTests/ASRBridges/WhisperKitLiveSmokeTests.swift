import AVFoundation
import VoxFlowASRCore
import VoxFlowProviderWhisper
import XCTest
@testable import VoxFlowApp

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
        let provider = WhisperASRProvider(
            descriptor: WhisperProviderDescriptor.descriptor(
                variant: variant,
                modelInstallationState: .ready
            ),
            variant: variant,
            modelURL: URL(fileURLWithPath: modelPath, isDirectory: true)
        )
        let engine = ASRCoreBackedASREngine(
            provider: provider,
            defaultLanguage: ASRLanguageCapability(bcp47Tag: "en-US")
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
        engine.appendAudioFrame(makeTestAudioFrame(samples: samples))
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

}
