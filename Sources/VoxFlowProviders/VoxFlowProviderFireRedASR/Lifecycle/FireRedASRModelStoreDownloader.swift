import CryptoKit
import Foundation
import VoxFlowModelStore

/// FireRedASR2-AED 模型下载进度。
public struct FireRedASRModelDownloadProgress: Equatable, Sendable {
    public let fractionCompleted: Double
    public let bytesWritten: Int64?
    public let totalBytes: Int64?

    public init(
        fractionCompleted: Double,
        bytesWritten: Int64? = nil,
        totalBytes: Int64? = nil
    ) {
        self.fractionCompleted = fractionCompleted
        self.bytesWritten = bytesWritten
        self.totalBytes = totalBytes
    }
}

public typealias FireRedASRModelDownloadProgressHandler =
    @Sendable (FireRedASRModelDownloadProgress) async -> Void

/// Provider 侧的模型下载入口，App 只依赖这个协议。
public protocol FireRedASRModelDownloading: Sendable {
    /// 下载、解包、逐文件校验并原子安装，返回安装后的模型目录。
    func download(
        progress: @escaping FireRedASRModelDownloadProgressHandler
    ) async throws -> URL

    func cancelDownload() async

    /// 下载归档的大小，用于设置页展示。
    func expectedDownloadBytes() -> Int64
}

public extension FireRedASRModelDownloading {
    func cancelDownload() async {}

    func expectedDownloadBytes() -> Int64 {
        FireRedASRModel.archiveBytes
    }
}

public enum FireRedASRModelDownloadError: LocalizedError, Equatable, Sendable {
    case archiveChecksumMismatch(expected: String, actual: String)
    case extractionFailed(String)
    case unexpectedArchiveLayout(missingPaths: [String])

    public var errorDescription: String? {
        switch self {
        case .archiveChecksumMismatch:
            return "模型压缩包校验不通过，可能下载中断或被篡改。请重试下载。"
        case .extractionFailed(let message):
            return "模型压缩包解包失败。详情：\(message)"
        case .unexpectedArchiveLayout(let missingPaths):
            return "模型压缩包内容与清单不一致，缺少：\(missingPaths.joined(separator: "、"))。"
        }
    }
}

/// 基于 ModelStore 的 FireRedASR2-AED 下载器。
///
/// 上游资产是**单个 tar.bz2**，所以流程不能直接用「逐组件下载」：
///
/// 1. 已有通过校验的安装 → 直接复用，不重复下载（约 1.24 GB 权重 + 838 MB 归档）。
/// 2. 下载前先查空间：需要**同时**容纳归档与解包结果，空间不足时在发起任何网络请求之前失败。
/// 3. 用 `ResumableModelDownloader` 下载归档（断点续传 + 重试），再校验归档自身的 sha256。
/// 4. `tar -xjf` 解包到 staging，把产物摊平到 staging 根目录，删掉归档。
/// 5. 交给 `ModelAtomicInstaller` 按逐文件 size + sha256 校验并原子换入；失败时保留既有安装。
///
/// 第 5 步是这条链路存在的理由：App 侧旧的 sherpa 下载路径只检查「文件非空」，
/// 没有 sha256，也没有磁盘预检。
public struct FireRedASRModelStoreDownloader: FireRedASRModelDownloading {
    private let storeRoot: URL
    private let manifestProvider: @Sendable () -> ModelManifest
    private let installedManifestProvider: @Sendable () -> ModelManifest
    private let downloader: ResumableModelDownloader
    private let availableDiskBytesProvider: @Sendable (URL) -> Int64?

    public init(
        storeRoot: URL,
        transport: any ModelDownloadTransport = ModelURLSessionDownloadTransport(),
        manifestProvider: @escaping @Sendable () -> ModelManifest = FireRedASRManifestCatalog.archiveManifest,
        installedManifestProvider: @escaping @Sendable () -> ModelManifest =
            FireRedASRManifestCatalog.installedManifest,
        availableDiskBytesProvider: @escaping @Sendable (URL) -> Int64? = {
            FireRedASRModelStoreDownloader.availableDiskBytes(at: $0)
        }
    ) {
        self.storeRoot = storeRoot
        self.manifestProvider = manifestProvider
        self.installedManifestProvider = installedManifestProvider
        self.downloader = ResumableModelDownloader(transport: transport)
        self.availableDiskBytesProvider = availableDiskBytesProvider
    }

