@preconcurrency import Qwen3ASR
import Foundation

public protocol SpeechSwiftQwen3Transcribing: Sendable {
    func transcribe(
        audio: [Float],
        sampleRate: Int,
        language: String?
    ) async throws -> String

    func transcribe(
        audio: [Float],
        sampleRate: Int,
        language: String?,
        context: String?
    ) async throws -> String
}

public extension SpeechSwiftQwen3Transcribing {
    func transcribe(
        audio: [Float],
        sampleRate: Int,
        language: String?,
        context: String?
    ) async throws -> String {
        try await transcribe(audio: audio, sampleRate: sampleRate, language: language)
    }
}

public struct SpeechSwiftQwen3StreamingSessionFactory: Qwen3StreamingSessionMaking {
    public static let smallModelID = "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
    public static let largeModelID = "aufklarer/Qwen3-ASR-1.7B-MLX-8bit"
    public static let defaultModelID = smallModelID

    private static let sharedModelCache = SpeechSwiftQwen3ModelCache { modelURL, modelID in
        try await SpeechSwiftQwen3ModelTranscriber(
            modelURL: modelURL,
            modelID: modelID
        )
    }

    private let modelID: String
    private let modelCache: SpeechSwiftQwen3ModelCache

    public init(modelID: String = Self.defaultModelID) {
        self.modelID = modelID
        self.modelCache = Self.sharedModelCache
    }

    init(
        modelID: String = Self.defaultModelID,
        modelCache: SpeechSwiftQwen3ModelCache
    ) {
        self.modelID = modelID
        self.modelCache = modelCache
    }

    public func makeSession(
        modelURL: URL,
        languageHint: String?
    ) async throws -> any Qwen3StreamingSession {
        try await makeSession(
            modelURL: modelURL,
            languageHint: languageHint,
            contextPrompt: nil
        )
    }

    public func makeSession(
        modelURL: URL,
        languageHint: String?,
        contextPrompt: String?
    ) async throws -> any Qwen3StreamingSession {
        let transcriber = try await modelCache.model(
            modelURL: modelURL,
            modelID: modelID
        )
        return SpeechSwiftQwen3StreamingSession(
            transcriber: transcriber,
            languageHint: languageHint,
            contextPrompt: contextPrompt
        )
    }
}

public actor SpeechSwiftQwen3StreamingSession: Qwen3StreamingSession {
    private static let partialTranscriptionSampleCount = 32_000
    private static let silencePeakThreshold: Float = 0.0005

    private let transcriber: any SpeechSwiftQwen3Transcribing
    private let languageHint: String?
    private let contextPrompt: String?
    private var samples: [Float] = []
    private var isCancelled = false

    public init(
        transcriber: any SpeechSwiftQwen3Transcribing,
        languageHint: String?,
        contextPrompt: String? = nil
    ) {
        self.transcriber = transcriber
        self.languageHint = languageHint
        self.contextPrompt = contextPrompt
    }

    public func addAudio(_ newSamples: [Float]) async throws -> Qwen3StreamingUpdate? {
        guard !isCancelled else { return nil }
        samples.append(contentsOf: newSamples)
        guard samples.count >= Self.partialTranscriptionSampleCount else { return nil }
        guard !Self.isSilence(samples) else { return nil }

        let transcript = try await transcriber.transcribe(
            audio: samples,
            sampleRate: 16_000,
            language: languageHint,
            context: contextPrompt
        )
        return Qwen3StreamingUpdate(transcript: transcript, isFinal: false)
    }

    public func finish() async throws -> Qwen3StreamingUpdate {
        guard !isCancelled else {
            return Qwen3StreamingUpdate(transcript: "", isFinal: true)
        }
        guard !Self.isSilence(samples) else {
            samples.removeAll(keepingCapacity: false)
            return Qwen3StreamingUpdate(transcript: "", isFinal: true)
        }

        let transcript = try await transcriber.transcribe(
            audio: samples,
            sampleRate: 16_000,
            language: languageHint,
            context: contextPrompt
        )
        samples.removeAll(keepingCapacity: false)
        return Qwen3StreamingUpdate(transcript: transcript, isFinal: true)
    }

    private static func isSilence(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else {
            return true
        }
        return samples.allSatisfy { abs($0) < silencePeakThreshold }
    }

    public func cancel() {
        isCancelled = true
        samples.removeAll(keepingCapacity: false)
    }
}

actor SpeechSwiftQwen3ModelCache {
    private struct Key: Hashable, Sendable {
        let modelURL: URL
        let modelID: String
    }

    private let modelLoader: @Sendable (URL, String) async throws -> any SpeechSwiftQwen3Transcribing
    private var models: [Key: any SpeechSwiftQwen3Transcribing] = [:]
    private var loadingTasks: [Key: Task<any SpeechSwiftQwen3Transcribing, Error>] = [:]

    init(
        modelLoader: @escaping @Sendable (URL, String) async throws -> any SpeechSwiftQwen3Transcribing
    ) {
        self.modelLoader = modelLoader
    }

    func model(
        modelURL: URL,
        modelID: String
    ) async throws -> any SpeechSwiftQwen3Transcribing {
        let key = Key(modelURL: modelURL.standardizedFileURL, modelID: modelID)
        if let model = models[key] {
            return model
        }
        if let loadingTask = loadingTasks[key] {
            return try await loadingTask.value
        }

        let loadingTask = Task {
            try await modelLoader(key.modelURL, key.modelID)
        }
        loadingTasks[key] = loadingTask
        do {
            let model = try await loadingTask.value
            models[key] = model
            loadingTasks[key] = nil
            return model
        } catch {
            loadingTasks[key] = nil
            throw error
        }
    }
}

private actor SpeechSwiftQwen3ModelTranscriber: SpeechSwiftQwen3Transcribing {
    private let model: Qwen3ASRModel

    init(modelURL: URL, modelID: String) async throws {
        self.model = try await Qwen3ASRModel.fromPretrained(
            modelId: modelID,
            cacheDir: modelURL,
            offlineMode: true
        )
    }

    func transcribe(
        audio: [Float],
        sampleRate: Int,
        language: String?
    ) -> String {
        transcribe(audio: audio, sampleRate: sampleRate, language: language, context: nil)
    }

    func transcribe(
        audio: [Float],
        sampleRate: Int,
        language: String?,
        context: String?
    ) -> String {
        model.transcribe(
            audio: audio,
            sampleRate: sampleRate,
            language: language,
            context: context
        )
    }
}

public enum Qwen3StreamingSessionFactoryProvider {
    public static func factory(
        for variant: Qwen3ModelVariant
    ) -> any Qwen3StreamingSessionMaking {
        switch variant {
        case .qwen06SpeechSwift4Bit:
            return SpeechSwiftQwen3StreamingSessionFactory(modelID: SpeechSwiftQwen3StreamingSessionFactory.smallModelID)
        case .qwen17SpeechSwift8Bit:
            return SpeechSwiftQwen3StreamingSessionFactory(modelID: SpeechSwiftQwen3StreamingSessionFactory.largeModelID)
        }
    }
}
