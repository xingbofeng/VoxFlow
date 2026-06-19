import FluidAudio
import Foundation

public enum SenseVoiceRuntimeError: LocalizedError {
    case modelFilesMissing
    case transcriptionFailed

    public var errorDescription: String? {
        switch self {
        case .modelFilesMissing:
            return "SenseVoice 模型文件不完整，请重新下载。"
        case .transcriptionFailed:
            return "SenseVoice 本地语音识别失败。"
        }
    }
}

public protocol SenseVoiceTranscribing: Sendable {
    func transcribe(audio: [Float]) async throws -> String
}

public protocol SenseVoiceTranscriberMaking: Sendable {
    func makeTranscriber(directoryURL: URL) async throws -> any SenseVoiceTranscribing
}

private struct SenseVoiceManagerTranscriber: SenseVoiceTranscribing {
    let manager: SenseVoiceManager

    func transcribe(audio: [Float]) async throws -> String {
        try await manager.transcribe(audio: audio)
    }
}

public struct SenseVoiceTranscriberFactory: SenseVoiceTranscriberMaking {
    public init() {}

    public func makeTranscriber(directoryURL: URL) async throws -> any SenseVoiceTranscribing {
        guard SenseVoiceModel.modelsExist(at: directoryURL) else {
            throw SenseVoiceRuntimeError.modelFilesMissing
        }
        let models = try SenseVoiceModels.load(
            from: directoryURL,
            precision: SenseVoiceModel.precision
        )
        return SenseVoiceManagerTranscriber(manager: SenseVoiceManager(models: models))
    }
}
