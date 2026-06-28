import Foundation
import VoxFlowAudio

public actor Qwen3StreamingRuntimeDriver {
    private let modelURL: URL
    private let languageHint: String?
    private let contextPrompt: String?
    private let sessionFactory: any Qwen3StreamingSessionMaking
    private var session: (any Qwen3StreamingSession)?
    private var pendingSamples: [Float] = []
    private var latestTranscript = ""
    private var hasFinalUpdate = false
    private var hasFinished = false
    private var isCancelled = false

    public init(
        modelURL: URL,
        languageHint: String?,
        contextPrompt: String? = nil,
        sessionFactory: any Qwen3StreamingSessionMaking = SpeechSwiftQwen3StreamingSessionFactory()
    ) {
        self.modelURL = modelURL
        self.languageHint = languageHint
        self.contextPrompt = contextPrompt
        self.sessionFactory = sessionFactory
    }

    public func start() async throws {
        isCancelled = false
        hasFinalUpdate = false
        hasFinished = false
        latestTranscript = ""
        pendingSamples.removeAll(keepingCapacity: true)
        guard session == nil else { return }
        session = try await sessionFactory.makeSession(
            modelURL: modelURL,
            languageHint: languageHint,
            contextPrompt: contextPrompt
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
        remember(update)
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
            remember(pendingUpdate)
        }

        let update = try await session.finish()
        hasFinished = true
        hasFinalUpdate = true
        let normalizedTranscript = Self.deduplicatedTranscript(update.transcript)
        let normalizedUpdate = Qwen3StreamingUpdate(
            transcript: normalizedTranscript,
            isFinal: true
        )
        remember(normalizedUpdate)
        return normalizedUpdate
    }

    public func cancel() async {
        isCancelled = true
        latestTranscript = ""
        pendingSamples.removeAll(keepingCapacity: true)
        await session?.cancel()
    }

    private func remember(_ update: Qwen3StreamingUpdate?) {
        guard let text = update?.transcript.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return
        }
        latestTranscript = text
    }

    private func minimumStreamingSampleCount(for frame: AudioFrame) -> Int {
        max(frame.sampleRate * 2, 1)
    }

    private static func deduplicatedTranscript(_ transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if let sentenceCollapsed = collapseRepeatedSentenceSequence(trimmed) {
            return sentenceCollapsed
        }
        if let wordCollapsed = collapseRepeatedWordSequence(trimmed) {
            return wordCollapsed
        }
        return trimmed
    }

    private static func collapseRepeatedSentenceSequence(_ text: String) -> String? {
        let terminators = Set("。！？!?；;\n")
        var current = ""
        var sentences: [String] = []
        for character in text {
            current.append(character)
            if terminators.contains(character) {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    sentences.append(sentence)
                }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            sentences.append(tail)
        }
        guard sentences.count >= 2, sentences.count.isMultiple(of: 2) else {
            return nil
        }
        let midpoint = sentences.count / 2
        let firstHalf = Array(sentences[..<midpoint])
        let secondHalf = Array(sentences[midpoint...])
        guard firstHalf == secondHalf else {
            return nil
        }
        return firstHalf.joined()
    }

    private static func collapseRepeatedWordSequence(_ text: String) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 2, words.count.isMultiple(of: 2) else {
            return nil
        }
        let midpoint = words.count / 2
        let firstHalf = Array(words[..<midpoint])
        let secondHalf = Array(words[midpoint...])
        guard firstHalf == secondHalf else {
            return nil
        }
        return firstHalf.joined(separator: " ")
    }
}
