import Foundation

enum SherpaASRModelVariant: String, CaseIterable, Sendable {
    case funASRInt8
    case funASRFP32

    enum Family: Sendable {
        case funASR
    }

    var family: Family {
        switch self {
        case .funASRInt8, .funASRFP32:
            return .funASR
        }
    }

    var archiveName: String {
        switch self {
        case .funASRInt8:
            return "sherpa-onnx-funasr-nano-int8-2025-12-30.tar.bz2"
        case .funASRFP32:
            return "sherpa-onnx-funasr-nano-2025-12-30.tar.bz2"
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
        }
    }

    var defaultDirectoryURL: URL {
        let base = (try? ApplicationSupportPaths.live().modelsDirectory)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("VoxFlowModels")
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    var partialArchiveURL: URL {
        defaultDirectoryURL
            .deletingLastPathComponent()
            .appendingPathComponent(".downloads", isDirectory: true)
            .appendingPathComponent("\(archiveName).partial", isDirectory: false)
    }

    func modelsExist(
        at directory: URL? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        let root = directory ?? defaultDirectoryURL
        for relativePath in requiredPaths {
            let path = root.appendingPathComponent(relativePath).path
            if !fileManager.isReadableFile(atPath: path) {
                AppLogger.general.warning(
                    "SherpaASRModel model missing path variant=\(self.rawValue) path=\(relativePath)"
                )
                return false
            }
            guard let attributes = try? fileManager.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? NSNumber, size.int64Value > 0 else {
                AppLogger.general.warning(
                    "SherpaASRModel model invalid file variant=\(self.rawValue) path=\(relativePath)"
                )
                return false
            }
        }
        AppLogger.general.debug("SherpaASRModel model exists variant=\(self.rawValue)")
        return true
    }

    var modelPath: String? {
        nil
    }

    var encoderPath: String? {
        switch self {
        case .funASRInt8:
            return "encoder_adaptor.int8.onnx"
        case .funASRFP32:
            return "encoder_adaptor.onnx"
        }
    }

    var decoderPath: String? {
        switch self {
        case .funASRInt8:
            return "llm.int8.onnx"
        case .funASRFP32:
            return "llm.fp32.onnx"
        }
    }

    var tokensPath: String? {
        nil
    }

    var embeddingPath: String? {
        switch self {
        case .funASRInt8:
            return "embedding.int8.onnx"
        case .funASRFP32:
            return "embedding.onnx"
        }
    }

    var tokenizerPath: String? {
        "Qwen3-0.6B"
    }
}
