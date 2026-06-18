@preconcurrency import FluidAudio
import Foundation

public struct Qwen3StreamingUpdate: Sendable, Equatable {
    public let transcript: String
    public let isFinal: Bool

    public init(transcript: String, isFinal: Bool) {
        self.transcript = transcript
        self.isFinal = isFinal
    }
}

public protocol Qwen3StreamingSession: Sendable {
    func addAudio(_ samples: [Float]) async throws -> Qwen3StreamingUpdate?
    func finish() async throws -> Qwen3StreamingUpdate
    func cancel() async
}

public protocol Qwen3StreamingSessionMaking: Sendable {
    func makeSession(modelURL: URL, languageHint: String?) async throws -> any Qwen3StreamingSession
}

public struct FluidAudioQwen3StreamingSessionFactory: Qwen3StreamingSessionMaking {
    public init() {}

    public func makeSession(modelURL: URL, languageHint: String?) async throws -> any Qwen3StreamingSession {
        guard #available(macOS 15, *) else {
            throw Qwen3ProviderError.unsupportedOS
        }

        let manager = Qwen3AsrManager()
        try await manager.loadModels(from: modelURL)
        let language = languageHint.flatMap(Qwen3AsrConfig.Language.init(rawValue:))
        let config = Qwen3StreamingConfig(
            minAudioSeconds: 1.0,
            chunkSeconds: 1.0,
            maxAudioSeconds: 30.0,
            language: language
        )
        return FluidAudioQwen3StreamingSession(
            manager: Qwen3StreamingManager(asrManager: manager, config: config)
        )
    }
}

@available(macOS 15, *)
private struct FluidAudioQwen3StreamingSession: Qwen3StreamingSession {
    let manager: Qwen3StreamingManager

    func addAudio(_ samples: [Float]) async throws -> Qwen3StreamingUpdate? {
        guard let result = try await manager.addAudio(samples) else { return nil }
        return Qwen3StreamingUpdate(transcript: result.transcript, isFinal: result.isFinal)
    }

    func finish() async throws -> Qwen3StreamingUpdate {
        let result = try await manager.finish()
        return Qwen3StreamingUpdate(transcript: result.transcript, isFinal: result.isFinal)
    }

    func cancel() async {
        await manager.reset()
    }
}
