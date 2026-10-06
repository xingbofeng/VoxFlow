import Foundation
import VoxFlowModelStore

public struct XASRModelDownloadProgress: Equatable, Sendable {
    public let fileIndex: Int
    public let fileCount: Int
    public let fileName: String
    public let fileProgress: Double
    public let bytesWritten: Int64?
    public let totalBytes: Int64?

    public init(fileIndex: Int, fileCount: Int, fileName: String, fileProgress: Double,
        bytesWritten: Int64? = nil, totalBytes: Int64? = nil) {
        self.fileIndex = fileIndex
        self.fileCount = fileCount
        self.fileName = fileName
        self.fileProgress = fileProgress
        self.bytesWritten = bytesWritten
        self.totalBytes = totalBytes
    }

    public var overallProgress: Double {
        guard fileCount > 0 else { return 0 }
        return (Double(fileIndex) + fileProgress) / Double(fileCount)
    }
}

public typealias XASRModelDownloadProgressHandler = @Sendable (XASRModelDownloadProgress) async -> Void

public protocol XASRModelDownloading: Sendable {
    func download(progress: @escaping XASRModelDownloadProgressHandler) async throws -> URL
    func cancelDownload() async
    func expectedDownloadBytes() -> Int64
}

public extension XASRModelDownloading {
    func cancelDownload() async {}
    func expectedDownloadBytes() -> Int64 { XASRManifestCatalog.expectedDownloadBytes }
}

/// 同一实例把完整校验、下载和原子换入纳入一个任务。
/// 返回的是已校验的安装目录；真实 canary 与 ready 状态由 readiness runner 负责。
public actor XASRModelStoreDownloader: XASRModelDownloading {
    private let storeRoot: URL
    private let manifestProvider: @Sendable () throws -> ModelManifest
    private let downloader: ResumableModelDownloader
    private let availableDiskBytesProvider: @Sendable (URL) -> Int64?
    private var inFlight: Task<URL, Error>?

    public init(storeRoot: URL,
        transport: any ModelDownloadTransport = ModelURLSessionDownloadTransport(),
        manifestProvider: @escaping @Sendable () throws -> ModelManifest = XASRManifestCatalog.modelStoreManifest,
        availableDiskBytesProvider: @escaping @Sendable (URL) -> Int64? = { XASRModelStoreDownloader.availableDiskBytes(at: $0) }) {
        self.storeRoot = storeRoot
        self.manifestProvider = manifestProvider
        self.downloader = ResumableModelDownloader(transport: XASRStagedComponentTransport(transport: transport))
        self.availableDiskBytesProvider = availableDiskBytesProvider
    }

    public func download(progress: @escaping XASRModelDownloadProgressHandler) async throws -> URL {
        if let inFlight { return try await inFlight.value }
        let task = Task { try await self.performDownload(progress: progress) }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    private func performDownload(progress: @escaping XASRModelDownloadProgressHandler) async throws -> URL {
        try checkCancellation()
        let manifest = try manifestProvider()
        guard let first = manifest.components.first else { throw ModelInstallError.emptyManifest }
        let installedRoot = storeRoot
            .appendingPathComponent(first.modelID.rawValue, isDirectory: true)
            .appendingPathComponent(first.version, isDirectory: true)
        if FileManager.default.fileExists(atPath: installedRoot.path),
           let report = try? ModelIntegrityValidator().validate(
               manifest: manifest, installedRoot: installedRoot, runtimeVersion: first.runtimeVersion
           ), report.isValid {
            try checkCancellation()
            return installedRoot
        }

        // 可用容量已扣除旧安装和已有 stage；再保留完整新 stage 的预算。
        // 原子安装在同一卷重命名 stage，保留旧目录作 backup，不需要第二份新文件副本。
        let stagingRoot: URL
        do {
            stagingRoot = try await downloader.download(manifest: manifest, storeRoot: storeRoot,
                availableDiskBytes: availableDiskBytesProvider(storeRoot)) { update in
                await progress(XASRModelDownloadProgress(
                    fileIndex: manifest.components.firstIndex { $0.localPath == update.componentID.rawValue } ?? 0,
                    fileCount: manifest.components.count, fileName: update.componentID.rawValue,
                    fileProgress: update.fractionCompleted ?? 0, bytesWritten: update.bytesWritten, totalBytes: update.totalBytes))
            }
        } catch {
            try checkCancellation()
            throw error
        }
        try checkCancellation()
        return try ModelAtomicInstaller().install(
            manifest: manifest, stagingRoot: stagingRoot, storeRoot: storeRoot,
            runtimeVersion: first.runtimeVersion
        ).installedRoot
    }

    public func cancelDownload() async {
        guard let inFlight else { return }
        inFlight.cancel()
        await downloader.cancel()
    }

    private func checkCancellation() throws {
        if Task.isCancelled { throw ModelDownloadError.cancelled }
    }
    public nonisolated func expectedDownloadBytes() -> Int64 { XASRManifestCatalog.expectedDownloadBytes }
    public nonisolated static func availableDiskBytes(at url: URL, fileManager: FileManager = .default) -> Int64? {
        var candidate = url
        while !fileManager.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { return nil }
            candidate = parent
        }
        return (try? candidate.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }
}

/// 完成的 stage 文件不能请求 `Range: bytes=size-`（上游会返回 416）。
/// 此处只避免无内容的网络请求；全部组件仍须经原子安装器的 size/SHA256 校验。
private struct XASRStagedComponentTransport: ModelDownloadTransport {
    let transport: any ModelDownloadTransport

    func download(
        component: ModelComponentManifest,
        to destinationURL: URL,
        resumeFrom offset: Int64,
        progress: @escaping ModelDownloadProgressSink
    ) async throws {
        if offset == component.expectedSizeBytes {
            try await progress(ModelDownloadProgress(
                bytesWritten: offset,
                totalBytes: component.expectedSizeBytes,
                componentID: ModelComponentID(rawValue: component.localPath)
            ))
            return
        }
        try await transport.download(
            component: component, to: destinationURL, resumeFrom: offset, progress: progress
        )
    }
}
