import Foundation
import VoxFlowModelStore
import VoxFlowProviderXASR

enum XASRModelDownloadError: LocalizedError {
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
/// 活动下载，删除模型时可以中断 614.6 MB 的下载。
final class XASRLiveModelDownloader: XASRModelDownloading, @unchecked Sendable {
    private let fileManager: FileManager
    private let transport: any ModelDownloadTransport
    private let activeDownloadLock = NSLock()
    private var activeDownloadID: UUID?
    private var activeDownloader: XASRModelStoreDownloader?

    init(
        fileManager: FileManager = .default,
        transport: any ModelDownloadTransport = ModelURLSessionDownloadTransport()
    ) {
        self.fileManager = fileManager
        self.transport = transport
    }

    func download(progress: @escaping XASRModelDownloadProgressHandler) async throws -> URL {
        let paths: ApplicationSupportPaths
        do {
            paths = try ApplicationSupportPaths.live(fileManager: fileManager)
        } catch {
            throw XASRModelDownloadError.applicationSupportUnavailable
        }
        try paths.ensureDirectories(fileManager: fileManager)

        let downloadID = UUID()
        let downloader = XASRModelStoreDownloader(
            storeRoot: paths.modelsDirectory,
            transport: transport
        )
        setActiveDownloader(downloader, id: downloadID)
        defer { clearActiveDownloader(id: downloadID) }
        do {
            return try await downloader.download(progress: progress)
        } catch {
            throw XASRErrorPresentation.localizedError(error)
        }
    }

    func cancelDownload() async {
        await activeDownloaderSnapshot()?.cancelDownload()
    }

    private func setActiveDownloader(_ downloader: XASRModelStoreDownloader, id: UUID) {
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

    private func activeDownloaderSnapshot() -> XASRModelStoreDownloader? {
        activeDownloadLock.lock()
        let downloader = activeDownloader
        activeDownloadLock.unlock()
        return downloader
    }
}
