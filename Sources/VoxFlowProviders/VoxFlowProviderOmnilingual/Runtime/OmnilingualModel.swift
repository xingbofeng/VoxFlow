import Foundation
import OmnilingualASR

public enum OmnilingualModel {
    public static let modelID = OmnilingualASRModel.defaultModelId
    public static let version = "speech-swift-coreml-int8-10s"

    public static func modelsExist(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard fileManager.fileExists(atPath: directory.path) else { return false }
        let required = [
            "config.json",
            "tokenizer.model",
            "omnilingual-ctc-300m-int8.mlmodelc",
        ]
        return required.allSatisfy {
            fileManager.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    public static func defaultDirectoryURL() -> URL {
        hubRepoDirectoryURL(base: modelsBaseDirectoryURL())
    }

    public static func legacyDirectoryURL() -> URL {
        modelsBaseDirectoryURL()
            .appendingPathComponent("omnilingual-asr-speech-swift", isDirectory: true)
    }

    private static func modelsBaseDirectoryURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("VoxFlow", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    private static func hubRepoDirectoryURL(base: URL) -> URL {
        modelID.split(separator: "/").reduce(
            base.appendingPathComponent("models", isDirectory: true)
        ) { partialResult, component in
            partialResult.appendingPathComponent(String(component), isDirectory: true)
        }
    }
}

public struct OmnilingualModelDownloadProgress: Sendable, Equatable {
    public let fractionCompleted: Double
    public let status: String

    public init(fractionCompleted: Double, status: String) {
        self.fractionCompleted = fractionCompleted
        self.status = status
    }
}

public protocol OmnilingualModelDownloading: Sendable {
    func download(
        progress: @escaping @MainActor @Sendable (OmnilingualModelDownloadProgress) -> Void
    ) async throws -> URL
}

public struct OmnilingualModelDownloader: OmnilingualModelDownloading, @unchecked Sendable {
    public init() {}

    public func download(
        progress: @escaping @MainActor @Sendable (OmnilingualModelDownloadProgress) -> Void
    ) async throws -> URL {
        let directory = OmnilingualModel.defaultDirectoryURL()
        _ = try await OmnilingualASRModel.fromPretrained(
            modelId: OmnilingualModel.modelID,
            cacheDir: directory,
            offlineMode: false,
            progressHandler: { fraction, status in
                Task { @MainActor in
                    progress(.init(
                        fractionCompleted: fraction,
                        status: status.isEmpty ? "准备 Omnilingual 模型" : status
                    ))
                }
            }
        )
        guard OmnilingualModel.modelsExist(at: directory) else {
            throw OmnilingualProviderError.modelNotInstalled
        }
        await progress(.init(fractionCompleted: 1, status: "模型已就绪"))
        return directory
    }
}
