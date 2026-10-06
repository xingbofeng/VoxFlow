import Foundation

public enum XASRModel {
    public static let encoderPath = "encoder-480ms.onnx"
    public static let decoderPath = "decoder-480ms.onnx"
    public static let joinerPath = "joiner-480ms.onnx"
    public static let tokensPath = "tokens.txt"
    public static let requiredPaths = [encoderPath, decoderPath, joinerPath, tokensPath]
    public static let numThreads: Int32 = 1
    public static let sampleRate = 16_000
    public static let tailPaddingSeconds: Double = 1

    public static func defaultDirectoryURL(modelsDirectory: URL) -> URL {
        let key = XASRManifestCatalog.modelInstallKey
        return modelsDirectory
            .appendingPathComponent(key.modelID.rawValue, isDirectory: true)
            .appendingPathComponent(key.version, isDirectory: true)
    }

    /// 仅检查文件布局；完整性和真实 canary 由 ModelStore/readiness 负责。
    public static func modelsExist(at directory: URL, fileManager: FileManager = .default) -> Bool {
        missingRequiredPaths(at: directory, fileManager: fileManager).isEmpty
    }

    public static func missingRequiredPaths(at directory: URL, fileManager: FileManager = .default) -> [String] {
        requiredPaths.filter { relativePath in
            let path = directory.appendingPathComponent(relativePath).path
            guard fileManager.isReadableFile(atPath: path),
                  let attributes = try? fileManager.attributesOfItem(atPath: path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber else { return true }
            return size.int64Value <= 0
        }
    }
}
