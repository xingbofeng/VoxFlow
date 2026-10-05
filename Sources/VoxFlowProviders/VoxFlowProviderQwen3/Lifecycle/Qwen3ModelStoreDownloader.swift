import Foundation
import VoxFlowModelStore

public struct Qwen3ModelDownloadProgress: Equatable, Sendable {
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

public typealias Qwen3ModelDownloadProgressHandler = @Sendable (Qwen3ModelDownloadProgress) async -> Void

public protocol Qwen3ModelStoreInstalling: Sendable {
    func install(
        manifest: ModelManifest,
        progress: ModelDownloadObserver?
    ) async throws -> URL

    func cancelDownload() async
}

public extension Qwen3ModelStoreInstalling {
    func cancelDownload() async {}
}

public actor Qwen3ModelStoreInstaller: Qwen3ModelStoreInstalling {
    private let downloader: ResumableModelDownloader
    private let atomicInstaller: ModelAtomicInstaller
    private let storeRoot: URL
    private let runtimeVersion: String

    public init(
        downloader: ResumableModelDownloader,
        atomicInstaller: ModelAtomicInstaller = ModelAtomicInstaller(),
        storeRoot: URL,
        runtimeVersion: String
    ) {
        self.downloader = downloader
        self.atomicInstaller = atomicInstaller
        self.storeRoot = storeRoot
        self.runtimeVersion = runtimeVersion
    }

    public func install(
        manifest: ModelManifest,
        progress: ModelDownloadObserver?
    ) async throws -> URL {
        let stagingRoot = try await downloader.download(
            manifest: manifest,
            storeRoot: storeRoot,
            progress: progress
        )
        let installation = try atomicInstaller.install(
            manifest: manifest,
            stagingRoot: stagingRoot,
            storeRoot: storeRoot,
            runtimeVersion: runtimeVersion
        )
        return installation.installedRoot
    }

    public func cancelDownload() async {
        await downloader.cancel()
    }
}

public final class Qwen3ModelStoreLiveInstaller: Qwen3ModelStoreInstalling, @unchecked Sendable {
    private let storeRoot: URL
    private let fileManager: FileManager
    private let transport: any ModelDownloadTransport
    private let downloader: ResumableModelDownloader
    private let installCoordinator = ModelInstallCoordinator()

    public init(
        storeRoot: URL,
        fileManager: FileManager = .default,
        transport: any ModelDownloadTransport = Qwen3URLSessionModelDownloadTransport()
    ) {
        self.storeRoot = storeRoot
        self.fileManager = fileManager
        self.transport = transport
        self.downloader = ResumableModelDownloader(transport: transport)
    }

    public func install(
        manifest: ModelManifest,
        progress: ModelDownloadObserver?
    ) async throws -> URL {
        guard let firstComponent = manifest.components.first else {
            throw ModelInstallError.emptyManifest
        }
        let key = ModelInstallKey(
            modelID: firstComponent.modelID,
            version: firstComponent.version
        )
        let runtimeVersion = manifest.components.first?.runtimeVersion ?? "mlx-4bit"
        let context = Qwen3LiveInstallerContext(
            downloader: downloader,
            fileManager: fileManager,
            storeRoot: storeRoot
        )
        let installation = try await installCoordinator.install(for: key) {
            if let installedRoot = try existingValidInstallationRoot(
                manifest: manifest,
                storeRoot: context.storeRoot,
                runtimeVersion: runtimeVersion,
                fileManager: context.fileManager
            ) {
                return ModelInstallation(
                    modelID: firstComponent.modelID,
                    version: firstComponent.version,
                    installedRoot: installedRoot
                )
            }

            let stagingRoot = try await context.downloader.download(
                manifest: manifest,
                storeRoot: context.storeRoot,
                progress: progress
            )
            return try ModelAtomicInstaller(fileManager: context.fileManager).install(
                manifest: manifest,
                stagingRoot: stagingRoot,
                storeRoot: context.storeRoot,
                runtimeVersion: runtimeVersion
            )
        }
        return installation.installedRoot
    }

    public func cancelDownload() async {
        await downloader.cancel()
    }
}

private struct Qwen3LiveInstallerContext: @unchecked Sendable {
    let downloader: ResumableModelDownloader
    let fileManager: FileManager
    let storeRoot: URL
}

private func existingValidInstallationRoot(
    manifest: ModelManifest,
    storeRoot: URL,
    runtimeVersion: String,
    fileManager: FileManager
) throws -> URL? {
    guard let modelID = manifest.components.first?.modelID else {
        return nil
    }

    let installedRoot = storeRoot
        .appendingPathComponent(modelID.rawValue, isDirectory: true)
        .appendingPathComponent(runtimeVersion, isDirectory: true)

    var isDirectory = ObjCBool(false)
    guard fileManager.fileExists(atPath: installedRoot.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        return nil
    }

    let report = try ModelIntegrityValidator(fileManager: fileManager).validate(
        manifest: manifest,
        installedRoot: installedRoot,
        runtimeVersion: runtimeVersion
    )
    return report.isValid ? installedRoot : nil
}

public struct Qwen3ModelStoreBackedDownloader: Sendable {
    private let metadataProvider: @Sendable (Qwen3ModelManifest) throws -> Qwen3ModelStoreMetadata
    private let installer: any Qwen3ModelStoreInstalling

    public init(
        metadataProvider: @escaping @Sendable (Qwen3ModelManifest) throws -> Qwen3ModelStoreMetadata = Qwen3ManifestCatalog.metadata(for:),
        installer: any Qwen3ModelStoreInstalling
    ) {
        self.metadataProvider = metadataProvider
        self.installer = installer
    }

    public func download(
        manifest: Qwen3ModelManifest,
        progress: @escaping Qwen3ModelDownloadProgressHandler
    ) async throws -> URL {
        let modelStoreManifest = try manifest.modelStoreManifest(
            metadata: metadataProvider(manifest)
        )
        return try await installer.install(manifest: modelStoreManifest) { update in
            await progress(Self.qwenProgress(from: update, in: modelStoreManifest))
        }
    }

    public func cancelDownload() async {
        await installer.cancelDownload()
    }

    private static func qwenProgress(
        from progress: ModelDownloadProgress,
        in manifest: ModelManifest
    ) -> Qwen3ModelDownloadProgress {
        let componentPaths = manifest.components.map(\.localPath)
        let fileIndex = componentPaths.firstIndex(of: progress.componentID.rawValue) ?? 0
        return Qwen3ModelDownloadProgress(
            fileIndex: fileIndex,
            fileCount: max(componentPaths.count, 1),
            fileName: progress.componentID.rawValue,
            fileProgress: progress.fractionCompleted ?? 0,
            bytesWritten: progress.bytesWritten,
            totalBytes: progress.totalBytes
        )
    }
}

/// 具体实现位于 `VoxFlowModelStore.ModelURLSessionDownloadTransport`（与 Provider 无关，供所有 ModelStore 驱动方复用）。
public typealias Qwen3URLSessionModelDownloadTransport = ModelURLSessionDownloadTransport
public typealias Qwen3ModelStoreDownloadError = ModelStoreDownloadError
