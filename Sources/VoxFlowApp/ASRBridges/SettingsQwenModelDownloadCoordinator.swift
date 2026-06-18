import Foundation
import VoxFlowProviderQwen3

enum SettingsQwenModelDownloadError: LocalizedError, Equatable {
    case missingRequiredFiles([String])

    var errorDescription: String? {
        switch self {
        case .missingRequiredFiles(let paths):
            return "模型下载完成但缺少必要文件：\(paths.joined(separator: "、"))"
        }
    }
}

@MainActor
struct SettingsQwenModelDownloadCoordinator {
    private let asrManager: ASRManager
    private let downloader: any Qwen3ModelDownloading
    private let readinessPreparer: any Qwen3ModelReadinessPreparing
    private let runtimeProvisioner: any Qwen3MLXRuntimeProvisioning
    private let fileManager: FileManager

    init(
        asrManager: ASRManager,
        downloader: any Qwen3ModelDownloading,
        readinessPreparer: any Qwen3ModelReadinessPreparing = Qwen3ModelReadinessPreparer(),
        runtimeProvisioner: any Qwen3MLXRuntimeProvisioning = Qwen3MLXRuntimeProvisioner(),
        fileManager: FileManager = .default
    ) {
        self.asrManager = asrManager
        self.downloader = downloader
        self.readinessPreparer = readinessPreparer
        self.runtimeProvisioner = runtimeProvisioner
        self.fileManager = fileManager
    }

    func downloadQwen3Model(
        size: ASRManager.ModelSize,
        progress: @escaping Qwen3ModelDownloader.ProgressHandler
    ) async throws -> URL {
        if size == .size1_7B {
            _ = try await runtimeProvisioner.prepare()
        }
        let modelURL = try await downloader.download(
            manifest: Qwen3ModelManifest.manifest(for: size),
            progress: progress
        )
        let missingPaths = downloader.missingRequiredLocalPaths(
            size: size,
            at: modelURL,
            fileManager: fileManager
        )
        guard missingPaths.isEmpty else {
            throw SettingsQwenModelDownloadError.missingRequiredFiles(missingPaths)
        }

        try await readinessPreparer.prepare(modelURL: modelURL, size: size)
        asrManager.markQwen3ModelReady(at: modelURL.path, size: size)
        return modelURL
    }
}
