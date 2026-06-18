import Foundation
import VoxFlowAudio

public actor Qwen3StreamingRuntimeDriver {
    private let modelURL: URL
    private let languageHint: String?
    private let sessionFactory: any Qwen3StreamingSessionMaking
    private var session: (any Qwen3StreamingSession)?
    private var pendingSamples: [Float] = []
    private var hasFinalUpdate = false
    private var hasFinished = false
    private var isCancelled = false

    public init(
        modelURL: URL,
        languageHint: String?,
        sessionFactory: any Qwen3StreamingSessionMaking = FluidAudioQwen3StreamingSessionFactory()
    ) {
        self.modelURL = modelURL
        self.languageHint = languageHint
        self.sessionFactory = sessionFactory
    }

    public func start() async throws {
        isCancelled = false
        hasFinalUpdate = false
        hasFinished = false
        pendingSamples.removeAll(keepingCapacity: true)
        guard session == nil else { return }
        session = try await sessionFactory.makeSession(
            modelURL: modelURL,
            languageHint: languageHint
        )
    }

    public func accept(_ frame: AudioFrame) async throws -> Qwen3StreamingUpdate? {
        guard !isCancelled, !hasFinalUpdate else { return nil }
        guard let session else {
            throw Qwen3ProviderError.preparationFailed("Qwen3-ASR session has not started.")
        }

        pendingSamples.append(contentsOf: frame.samples)
        guard pendingSamples.count >= minimumStreamingSampleCount(for: frame) else {
            return nil
        }

        let samples = pendingSamples
        pendingSamples.removeAll(keepingCapacity: true)
        let update = try await session.addAudio(samples)
        guard !isCancelled, !hasFinalUpdate else { return nil }
        if update?.isFinal == true {
            hasFinalUpdate = true
        }
        return update
    }

    public func finish() async throws -> Qwen3StreamingUpdate? {
        guard !isCancelled, !hasFinished else { return nil }
        guard let session else {
            throw Qwen3ProviderError.preparationFailed("Qwen3-ASR session has not started.")
        }

        if !pendingSamples.isEmpty {
            let samples = pendingSamples
            pendingSamples.removeAll(keepingCapacity: true)
            let pendingUpdate = try await session.addAudio(samples)
            guard !isCancelled else { return nil }
            if pendingUpdate?.isFinal == true {
                hasFinalUpdate = true
            }
        }

        let update = try await session.finish()
        hasFinished = true
        hasFinalUpdate = true
        return update
    }

    public func cancel() async {
        isCancelled = true
        pendingSamples.removeAll(keepingCapacity: true)
        await session?.cancel()
    }

    private func minimumStreamingSampleCount(for frame: AudioFrame) -> Int {
        max(frame.sampleRate * 2, 1)
    }
}
