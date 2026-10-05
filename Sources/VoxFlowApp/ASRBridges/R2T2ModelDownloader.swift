import Foundation
import VoxFlowModelStore
import VoxFlowProviderR2T2

enum R2T2ModelDownloadError: LocalizedError {
    case applicationSupportUnavailable

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return L10n.localize("app.paths.application_support_unavailable",
                comment: "Application Support directory unavailable")
        }
    }
}

/// 把 Provider 的 ModelStore 下载器接到 App 的模型目录上。
///
/// Provider 侧只认 `storeRoot`，目录解析与生命周期留在 App 层；`cancelDownload()` 作用于当前
/// 活动下载，删除模型时可以中断 2.4 GB 的下载。
final class R2T2LiveModelDownloader: R2T2ModelDownloading, @unchecked Sendable {
    private let fileManager: FileManager
    private let transport: any ModelDownloadTransport
    private let activeDownloadLock = NSLock()
    private var activeDownloadID: UUID?
    private var activeDownloader: R2T2ModelStoreDownloader?

    init(
        fileManager: FileManager = .default,
        transport: any ModelDownloadTransport = ModelURLSessionDownloadTransport()
    ) {
        self.fileManager = fileManager
        self.transport = transport
    }

    func download(progress: @escaping R2T2ModelDownloadProgressHandler) async throws -> URL {
        let paths: ApplicationSupportPaths
        do {
            paths = try ApplicationSupportPaths.live(fileManager: fileManager)
        } catch {
            throw R2T2ModelDownloadError.applicationSupportUnavailable
        }
        try paths.ensureDirectories(fileManager: fileManager)

        let downloadID = UUID()
        let downloader = R2T2ModelStoreDownloader(
            storeRoot: paths.modelsDirectory,
            transport: transport
        )
        setActiveDownloader(downloader, id: downloadID)
        defer { clearActiveDownloader(id: downloadID) }
        return try await downloader.download(progress: progress)
    }

    func cancelDownload() async {
        await activeDownloaderSnapshot()?.cancelDownload()
    }

    private func setActiveDownloader(_ downloader: R2T2ModelStoreDownloader, id: UUID) {
        activeDownloadLock.lock()
        activeDownloadID = id
        activeDownloader = downloader
        activeDownloadLock.unlock()
    }

    private func clearActiveDownloader(id: UUID) {
        activeDownloadLock.lock()
        if activeDownloadID == id {
            activeDownloadID = nil
            activeDownloader = nil
        }
        activeDownloadLock.unlock()
    }

    private func activeDownloaderSnapshot() -> R2T2ModelStoreDownloader? {
        activeDownloadLock.lock()
        let downloader = activeDownloader
        activeDownloadLock.unlock()
        return downloader
    }
}
