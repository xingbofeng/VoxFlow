import Foundation
import AudioCommon
import ParakeetStreamingASR

public enum ParakeetModel {
    public static let modelID = ParakeetStreamingASRModel.defaultModelId
    public static let version = "speech-swift-coreml-int8"

    public static func modelsExist(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard fileManager.fileExists(atPath: directory.path) else { return false }
        let required = [
            "encoder.mlmodelc",
            "decoder.mlmodelc",
            "joint.mlmodelc",
            "vocab.json",
            "config.json",
        ]
        return required.allSatisfy {
            fileManager.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    public static func defaultDirectoryURL() -> URL {
        (try? HuggingFaceDownloader.getCacheDirectory(for: modelID))
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("parakeet-streaming-speech-swift", isDirectory: true)
    }
}

public struct ParakeetModelDownloadProgress: Sendable, Equatable {
    public let fractionCompleted: Double
    public let status: String

    public init(fractionCompleted: Double, status: String) {
        self.fractionCompleted = fractionCompleted
        self.status = status
    }
}

public protocol ParakeetModelDownloading: Sendable {
    func download(
        progress: @escaping @MainActor @Sendable (ParakeetModelDownloadProgress) -> Void
    ) async throws -> URL
}

public struct ParakeetModelDownloader: ParakeetModelDownloading, @unchecked Sendable {
    public init() {}

    public func download(
        progress: @escaping @MainActor @Sendable (ParakeetModelDownloadProgress) -> Void
    ) async throws -> URL {
        _ = try await ParakeetStreamingASRModel.fromPretrained(
            modelId: ParakeetModel.modelID,
            progressHandler: { fraction, status in
                Task { @MainActor in
                    progress(.init(
                        fractionCompleted: fraction,
                        status: status.isEmpty ? "准备 Parakeet 模型" : status
                    ))
                }
            }
        )
        let directory = ParakeetModel.defaultDirectoryURL()
        guard ParakeetModel.modelsExist(at: directory) else {
            throw ParakeetProviderError.modelNotInstalled
        }
        await progress(.init(fractionCompleted: 1, status: "模型已就绪"))
        return directory
    }
}
