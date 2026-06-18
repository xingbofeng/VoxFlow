import FluidAudio
import Foundation

public enum ParaformerRuntimeError: LocalizedError {
    case modelFilesMissing
    case transcriptionFailed

    public var errorDescription: String? {
        switch self {
        case .modelFilesMissing:
            return "Paraformer 模型文件不完整，请重新下载。"
        case .transcriptionFailed:
            return "Paraformer 本地语音识别失败。"
        }
    }
}

public protocol ParaformerTranscribing: Sendable {
    func transcribe(audio: [Float]) async throws -> String
}

public protocol ParaformerTranscriberMaking: Sendable {
    func makeTranscriber(directoryURL: URL) async throws -> any ParaformerTranscribing
}

private struct ParaformerManagerTranscriber: ParaformerTranscribing {
    let manager: ParaformerManager

    func transcribe(audio: [Float]) async throws -> String {
        try await manager.transcribe(audio: audio)
    }
}

public struct ParaformerTranscriberFactory: ParaformerTranscriberMaking {
    public init() {}

    public func makeTranscriber(directoryURL: URL) async throws -> any ParaformerTranscribing {
        guard ParaformerModel.modelsExist(at: directoryURL) else {
            throw ParaformerRuntimeError.modelFilesMissing
        }
        let models = try ParaformerModels.load(
            from: directoryURL,
            precision: ParaformerModel.precision
        )
        return ParaformerManagerTranscriber(manager: ParaformerManager(models: models))
    }
}
