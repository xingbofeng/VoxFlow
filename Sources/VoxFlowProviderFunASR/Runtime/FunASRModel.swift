import Foundation

public enum FunASRModelVariant: String, CaseIterable, Sendable {
    case int8
    case fp32

    public var archiveName: String {
        switch self {
        case .int8:
            return "sherpa-onnx-funasr-nano-int8-2025-12-30.tar.bz2"
        case .fp32:
            return "sherpa-onnx-funasr-nano-2025-12-30.tar.bz2"
        }
    }

    public var archiveURL: URL {
        URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/\(archiveName)")!
    }

    public var directoryName: String {
        String(archiveName.dropLast(".tar.bz2".count))
    }

    public var requiredPaths: [String] {
        switch self {
        case .int8:
            return [
                "encoder_adaptor.int8.onnx",
                "llm.int8.onnx",
                "embedding.int8.onnx",
                "Qwen3-0.6B/tokenizer.json",
                "Qwen3-0.6B/vocab.json",
                "Qwen3-0.6B/merges.txt",
            ]
        case .fp32:
            return [
                "encoder_adaptor.onnx",
                "llm.fp32.onnx",
                "llm.fp32.data",
                "embedding.onnx",
                "Qwen3-0.6B/tokenizer.json",
                "Qwen3-0.6B/vocab.json",
                "Qwen3-0.6B/merges.txt",
            ]
        }
    }

    public func defaultDirectoryURL(modelsDirectory: URL) -> URL {
        modelsDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    public func modelsExist(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        requiredPaths.allSatisfy { relativePath in
            let path = directory.appendingPathComponent(relativePath).path
            guard fileManager.isReadableFile(atPath: path),
                  let attributes = try? fileManager.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? NSNumber else {
                return false
            }
            return size.int64Value > 0
        }
    }

    var encoderPath: String {
        switch self {
        case .int8:
            return "encoder_adaptor.int8.onnx"
        case .fp32:
            return "encoder_adaptor.onnx"
        }
    }

    var decoderPath: String {
        switch self {
        case .int8:
            return "llm.int8.onnx"
        case .fp32:
            return "llm.fp32.onnx"
        }
    }

    var embeddingPath: String {
        switch self {
        case .int8:
            return "embedding.int8.onnx"
        case .fp32:
            return "embedding.onnx"
        }
    }

    var tokenizerPath: String {
        "Qwen3-0.6B"
    }
}
