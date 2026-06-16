import Foundation

enum SherpaASRModelVariant: String, CaseIterable, Sendable {
    case funASRInt8
    case funASRFP32
    case paraformerChinese
    case paraformerEnglish

    enum Family: Sendable {
        case funASR
        case paraformer
    }

    var family: Family {
        switch self {
        case .funASRInt8, .funASRFP32:
            return .funASR
        case .paraformerChinese, .paraformerEnglish:
            return .paraformer
        }
    }

    var archiveName: String {
        switch self {
        case .funASRInt8:
            return "sherpa-onnx-funasr-nano-int8-2025-12-30.tar.bz2"
        case .funASRFP32:
            return "sherpa-onnx-funasr-nano-2025-12-30.tar.bz2"
        case .paraformerChinese:
            return "sherpa-onnx-paraformer-zh-small-2024-03-09.tar.bz2"
        case .paraformerEnglish:
            return "sherpa-onnx-paraformer-en-2024-03-09.tar.bz2"
        }
    }

    var archiveURL: URL {
        URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/\(archiveName)")!
    }

    var directoryName: String {
        String(archiveName.dropLast(".tar.bz2".count))
    }

    var requiredPaths: [String] {
        switch self {
        case .funASRInt8:
            return [
                "encoder_adaptor.int8.onnx",
                "llm.int8.onnx",
                "embedding.int8.onnx",
                "Qwen3-0.6B/tokenizer.json",
                "Qwen3-0.6B/vocab.json",
                "Qwen3-0.6B/merges.txt",
            ]
        case .funASRFP32:
            return [
                "encoder_adaptor.onnx",
                "llm.fp32.onnx",
                "llm.fp32.data",
                "embedding.onnx",
                "Qwen3-0.6B/tokenizer.json",
                "Qwen3-0.6B/vocab.json",
                "Qwen3-0.6B/merges.txt",
            ]
        case .paraformerChinese, .paraformerEnglish:
            return ["model.int8.onnx", "tokens.txt"]
        }
    }

    var defaultDirectoryURL: URL {
        let base = (try? ApplicationSupportPaths.live().modelsDirectory)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("VoiceInputModels")
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    func modelsExist(
        at directory: URL? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        let root = directory ?? defaultDirectoryURL
        return requiredPaths.allSatisfy { relativePath in
            let path = root.appendingPathComponent(relativePath).path
            guard fileManager.isReadableFile(atPath: path),
                  let attributes = try? fileManager.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? NSNumber else {
                return false
            }
            return size.int64Value > 0
        }
    }

    var modelPath: String? {
        switch self {
        case .paraformerChinese, .paraformerEnglish:
            return "model.int8.onnx"
        default:
            return nil
        }
    }

    var encoderPath: String? {
        switch self {
        case .funASRInt8:
            return "encoder_adaptor.int8.onnx"
        case .funASRFP32:
            return "encoder_adaptor.onnx"
        case .paraformerChinese, .paraformerEnglish:
            return nil
        }
    }

    var decoderPath: String? {
        switch self {
        case .funASRInt8:
            return "llm.int8.onnx"
        case .funASRFP32:
            return "llm.fp32.onnx"
        case .paraformerChinese, .paraformerEnglish:
            return nil
        }
    }

    var tokensPath: String? {
        switch self {
        case .paraformerChinese, .paraformerEnglish:
            return "tokens.txt"
        case .funASRInt8, .funASRFP32:
            return nil
        }
    }

    var embeddingPath: String? {
        switch self {
        case .funASRInt8:
            return "embedding.int8.onnx"
        case .funASRFP32:
            return "embedding.onnx"
        default:
            return nil
        }
    }

    var tokenizerPath: String? {
        switch family {
        case .funASR:
            return "Qwen3-0.6B"
        case .paraformer:
            return nil
        }
    }
}
