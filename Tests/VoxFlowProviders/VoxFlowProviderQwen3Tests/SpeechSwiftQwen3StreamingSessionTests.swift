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

    func testFactoryPassesContextPromptToSpeechSwiftTranscriber() async throws {
        let transcriber = CapturingSpeechSwiftTranscriber()
        let modelCache = SpeechSwiftQwen3ModelCache { _, _ in transcriber }
        let factory = SpeechSwiftQwen3StreamingSessionFactory(modelCache: modelCache)
        let modelURL = URL(fileURLWithPath: "/tmp/qwen3-asr-0.6b")

        let session = try await factory.makeSession(
            modelURL: modelURL,
            languageHint: "zh",
            contextPrompt: "PostgreSQL, speech-swift"
        )
        _ = try await session.addAudio(Array(repeating: 0.1, count: 32_000))
        _ = try await session.finish()

        let contexts = await transcriber.contexts
        XCTAssertEqual(contexts, ["PostgreSQL, speech-swift", "PostgreSQL, speech-swift"])
    }

    func testSilenceDoesNotLeakContextPromptIntoTranscript() async throws {
        let transcriber = CapturingSpeechSwiftTranscriber()
        let session = SpeechSwiftQwen3StreamingSession(
            transcriber: transcriber,
            languageHint: "zh",
            contextPrompt: "码上写, 随声写, 语音输入"
        )

        let partial = try await session.addAudio(Array(repeating: 0, count: 32_000))
        let final = try await session.finish()

        XCTAssertNil(partial)
        XCTAssertEqual(final, Qwen3StreamingUpdate(transcript: "", isFinal: true))
        let sampleCounts = await transcriber.sampleCounts
        let contexts = await transcriber.contexts
        XCTAssertTrue(sampleCounts.isEmpty)
        XCTAssertTrue(contexts.isEmpty)
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
    private(set) var contexts: [String?] = []

    func transcribe(
        audio: [Float],
        sampleRate: Int,
        language: String?
    ) async throws -> String {
        sampleCounts.append(audio.count)
        return "samples=\(audio.count)"
    }

    func transcribe(
        audio: [Float],
        sampleRate: Int,
        language: String?,
        context: String?
    ) async throws -> String {
        contexts.append(context)
        return try await transcribe(audio: audio, sampleRate: sampleRate, language: language)
    }
}
