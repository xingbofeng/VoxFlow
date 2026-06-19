import Foundation
import VoxFlowModelStore

public struct Qwen3ModelDownloadProgress: Equatable, Sendable {
    public let fileIndex: Int
    public let fileCount: Int
    public let fileName: String
    public let fileProgress: Double

    public init(
        fileIndex: Int,
        fileCount: Int,
        fileName: String,
        fileProgress: Double
    ) {
        self.fileIndex = fileIndex
        self.fileCount = fileCount
        self.fileName = fileName
        self.fileProgress = fileProgress
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
}

public final class Qwen3ModelStoreLiveInstaller: Qwen3ModelStoreInstalling, @unchecked Sendable {
    private let storeRoot: URL
    private let fileManager: FileManager
    private let transport: any ModelDownloadTransport

    public init(
        storeRoot: URL,
        fileManager: FileManager = .default,
        transport: any ModelDownloadTransport = Qwen3URLSessionModelDownloadTransport()
    ) {
        self.storeRoot = storeRoot
        self.fileManager = fileManager
        self.transport = transport
    }

    public func install(
        manifest: ModelManifest,
        progress: ModelDownloadObserver?
    ) async throws -> URL {
        let runtimeVersion = manifest.components.first?.runtimeVersion ?? "mlx-4bit"
        if let installedRoot = try existingValidInstallationRoot(
            manifest: manifest,
            storeRoot: storeRoot,
            runtimeVersion: runtimeVersion,
            fileManager: fileManager
        ) {
            return installedRoot
        }

        let downloader = ResumableModelDownloader(
            transport: transport,
            fileManager: fileManager
        )
        let stagingRoot = try await downloader.download(
            manifest: manifest,
            storeRoot: storeRoot,
            progress: progress
        )
        let installation = try ModelAtomicInstaller(fileManager: fileManager).install(
            manifest: manifest,
            stagingRoot: stagingRoot,
            storeRoot: storeRoot,
            runtimeVersion: runtimeVersion
        )
        return installation.installedRoot
    }
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
            fileProgress: progress.fractionCompleted ?? 0
        )
    }
}

public enum Qwen3ModelStoreDownloadError: LocalizedError, Equatable, Sendable {
    case downloadedFileUnavailable

    public var errorDescription: String? {
        switch self {
        case .downloadedFileUnavailable:
            return "模型文件下载完成但临时文件不可用。"
        }
    }
}

public final class Qwen3URLSessionModelDownloadTransport: NSObject, ModelDownloadTransport, URLSessionDownloadDelegate, @unchecked Sendable {
    private let fileManager: FileManager
    private var session: URLSession!
    private var activeContinuation: CheckedContinuation<Void, Error>?
    private var activeDestinationURL: URL?
    private var activeResumeOffset: Int64 = 0
    private var activeComponent: ModelComponentManifest?
    private var activeProgress: ModelDownloadProgressSink?
    private var activeMoveResult: Result<Void, Error>?

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        super.init()
        self.session = URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: nil
        )
    }

    public func download(
        component: ModelComponentManifest,
        to destinationURL: URL,
        resumeFrom offset: Int64,
        progress: @escaping ModelDownloadProgressSink
    ) async throws {
        activeDestinationURL = destinationURL
        activeResumeOffset = offset
        activeComponent = component
        activeProgress = progress
        activeMoveResult = nil

        var request = URLRequest(url: component.downloadURL)
        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                activeContinuation = continuation
                session.downloadTask(with: request).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }

        activeContinuation = nil
        activeDestinationURL = nil
        activeResumeOffset = 0
        activeComponent = nil
        activeProgress = nil
        activeMoveResult = nil
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let activeComponent, let activeProgress else { return }
        let totalBytes = activeComponent.expectedSizeBytes
        let written = min(totalBytes, activeResumeOffset + totalBytesWritten)
        Task {
            try? await activeProgress(
                ModelDownloadProgress(
                    bytesWritten: written,
                    totalBytes: totalBytes,
                    componentID: ModelComponentID(rawValue: activeComponent.localPath)
                )
            )
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let destinationURL = activeDestinationURL else {
            activeMoveResult = .failure(Qwen3ModelStoreDownloadError.downloadedFileUnavailable)
            return
        }

        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if activeResumeOffset > 0, fileManager.fileExists(atPath: destinationURL.path) {
                let readHandle = try FileHandle(forReadingFrom: location)
                defer { try? readHandle.close() }
                let writeHandle = try FileHandle(forWritingTo: destinationURL)
                defer { try? writeHandle.close() }
                try writeHandle.seekToEnd()
                try writeHandle.write(contentsOf: readHandle.readDataToEndOfFile())
            } else {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.moveItem(at: location, to: destinationURL)
            }
            activeMoveResult = .success(())
        } catch {
            activeMoveResult = .failure(error)
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            activeContinuation?.resume(throwing: error)
            return
        }

        guard let activeMoveResult else {
            activeContinuation?.resume(
                throwing: Qwen3ModelStoreDownloadError.downloadedFileUnavailable
            )
            return
        }

        switch activeMoveResult {
        case .success:
            activeContinuation?.resume()
        case .failure(let error):
            activeContinuation?.resume(throwing: error)
        }
    }
}
