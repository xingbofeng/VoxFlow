import Foundation
import VoxFlowModelStore
import VoxFlowProviderFireRedASR

enum FireRedASRModelDownloadError: LocalizedError {
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
/// 活动下载，删除模型时可以中断 838 MB 归档的下载。
///
/// 与既有 sherpa 下载路径的差别：这条链路会校验归档与每个组件的 sha256、在发起网络请求前
/// 检查磁盘空间，并通过 `ModelAtomicInstaller` 原子换入。
final class FireRedASRLiveModelDownloader: FireRedASRModelDownloading, @unchecked Sendable {
    private let fileManager: FileManager
    private let transport: any ModelDownloadTransport
    private let activeDownloadLock = NSLock()
    private var activeDownloadID: UUID?
    private var activeDownloader: FireRedASRModelStoreDownloader?

    init(
        fileManager: FileManager = .default,
        transport: any ModelDownloadTransport = ModelURLSessionDownloadTransport()
    ) {
        self.fileManager = fileManager
        self.transport = transport
    }

    func download(
        progress: @escaping FireRedASRModelDownloadProgressHandler
    ) async throws -> URL {
        let paths: ApplicationSupportPaths
        do {
            paths = try ApplicationSupportPaths.live(fileManager: fileManager)
        } catch {
            throw FireRedASRModelDownloadError.applicationSupportUnavailable
        }
        try paths.ensureDirectories(fileManager: fileManager)

        let downloadID = UUID()
        let downloader = FireRedASRModelStoreDownloader(
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

    private func setActiveDownloader(_ downloader: FireRedASRModelStoreDownloader, id: UUID) {
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

    private func activeDownloaderSnapshot() -> FireRedASRModelStoreDownloader? {
        activeDownloadLock.lock()
        let downloader = activeDownloader
        activeDownloadLock.unlock()
        return downloader
    }
}
