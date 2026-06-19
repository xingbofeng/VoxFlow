import Foundation
import AudioCommon
import NemotronStreamingASR

public enum NVIDIANemotronModel {
    public static let modelID = NemotronStreamingASRModel.defaultModelId
    public static let version = "speech-swift-coreml-int8"
    public static let defaultLanguageCode = "auto"
    public static let chunkMilliseconds = 320

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
            "languages.json",
            "config.json",
        ]
        return required.allSatisfy {
            fileManager.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    public static func defaultDirectoryURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("VoxFlow", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("nemotron-streaming-asr-0.6b-speech-swift", isDirectory: true)
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
        let directory = NVIDIANemotronModel.defaultDirectoryURL()
        _ = try await NemotronStreamingASRModel.fromPretrained(
            modelId: NVIDIANemotronModel.modelID,
            progressHandler: { fraction, status in
                Task { @MainActor in
                    progress(.init(
                        fractionCompleted: fraction,
                        status: Self.statusText(status)
                    ))
                }
            }
        )
        let speechSwiftCache = try HuggingFaceDownloader.getCacheDirectory(
            for: NVIDIANemotronModel.modelID
        )
        if speechSwiftCache.path != directory.path {
            try FileManager.default.createDirectory(
                at: directory.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
            try FileManager.default.copyItem(at: speechSwiftCache, to: directory)
        }
        guard NVIDIANemotronModel.modelsExist(at: directory) else {
            throw NVIDIANemotronProviderError.modelNotInstalled
        }
        await progress(.init(fractionCompleted: 1, status: "模型已就绪"))
        return directory
    }

    private static func statusText(_ speechSwiftStatus: String) -> String {
        let lowercased = speechSwiftStatus.lowercased()
        if lowercased.contains("download") {
            return "下载 Nemotron speech-swift 模型"
        }
        if lowercased.contains("load") {
            return "加载 Nemotron CoreML 模型"
        }
        return speechSwiftStatus.isEmpty ? "准备 Nemotron 模型" : speechSwiftStatus
    }

}
