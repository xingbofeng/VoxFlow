import VoxFlowModelStore
@testable import VoxFlowProviderQwen3
import XCTest

final class Qwen3ModelRuntimePreparerTests: XCTestCase {
    func testPrewarmRuntimeLoadsModelAndTranscribesCanaryAudio() async throws {
        let session = CapturingPrewarmQwen3StreamingSession(
            final: Qwen3StreamingUpdate(transcript: "模型已预热", isFinal: true)
        )
        let factory = CapturingPrewarmQwen3StreamingSessionFactory(session: session)
        let preparer = Qwen3ModelRuntimePreparer(
            sessionFactory: factory,
            languageHint: "zh"
        )
        let installation = ModelInstallation(
            modelID: ModelID(rawValue: "qwen3-asr-0.6b"),
            version: "2026-06-17",
            installedRoot: URL(fileURLWithPath: "/tmp/qwen3-runtime-preparer", isDirectory: true)
        )
        let canary = ModelCanaryAudio(
            samples: [0.1, 0.2, 0.3],
            sampleRate: 16_000,
            expectedTokens: []
        )

        try await preparer.load(installation: installation)
        try await preparer.compile(installation: installation)
        let transcript = try await preparer.transcribeCanary(
            installation: installation,
            audio: canary
        )

        let acceptedSamples = await session.acceptedSamples
        let finishCount = await session.finishCount
        XCTAssertEqual(factory.modelURLs, [installation.installedRoot])
        XCTAssertEqual(factory.languageHints, ["zh"])
        XCTAssertEqual(acceptedSamples, [[0.1, 0.2, 0.3]])
        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(transcript, "模型已预热")

        do {
            try await preparer.compile(installation: installation)
            XCTFail("Expected the completed prewarm session to be released.")
        } catch {
            XCTAssertEqual(
                error as? Qwen3ProviderError,
                .preparationFailed("预热会话尚未加载。")
            )
        }
    }
}

private final class CapturingPrewarmQwen3StreamingSessionFactory: Qwen3StreamingSessionMaking, @unchecked Sendable {
    let session: CapturingPrewarmQwen3StreamingSession
    private(set) var modelURLs: [URL] = []
    private(set) var languageHints: [String?] = []

    init(session: CapturingPrewarmQwen3StreamingSession) {
        self.session = session
    }

    func makeSession(modelURL: URL, languageHint: String?) async throws -> any Qwen3StreamingSession {
        modelURLs.append(modelURL)
        languageHints.append(languageHint)
        return session
    }
}

private actor CapturingPrewarmQwen3StreamingSession: Qwen3StreamingSession {
    let final: Qwen3StreamingUpdate
    private(set) var acceptedSamples: [[Float]] = []
    private(set) var finishCount = 0

    init(final: Qwen3StreamingUpdate) {
        self.final = final
    }

    func addAudio(_ samples: [Float]) async throws -> Qwen3StreamingUpdate? {
        acceptedSamples.append(samples)
        return nil
    }

    func finish() async throws -> Qwen3StreamingUpdate {
        finishCount += 1
        return final
    }

    func cancel() async {}
}