    public func download(
        progress: @escaping FireRedASRModelDownloadProgressHandler
    ) async throws -> URL {
        let installedManifest = installedManifestProvider()
        if let existingRoot = existingValidInstallationRoot(for: installedManifest) {
            return existingRoot
        }

        let availableDiskBytes = availableDiskBytesProvider(storeRoot)
        try Self.precheckDisk(availableDiskBytes: availableDiskBytes)

        let archiveManifest = manifestProvider()
        let stagingRoot = try await downloader.download(
            manifest: archiveManifest,
            storeRoot: storeRoot,
            // 下载层只按归档大小检查；上面已经按「归档 + 解包结果」检查过一次更严格的。
            availableDiskBytes: availableDiskBytes
        ) { update in
            await progress(
                FireRedASRModelDownloadProgress(
                    fractionCompleted: update.fractionCompleted ?? 0,
                    bytesWritten: update.bytesWritten,
                    totalBytes: update.totalBytes
                )
            )
        }

        try await unpackArchive(in: stagingRoot, manifest: archiveManifest, progress: progress)

        return try ModelAtomicInstaller().install(
            manifest: installedManifest,
            stagingRoot: stagingRoot,
            storeRoot: storeRoot,
            runtimeVersion: FireRedASRManifestCatalog.runtimeVersion
        ).installedRoot
    }

    public func cancelDownload() async {
        await downloader.cancel()
    }

    // MARK: - 磁盘预检

    /// 空间不足时抛 `ModelDownloadError.insufficientDisk`，复用既有的空间不足文案与状态分类。
    public static func precheckDisk(availableDiskBytes: Int64?) throws {
        guard let availableDiskBytes else {
            return
        }
        let requiredBytes = FireRedASRManifestCatalog.requiredDiskBytes
        guard availableDiskBytes >= requiredBytes else {
            throw ModelDownloadError.insufficientDisk(
                requiredBytes: requiredBytes,
                availableBytes: availableDiskBytes
            )
        }
    }

    /// `storeRoot` 所在卷的可用空间。
    ///
    /// 首次安装时 `storeRoot` 可能还不存在，所以逐级向上取第一个存在的祖先目录再问容量；
    /// 传 `nil` 给 `ResumableModelDownloader` 等于跳过检查，2 GB 的资产会下载一半才失败。
    public static func availableDiskBytes(
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

    // MARK: - 解包

    private func unpackArchive(
        in stagingRoot: URL,
        manifest: ModelManifest,
        progress: @escaping FireRedASRModelDownloadProgressHandler
    ) async throws {
        let fileManager = FileManager.default
        guard let archiveComponent = manifest.components.first else {
            throw FireRedASRModelDownloadError.extractionFailed("empty archive manifest")
        }
        let archiveURL = stagingRoot.appendingPathComponent(archiveComponent.localPath)

        // 以**传入清单**声明的摘要为准，而不是在这里再写一份常量：
        // 清单是唯一事实来源，这样换资产只需要改清单，校验不会悄悄跟旧常量走。
        let expectedDigest = archiveComponent.sha256.rawValue
        let actualDigest = try Self.sha256Hex(at: archiveURL)
        guard actualDigest == expectedDigest else {
            throw FireRedASRModelDownloadError.archiveChecksumMismatch(
                expected: expectedDigest,
                actual: actualDigest
            )
        }

        try runTar(archive: archiveURL, into: stagingRoot)

        // tar 会保留顶层目录名，安装清单的 localPath 是裸文件名，所以把产物摊平上来。
        let extractedRoot = stagingRoot.appendingPathComponent(
            FireRedASRModel.directoryName,
            isDirectory: true
        )
        let missing = FireRedASRModel.requiredPaths.filter {
            !fileManager.isReadableFile(
                atPath: extractedRoot.appendingPathComponent($0).path
            )
        }
        guard missing.isEmpty else {
            throw FireRedASRModelDownloadError.unexpectedArchiveLayout(missingPaths: missing)
        }

        for relativePath in FireRedASRModel.requiredPaths {
            let source = extractedRoot.appendingPathComponent(relativePath)
            let destination = stagingRoot.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: source, to: destination)
        }
        try? fileManager.removeItem(at: extractedRoot)
        // 归档不能留在 staging 里：ModelAtomicInstaller 会把整个 staging 目录搬到安装位置。
        try? fileManager.removeItem(at: archiveURL)

        await progress(
            FireRedASRModelDownloadProgress(
                fractionCompleted: 1,
                bytesWritten: FireRedASRModel.installedBytes,
                totalBytes: FireRedASRModel.installedBytes
            )
        )
    }

    private func runTar(archive: URL, into directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", archive.path, "-C", directory.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)
                ?? "tar exited with \(process.terminationStatus)"
            throw FireRedASRModelDownloadError.extractionFailed(message)
        }
    }

    // MARK: - 复用与校验

    private func existingValidInstallationRoot(for manifest: ModelManifest) -> URL? {
        let fileManager = FileManager.default
        guard let first = manifest.components.first else { return nil }
        let candidate = storeRoot
            .appendingPathComponent(first.modelID.rawValue, isDirectory: true)
            .appendingPathComponent(first.version, isDirectory: true)

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
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

    static func sha256Hex(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
