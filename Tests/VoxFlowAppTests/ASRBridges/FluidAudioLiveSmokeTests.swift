import AVFoundation
import VoxFlowProviderSenseVoice
import XCTest
@testable import VoxFlowApp

final class FluidAudioLiveSmokeTests: XCTestCase {
    func testConfiguredFluidAudioModelLoadsAndTranscribesWave() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["VOICEINPUT_TEST_FLUIDAUDIO_LIVE"] == "1" else {
            throw XCTSkip("Set VOICEINPUT_TEST_FLUIDAUDIO_LIVE=1 to run a FluidAudio model smoke test.")
        }
        let modelName = try XCTUnwrap(environment["VOICEINPUT_TEST_FLUIDAUDIO_MODEL"])
        let wavePath = try XCTUnwrap(environment["VOICEINPUT_TEST_FLUIDAUDIO_WAVE_PATH"])
        let shouldDownload = environment["VOICEINPUT_TEST_FLUIDAUDIO_DOWNLOAD"] == "1"
        switch modelName {
        case "senseVoice":
            if shouldDownload {
                _ = try await SenseVoiceModelDownloader().download { _ in }
            }
            let samples = try Self.loadSamples(from: URL(fileURLWithPath: wavePath))
            let transcriber = try await SenseVoiceTranscriberFactory()
                .makeTranscriber(directoryURL: SenseVoiceModel.defaultDirectoryURL())
            let text = try await transcriber.transcribe(audio: samples)
            XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            return
        default:
            XCTFail("Unsupported FluidAudio model: \(modelName)")
            return
        }
    }

    private static func loadSamples(from url: URL) throws -> [Float] {
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
