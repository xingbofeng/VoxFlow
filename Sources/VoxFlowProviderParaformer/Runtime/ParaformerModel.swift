import FluidAudio
import Foundation

public enum ParaformerModel {
    public static let modelID = "paraformer-large-zh-coreml-int8"
    public static let version = "paraformer-large-zh-coreml-int8"
    public static let precision: ParaformerPrecision = .int8

    public static func modelsExist(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard fileManager.fileExists(atPath: directory.path) else { return false }
        return ParaformerModels.modelsExist(at: directory, precision: precision)
    }
}

public struct ParaformerModelDownloadProgress: Sendable, Equatable {
    public let fractionCompleted: Double
    public let status: String

    public init(fractionCompleted: Double, status: String) {
        self.fractionCompleted = fractionCompleted
        self.status = status
    }
}

public protocol ParaformerModelDownloading: Sendable {
    func download(
        progress: @escaping @MainActor @Sendable (ParaformerModelDownloadProgress) -> Void
    ) async throws -> URL
}

public struct ParaformerModelDownloader: ParaformerModelDownloading, @unchecked Sendable {
    public init() {}

    public func download(
        progress: @escaping @MainActor @Sendable (ParaformerModelDownloadProgress) -> Void
    ) async throws -> URL {
        let directory = try await ParaformerModels.download(
            precision: ParaformerModel.precision,
            progressHandler: { update in
                Task { @MainActor in
                    progress(.init(
                        fractionCompleted: update.fractionCompleted,
                        status: Self.statusText(for: update.phase)
                    ))
                }
            }
        )
        guard ParaformerModel.modelsExist(at: directory) else {
            throw ParaformerProviderError.modelNotInstalled
        }
        await progress(.init(fractionCompleted: 1, status: "模型已就绪"))
        return directory
    }

    private static func statusText(for phase: DownloadUtils.DownloadPhase) -> String {
        switch phase {
        case .listing:
            return "读取 Paraformer 模型清单"
        case .downloading(let completedFiles, let totalFiles):
            return "下载 Paraformer 模型 \(completedFiles)/\(totalFiles)"
        case .compiling(let modelName):
            return modelName.isEmpty ? "编译 Paraformer 模型" : "编译 \(modelName)"
        }
    }
}
