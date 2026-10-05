import CSherpaOnnx
import Foundation

public enum FireRedASRRuntimeError: Error, Sendable, Equatable {
    case modelFilesMissing
    case recognizerCreationFailed
    case transcriptionFailed
}

/// 一次「整段音频 → 文本」的转写能力。
///
/// 抽成协议是为了让 Session 可以在没有 1.24 GB 权重的情况下被完整测试：测试注入确定性 fake。
public protocol FireRedASRTranscribing: Sendable {
    func transcribe(audio: [Float]) async throws -> String
}

public protocol FireRedASRTranscriberMaking: Sendable {
    func makeTranscriber(directoryURL: URL) async throws -> any FireRedASRTranscribing
}

/// 基于 vendored sherpa-onnx 的 FireRedASR2-AED AED 识别器。
///
/// 走 `VOX_SHERPA_FIRE_RED_ASR`（AED：encoder + decoder 双文件），不是 CTC 分支。
public final class FireRedASROnnxRecognizer: @unchecked Sendable {
    private let recognizer: OpaquePointer
    private let lock = NSLock()

    public init(directoryURL: URL) throws {
        guard FireRedASRModel.modelsExist(at: directoryURL) else {
            throw FireRedASRRuntimeError.modelFilesMissing
        }

        // C 侧在创建时会复制需要的字符串，但指针必须在调用期间保持有效，因此用 strdup 后统一释放。
        let strings = [
            "",  // model：AED 路径不用单文件 model 槽位
            directoryURL.appendingPathComponent(FireRedASRModel.encoderPath).path,
            directoryURL.appendingPathComponent(FireRedASRModel.decoderPath).path,
            directoryURL.appendingPathComponent(FireRedASRModel.tokensPath).path,
            "",  // embedding
            "",  // tokenizer
            "",  // language：FireRedASR2-AED 不接受外部语言参数
        ]
        let pointers = strings.map { strdup($0) }
        defer { pointers.forEach { free($0) } }

        var config = VoxSherpaModelConfig(
            type: VOX_SHERPA_FIRE_RED_ASR,
            model: UnsafePointer(pointers[0]),
            encoder: UnsafePointer(pointers[1]),
            decoder: UnsafePointer(pointers[2]),
            tokens: UnsafePointer(pointers[3]),
            embedding: UnsafePointer(pointers[4]),
            tokenizer: UnsafePointer(pointers[5]),
            language: UnsafePointer(pointers[6]),
            num_threads: FireRedASRModel.numThreads
        )
        guard let recognizer = VoxSherpaCreateRecognizer(&config) else {
            throw FireRedASRRuntimeError.recognizerCreationFailed
        }
        self.recognizer = recognizer
    }

    deinit {
        VoxSherpaDestroyRecognizer(recognizer)
    }

    /// 一次整段解码。同一个 recognizer 每次调用都会新建 offline stream，因此可以跨段复用。
    public func transcribe(samples: [Float], sampleRate: Int32 = 16_000) throws -> String {
        guard !samples.isEmpty else { return "" }
        return try lock.withLock {
            guard let result = samples.withUnsafeBufferPointer({
                VoxSherpaTranscribe(recognizer, $0.baseAddress, Int32($0.count), sampleRate)
            }) else {
                throw FireRedASRRuntimeError.transcriptionFailed
            }
            defer { VoxSherpaFreeText(result) }
            return String(cString: result)
        }
    }
}

private struct FireRedASROnnxTranscriber: FireRedASRTranscribing {
    let recognizer: FireRedASROnnxRecognizer
    let sampleRate: Int

    func transcribe(audio: [Float]) async throws -> String {
        try recognizer.transcribe(samples: audio, sampleRate: Int32(sampleRate))
    }
}

public struct FireRedASRTranscriberFactory: FireRedASRTranscriberMaking {
    public init() {}

    public func makeTranscriber(directoryURL: URL) async throws -> any FireRedASRTranscribing {
        FireRedASROnnxTranscriber(
            recognizer: try FireRedASROnnxRecognizer(directoryURL: directoryURL),
            sampleRate: 16_000
        )
    }
}
