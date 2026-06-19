import Foundation
import OmnilingualASR

public protocol OmnilingualTranscribing: Sendable {
    func transcribe(audio: [Float], sampleRate: Int, languageCode: String?) async throws -> String
}

public protocol OmnilingualTranscriberMaking: Sendable {
    func makeTranscriber(directoryURL: URL) async throws -> any OmnilingualTranscribing
}

private actor OmnilingualSpeechSwiftTranscriber: OmnilingualTranscribing {
    private let model: OmnilingualASRModel

    init(model: OmnilingualASRModel) {
        self.model = model
    }

    func transcribe(audio: [Float], sampleRate: Int, languageCode: String?) async throws -> String {
        try model.transcribeAudio(audio, sampleRate: sampleRate, language: languageCode)
    }
}

public struct OmnilingualTranscriberFactory: OmnilingualTranscriberMaking {
    public init() {}

    public func makeTranscriber(directoryURL: URL) async throws -> any OmnilingualTranscribing {
        guard OmnilingualModel.modelsExist(at: directoryURL) else {
            throw OmnilingualProviderError.modelNotInstalled
        }
        let model = try await OmnilingualASRModel.fromPretrained(
            modelId: OmnilingualModel.modelID,
            cacheDir: directoryURL,
            offlineMode: true
        )
        return OmnilingualSpeechSwiftTranscriber(model: model)
    }
}
