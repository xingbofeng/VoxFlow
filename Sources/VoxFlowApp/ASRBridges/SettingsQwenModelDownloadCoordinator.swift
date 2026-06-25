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
    private let fileManager: FileManager

    init(
        asrManager: ASRManager,
        downloader: any Qwen3ModelDownloading,
        readinessPreparer: any Qwen3ModelReadinessPreparing = Qwen3ModelReadinessPreparer(),
        fileManager: FileManager = .default
    ) {
        self.asrManager = asrManager
        self.downloader = downloader
        self.readinessPreparer = readinessPreparer
        self.fileManager = fileManager
    }

    func downloadQwen3Model(
        size: ASRManager.ModelSize,
        progress: @escaping Qwen3ModelDownloader.ProgressHandler
    ) async throws -> URL {
        AppLogger.general.info("Settings Qwen3 download requested: size=\(size.rawValue)")
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
            AppLogger.general.error("Settings Qwen3 model missing required files: \(missingPaths.joined(separator: ","))")
            throw SettingsQwenModelDownloadError.missingRequiredFiles(missingPaths)
        }

        try await readinessPreparer.prepare(modelURL: modelURL, size: size)
        AppLogger.general.info("Settings Qwen3 model validated: size=\(size.rawValue), path=\(modelURL.path)")
        return modelURL
    }
}
