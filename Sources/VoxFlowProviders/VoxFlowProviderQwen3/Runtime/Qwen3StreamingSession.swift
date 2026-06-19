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
