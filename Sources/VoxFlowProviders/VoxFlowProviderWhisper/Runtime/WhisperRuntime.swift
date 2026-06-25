import Foundation
@preconcurrency import WhisperKit

public enum WhisperTranscriptionTask: Sendable, Equatable {
    case transcribe
}

public struct WhisperTranscriptionRequest: Sendable, Equatable {
    public let audio: [Float]
    public let languageCode: String
    public let task: WhisperTranscriptionTask
    public let prompt: String?

    public init(
        audio: [Float],
        languageCode: String,
        task: WhisperTranscriptionTask,
        prompt: String? = nil
    ) {
        self.audio = audio
        self.languageCode = languageCode
        self.task = task
        self.prompt = prompt
    }
}

public typealias WhisperPartialHandler = @Sendable (String) -> Void

public protocol WhisperKitTranscribing: Sendable {
    func transcribe(
        _ request: WhisperTranscriptionRequest,
        onPartial: WhisperPartialHandler?
    ) async throws -> String
}

public protocol WhisperKitTranscriberMaking: Sendable {
    func makeTranscriber(
        for variant: WhisperKitModelVariant,
        directoryURL: URL
    ) async throws -> any WhisperKitTranscribing
}

private enum WhisperKitTranscriberError: LocalizedError {
    case transcriptionFailed

    var errorDescription: String? {
        "Whisper 转写失败。"
    }
}

private actor LocalWhisperKitTranscriber: WhisperKitTranscribing {
    private let whisperKit: WhisperKit

    init(directoryURL: URL) async throws {
        whisperKit = try await WhisperKit(
            WhisperKitConfig(
                modelFolder: directoryURL.path,
                verbose: false,
                load: true,
                download: false
            )
        )
    }

    func transcribe(
        _ request: WhisperTranscriptionRequest,
        onPartial: WhisperPartialHandler?
    ) async throws -> String {
        var options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: request.languageCode,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        if let prompt = request.prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty,
           let tokenizer = whisperKit.tokenizer {
            options.promptTokens = tokenizer
                .encode(text: " " + prompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
            options.usePrefillPrompt = true
        }
        let results = try await whisperKit.transcribe(
            audioArray: request.audio,
            decodeOptions: options,
            callback: { progress in
                let text = progress.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    onPartial?(text)
                }
                return nil
            }
        )
        guard !results.isEmpty else {
            throw WhisperKitTranscriberError.transcriptionFailed
        }
        return results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct LocalWhisperKitTranscriberFactory: WhisperKitTranscriberMaking {
    public init() {}

    public func makeTranscriber(
        for variant: WhisperKitModelVariant,
        directoryURL: URL
    ) async throws -> any WhisperKitTranscribing {
        try await LocalWhisperKitTranscriber(directoryURL: directoryURL)
    }
}
