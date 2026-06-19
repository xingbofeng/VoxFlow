import Foundation
@testable import VoxFlowProviderQwen3
import XCTest

final class SpeechSwiftQwen3StreamingSessionTests: XCTestCase {
    func testFactoryCachesModelButKeepsSessionAudioIndependent() async throws {
        let transcriber = CapturingSpeechSwiftTranscriber()
        let loader = CapturingSpeechSwiftModelLoader(transcriber: transcriber)
        let modelCache = SpeechSwiftQwen3ModelCache(
            modelLoader: { modelURL, modelID in
                try await loader.load(modelURL: modelURL, modelID: modelID)
            }
        )
        let prewarmFactory = SpeechSwiftQwen3StreamingSessionFactory(modelCache: modelCache)
        let dictationFactory = SpeechSwiftQwen3StreamingSessionFactory(modelCache: modelCache)
        let modelURL = URL(fileURLWithPath: "/tmp/qwen3-asr-1.7b")

        let prewarmSession = try await prewarmFactory.makeSession(modelURL: modelURL, languageHint: "zh")
        _ = try await prewarmSession.addAudio(Array(repeating: 0.1, count: 12_800))
        let prewarmFinal = try await prewarmSession.finish()

        let dictationSession = try await dictationFactory.makeSession(modelURL: modelURL, languageHint: "zh")
        let dictationPartial = try await dictationSession.addAudio(Array(repeating: 0.2, count: 32_000))
        let dictationFinal = try await dictationSession.finish()

        XCTAssertEqual(prewarmFinal, Qwen3StreamingUpdate(transcript: "samples=12800", isFinal: true))
        XCTAssertEqual(dictationPartial, Qwen3StreamingUpdate(transcript: "samples=32000", isFinal: false))
        XCTAssertEqual(dictationFinal, Qwen3StreamingUpdate(transcript: "samples=32000", isFinal: true))
        let loadCount = await loader.loadCount
        let sampleCounts = await transcriber.sampleCounts
        XCTAssertEqual(loadCount, 1)
        XCTAssertEqual(sampleCounts, [12_800, 32_000, 32_000])
    }
}

private actor CapturingSpeechSwiftModelLoader {
    private let transcriber: any SpeechSwiftQwen3Transcribing
    private(set) var loadCount = 0

    init(transcriber: any SpeechSwiftQwen3Transcribing) {
        self.transcriber = transcriber
    }

    func load(
        modelURL: URL,
        modelID: String
    ) throws -> any SpeechSwiftQwen3Transcribing {
        loadCount += 1
        return transcriber
    }
}

private actor CapturingSpeechSwiftTranscriber: SpeechSwiftQwen3Transcribing {
    private(set) var sampleCounts: [Int] = []

    func transcribe(
        audio: [Float],
        sampleRate: Int,
        language: String?
    ) async throws -> String {
        sampleCounts.append(audio.count)
        return "samples=\(audio.count)"
    }
}
