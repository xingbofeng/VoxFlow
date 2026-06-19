import Foundation
import VoxFlowModelStore

public enum Qwen3ModelCanaryAudio {
    public static let smokeCanary = ModelCanaryAudio(
        samples: Array(repeating: 0, count: 16_000),
        sampleRate: 16_000,
        expectedTokens: []
    )

    public static let speechSwiftRuntimeProbe = ModelCanaryAudio(
        samples: (0..<12_800).map { index in
            let time = Double(index) / 16_000
            return Float(0.08 * sin(2 * Double.pi * 440 * time))
        },
        sampleRate: 16_000,
        expectedTokens: []
    )
}

public actor Qwen3ModelRuntimePreparer: ModelRuntimePreparing {
    private let sessionFactory: any Qwen3StreamingSessionMaking
    private let languageHint: String?
    private var session: (any Qwen3StreamingSession)?

    public init(
        sessionFactory: any Qwen3StreamingSessionMaking = SpeechSwiftQwen3StreamingSessionFactory(),
        languageHint: String? = "zh"
    ) {
        self.sessionFactory = sessionFactory
        self.languageHint = languageHint
    }

    public func load(installation: ModelInstallation) async throws {
        session = try await sessionFactory.makeSession(
            modelURL: installation.installedRoot,
            languageHint: languageHint
        )
    }

    public func compile(installation: ModelInstallation) async throws {
        guard session != nil else {
            throw Qwen3ProviderError.preparationFailed("预热会话尚未加载。")
        }
    }

    public func transcribeCanary(
        installation: ModelInstallation,
        audio: ModelCanaryAudio
    ) async throws -> String {
        guard let session else {
            throw Qwen3ProviderError.preparationFailed("预热会话尚未加载。")
        }
        defer { self.session = nil }
        if !audio.samples.isEmpty {
            _ = try await session.addAudio(audio.samples)
        }
        return try await session.finish().transcript
    }
}
