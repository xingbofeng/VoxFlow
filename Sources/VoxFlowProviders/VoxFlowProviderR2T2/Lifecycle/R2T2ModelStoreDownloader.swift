import Foundation
import VoxFlowModelStore

/// R2T2 模型下载进度，供设置页展示。
public struct R2T2ModelDownloadProgress: Equatable, Sendable {
    public let fileIndex: Int
    public let fileCount: Int
    public let fileName: String
    public let fileProgress: Double
    public let bytesWritten: Int64?
    public let totalBytes: Int64?

    public init(
        fileIndex: Int,
        fileCount: Int,
        fileName: String,
        fileProgress: Double,
        bytesWritten: Int64? = nil,
        totalBytes: Int64? = nil
    ) {
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

public typealias R2T2ModelDownloadProgressHandler = @Sendable (R2T2ModelDownloadProgress) async -> Void

/// Provider 侧的模型下载入口，App 只依赖这个协议。
public protocol R2T2ModelDownloading: Sendable {
    /// 下载并原子安装模型，返回安装后的模型目录。
    func download(progress: @escaping R2T2ModelDownloadProgressHandler) async throws -> URL

    func cancelDownload() async

    /// 全部组件大小之和。
    func expectedDownloadBytes() -> Int64
}

public extension R2T2ModelDownloading {
    func cancelDownload() async {}

    func expectedDownloadBytes() -> Int64 {
        R2T2ManifestCatalog.expectedDownloadBytes
    }
}

/// 基于 ModelStore 的 R2T2 下载器：复用共享层的断点续传下载、校验与原子安装。
///
/// R2T2 权重约 2.46 GB，安装完成后会先校验已有目录，命中有效安装就直接复用，
/// 避免重复下载。
public struct R2T2ModelStoreDownloader: R2T2ModelDownloading {
    private let storeRoot: URL
    private let manifestProvider: @Sendable () throws -> ModelManifest
    private let downloader: ResumableModelDownloader

    public init(
        storeRoot: URL,
        transport: any ModelDownloadTransport = ModelURLSessionDownloadTransport(),
        manifestProvider: @escaping @Sendable () throws -> ModelManifest = R2T2ManifestCatalog.modelStoreManifest
    ) {
        self.storeRoot = storeRoot
        self.manifestProvider = manifestProvider
        self.downloader = ResumableModelDownloader(transport: transport)
    }

    public func download(progress: @escaping R2T2ModelDownloadProgressHandler) async throws -> URL {
        let manifest = try manifestProvider()
        if let installedRoot = existingValidInstallationRoot(for: manifest) {
            return installedRoot
        }

        let componentPaths = manifest.components.map(\.localPath)
        let stagingRoot = try await downloader.download(
            manifest: manifest,
            storeRoot: storeRoot,
            availableDiskBytes: Self.availableDiskBytes(at: storeRoot)
        ) { update in
            await progress(Self.progress(from: update, componentPaths: componentPaths))
        }

        return try ModelAtomicInstaller().install(
            manifest: manifest,
            stagingRoot: stagingRoot,
            storeRoot: storeRoot,
            runtimeVersion: manifest.components.first?.runtimeVersion ?? ""
        ).installedRoot
    }

    public func cancelDownload() async {
        await downloader.cancel()
    }

    /// `storeRoot` 所在卷的可用空间。
    ///
    /// `ResumableModelDownloader.precheckDisk` 只在拿到可用空间时才生效，传 `nil` 等于跳过检查，
    /// 2.4 GB 的权重会下载到一半才因为空间不足失败。首次安装时 `storeRoot` 可能还不存在，
    /// 所以逐级向上取第一个存在的祖先目录再问容量。
    static func availableDiskBytes(
        at url: URL,
        fileManager: FileManager = .default
    ) -> Int64? {
        var candidate = url
        while !fileManager.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { return nil }
            candidate = parent
        }
        let values = try? candidate.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage
    }

    private func existingValidInstallationRoot(for manifest: ModelManifest) -> URL? {        guard let first = manifest.components.first else { return nil }
        let candidate = storeRoot
            .appendingPathComponent(first.modelID.rawValue, isDirectory: true)
            .appendingPathComponent(first.version, isDirectory: true)

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        let report = try? ModelIntegrityValidator().validate(
            manifest: manifest,
            installedRoot: candidate,
            runtimeVersion: first.runtimeVersion
        )
        return report?.isValid == true ? candidate : nil
    }

    private static func progress(
        from update: ModelDownloadProgress,
        componentPaths: [String]
    ) -> R2T2ModelDownloadProgress {
        let fileIndex = componentPaths.firstIndex(of: update.componentID.rawValue) ?? 0
        return R2T2ModelDownloadProgress(
            fileIndex: fileIndex,
            fileCount: max(componentPaths.count, 1),
            fileName: update.componentID.rawValue,
            fileProgress: update.fractionCompleted ?? 0,
            bytesWritten: update.bytesWritten,
            totalBytes: update.totalBytes
        )
    }
}
