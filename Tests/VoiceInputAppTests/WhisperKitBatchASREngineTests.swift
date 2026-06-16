import AVFoundation
import XCTest
@testable import VoiceInputApp

final class WhisperKitBatchASREngineTests: XCTestCase {
    func testModelVariantRejectsEmptyPlaceholderFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperKitModelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        for path in WhisperKitModelVariant.turbo.requiredPaths {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        }

        XCTAssertFalse(WhisperKitModelVariant.turbo.modelsExist(at: root))
    }

    func testEndAudioRunsWhisperKitAdapterAndEmitsFinalText() async throws {
        let transcriber = CapturingWhisperKitTranscriber(result: "Whisper 真实识别结果")
        let engine = WhisperKitBatchASREngine(
            variant: .turbo,
            directoryURL: FileManager.default.temporaryDirectory,
            isModelAvailable: { true },
            transcriberFactory: CapturingWhisperKitTranscriberFactory(transcriber: transcriber)
        )
        let completed = expectation(description: "emits final transcription")
        engine.onTranscription = { text, isFinal in
            XCTAssertEqual(text, "Whisper 真实识别结果")
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

    private func makeAudioBuffer() -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
        buffer.frameLength = 1_600
        return buffer
    }
}

private actor CapturingWhisperKitTranscriber: WhisperKitTranscribing {
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

private struct CapturingWhisperKitTranscriberFactory: WhisperKitTranscriberMaking {
    let transcriber: CapturingWhisperKitTranscriber

    func makeTranscriber(
        for variant: WhisperKitModelVariant,
        directoryURL: URL
    ) async throws -> any WhisperKitTranscribing {
        transcriber
    }
}
