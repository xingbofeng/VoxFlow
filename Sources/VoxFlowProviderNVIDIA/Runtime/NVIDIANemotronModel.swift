import FluidAudio
import Foundation

public enum NVIDIANemotronModel {
    public static let modelID = "nvidia-nemotron-asr-0.6b-coreml-1120ms"
    public static let version = "multilingual-1120ms-coreml"
    public static let defaultLanguageCode = "auto"
    public static let chunkMilliseconds = 1120

    public static func modelsExist(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard fileManager.fileExists(atPath: directory.path) else { return false }
        let required = [
            "preprocessor.mlmodelc",
            "encoder.mlmodelc",
            "metadata.json",
            "tokenizer.json",
        ]
        guard required.allSatisfy({ fileManager.fileExists(atPath: directory.appendingPathComponent($0).path) }) else {
            return false
        }
        let hasFusedDecode = [
            "decoder_joint_argmax.mlmodelc",
            "decoder_joint_noencproj.mlmodelc",
            "decoder_joint.mlmodelc",
        ].contains { fileManager.fileExists(atPath: directory.appendingPathComponent($0).path) }
        let hasBareDecode = fileManager.fileExists(atPath: directory.appendingPathComponent("decoder.mlmodelc").path)
            && fileManager.fileExists(atPath: directory.appendingPathComponent("joint.mlmodelc").path)
        return hasFusedDecode || hasBareDecode
    }
}

public struct NVIDIANemotronModelDownloadProgress: Sendable, Equatable {
    public let fractionCompleted: Double
    public let status: String

    public init(fractionCompleted: Double, status: String) {
        self.fractionCompleted = fractionCompleted
        self.status = status
    }
}

public protocol NVIDIANemotronModelDownloading: Sendable {
    func download(
        progress: @escaping @MainActor @Sendable (NVIDIANemotronModelDownloadProgress) -> Void
    ) async throws -> URL
}

public struct NVIDIANemotronModelDownloader: NVIDIANemotronModelDownloading, @unchecked Sendable {
    public init() {}

    public func download(
        progress: @escaping @MainActor @Sendable (NVIDIANemotronModelDownloadProgress) -> Void
    ) async throws -> URL {
        let directory = try await StreamingNemotronMultilingualAsrManager.downloadVariant(
            languageCode: NVIDIANemotronModel.defaultLanguageCode,
            chunkMs: NVIDIANemotronModel.chunkMilliseconds,
            progressHandler: { update in
                Task { @MainActor in
                    progress(.init(
                        fractionCompleted: update.fractionCompleted,
                        status: Self.statusText(for: update.phase)
                    ))
                }
            }
        )
        guard NVIDIANemotronModel.modelsExist(at: directory) else {
            throw NVIDIANemotronProviderError.modelNotInstalled
        }
        await progress(.init(fractionCompleted: 1, status: "模型已就绪"))
        return directory
    }

    private static func statusText(for phase: DownloadUtils.DownloadPhase) -> String {
        switch phase {
        case .listing:
            return "读取 Nemotron 模型清单"
        case .downloading(let completedFiles, let totalFiles):
            return "下载 Nemotron 模型 \(completedFiles)/\(totalFiles)"
        case .compiling(let modelName):
            return modelName.isEmpty ? "编译 Nemotron 模型" : "编译 \(modelName)"
        }
    }
}
