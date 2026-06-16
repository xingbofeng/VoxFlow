import AVFoundation
import XCTest
@testable import VoiceInputApp

final class FluidAudioBatchASREngineTests: XCTestCase {
    func testSenseVoiceUsesOfficialManagerAdapter() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoiceInputApp/FluidAudioBatchASREngine.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("SenseVoiceManagerTranscriber"))
        XCTAssertFalse(source.contains("SenseVoiceFP32Transcriber"))
    }

    func testEndAudioRunsRealTranscriberAdapterAndEmitsFinalText() async throws {
        let transcriber = CapturingLocalASRTranscriber(result: "真实识别结果")
        let engine = FluidAudioBatchASREngine(
            model: .paraformer,
            isModelAvailable: { true },
            transcriberFactory: CapturingLocalASRTranscriberFactory(transcriber: transcriber)
        )
        let completed = expectation(description: "emits final transcription")
        engine.onTranscription = { text, isFinal in
            XCTAssertEqual(text, "真实识别结果")
            XCTAssertTrue(isFinal)
            completed.fulfill()
        }

        try engine.start()
        engine.appendAudioBuffer(makeAudioBuffer())
        engine.endAudio()

        await fulfillment(of: [completed], timeout: 1)
        let sampleCount = await transcriber.sampleCount
        XCTAssertGreaterThan(sampleCount, 0)
    }

    func testStartRejectsMissingModel() {
        let engine = FluidAudioBatchASREngine(
            model: .senseVoice,
            isModelAvailable: { false },
            transcriberFactory: CapturingLocalASRTranscriberFactory(
                transcriber: CapturingLocalASRTranscriber(result: "")
            )
        )

        XCTAssertFalse(engine.isAvailable)
        XCTAssertThrowsError(try engine.start())
    }

    private func makeAudioBuffer() -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
        buffer.frameLength = 1_600
        return buffer
    }
}

private actor CapturingLocalASRTranscriber: LocalASRTranscribing {
    let result: String
    private(set) var sampleCount = 0

    init(result: String) {
        self.result = result
    }

    func transcribe(audio: [Float]) async throws -> String {
        sampleCount = audio.count
        return result
    }
}

private struct CapturingLocalASRTranscriberFactory: LocalASRTranscriberMaking {
    let transcriber: CapturingLocalASRTranscriber

    func makeTranscriber(for model: FluidAudioLocalASRModel) async throws -> any LocalASRTranscribing {
        transcriber
    }
}
