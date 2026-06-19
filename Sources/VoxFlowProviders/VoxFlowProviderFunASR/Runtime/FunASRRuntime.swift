import CSherpaOnnx
import Foundation

public enum FunASRRuntimeError: LocalizedError {
    case modelFilesMissing
    case recognizerCreationFailed
    case transcriptionFailed

    public var errorDescription: String? {
        switch self {
        case .modelFilesMissing:
            return "模型文件不完整，请重新下载。"
        case .recognizerCreationFailed:
            return "模型加载失败，请确认模型版本与运行时兼容。"
        case .transcriptionFailed:
            return "本地语音识别失败。"
        }
    }
}

public protocol FunASRTranscribing: Sendable {
    func transcribe(audio: [Float]) async throws -> String
}

public protocol FunASRTranscriberMaking: Sendable {
    func makeTranscriber(
        for variant: FunASRModelVariant,
        directoryURL: URL
    ) async throws -> any FunASRTranscribing
}

public final class FunASROnnxRecognizer: @unchecked Sendable {
    private let recognizer: OpaquePointer

    public init(variant: FunASRModelVariant, directoryURL: URL) throws {
        guard variant.modelsExist(at: directoryURL) else {
            throw FunASRRuntimeError.modelFilesMissing
        }

        let strings = [
            "",
            directoryURL.appendingPathComponent(variant.encoderPath).path,
            directoryURL.appendingPathComponent(variant.decoderPath).path,
            "",
            directoryURL.appendingPathComponent(variant.embeddingPath).path,
            directoryURL.appendingPathComponent(variant.tokenizerPath).path,
            "",
        ]
        let pointers = strings.map { strdup($0) }
        defer { pointers.forEach { free($0) } }

        var config = VoxSherpaModelConfig(
            type: VOX_SHERPA_FUNASR_NANO,
            model: UnsafePointer(pointers[0]),
            encoder: UnsafePointer(pointers[1]),
            decoder: UnsafePointer(pointers[2]),
            tokens: UnsafePointer(pointers[3]),
            embedding: UnsafePointer(pointers[4]),
            tokenizer: UnsafePointer(pointers[5]),
            language: UnsafePointer(pointers[6]),
            num_threads: 2
        )
        guard let recognizer = VoxSherpaCreateRecognizer(&config) else {
            throw FunASRRuntimeError.recognizerCreationFailed
        }
        self.recognizer = recognizer
    }

    deinit {
        VoxSherpaDestroyRecognizer(recognizer)
    }

    public func transcribe(samples: [Float], sampleRate: Int32 = 16_000) throws -> String {
        guard !samples.isEmpty else { return "" }
        guard let result = samples.withUnsafeBufferPointer({
            VoxSherpaTranscribe(recognizer, $0.baseAddress, Int32($0.count), sampleRate)
        }) else {
            throw FunASRRuntimeError.transcriptionFailed
        }
        defer { VoxSherpaFreeText(result) }
        return String(cString: result)
    }
}

private struct FunASROnnxTranscriber: FunASRTranscribing {
    let recognizer: FunASROnnxRecognizer

    func transcribe(audio: [Float]) async throws -> String {
        try recognizer.transcribe(samples: audio)
    }
}

public struct FunASRTranscriberFactory: FunASRTranscriberMaking {
    public init() {}

    public func makeTranscriber(
        for variant: FunASRModelVariant,
        directoryURL: URL
    ) async throws -> any FunASRTranscribing {
        try FunASROnnxTranscriber(
            recognizer: FunASROnnxRecognizer(variant: variant, directoryURL: directoryURL)
        )
    }
}
