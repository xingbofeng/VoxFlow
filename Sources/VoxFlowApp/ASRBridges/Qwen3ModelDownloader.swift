import Foundation
import VoxFlowModelStore
import VoxFlowProviderQwen3

extension Qwen3ModelVariant {
    init(size: ASRManager.ModelSize) {
        switch size {
        case .size0_6B:
            self = .qwen06SpeechSwift4Bit
        case .size1_7B:
            self = .qwen17SpeechSwift8Bit
        }
    }
}

extension Qwen3ModelManifest {
    static func manifest(for size: ASRManager.ModelSize) -> Qwen3ModelManifest {
        Qwen3ManifestCatalog.manifest(for: Qwen3ModelVariant(size: size))
    }
}

protocol Qwen3ModelDownloading: Sendable {
    func download(
        manifest: Qwen3ModelManifest,
        progress: @escaping Qwen3ModelDownloader.ProgressHandler
    ) async throws -> URL

    func cancelDownload() async

    func missingRequiredLocalPaths(
        size: ASRManager.ModelSize,
        at directory: URL,
        fileManager: FileManager
    ) -> [String]
}

extension Qwen3ModelDownloading {
    func cancelDownload() async {}

    func download(
        size: ASRManager.ModelSize,
        progress: @escaping Qwen3ModelDownloader.ProgressHandler
    ) async throws -> URL {
        AppLogger.general.info("Prepare Qwen3 download: size=\(size.rawValue)")
        guard ASRManager.isQwen3RuntimeSupported(size: size) else {
            AppLogger.general.warning(
                "Qwen3 runtime unsupported: size=\(size.rawValue), reason=\(ASRManager.qwen3RuntimeUnsupportedMessage(for: size))"
            )
            throw Qwen3ModelDownloadError.runtimeUnsupported(
                ASRManager.qwen3RuntimeUnsupportedMessage(for: size)
            )
        }
        AppLogger.general.info("Start Qwen3 download for size=\(size.rawValue)")
        return try await download(manifest: Qwen3ModelManifest.manifest(for: size), progress: progress)
    }

    func missingRequiredLocalPaths(
        size: ASRManager.ModelSize,
        at directory: URL,
        fileManager: FileManager = .default
    ) -> [String] {
        Qwen3ModelManifest.manifest(for: size)
            .missingRequiredLocalPaths(at: directory, fileManager: fileManager)
    }
}

final class Qwen3LiveModelStoreInstaller: Qwen3ModelStoreInstalling, @unchecked Sendable {
    private let fileManager: FileManager
    private let transport: any ModelDownloadTransport
    private let currentInstallerLock = NSLock()
    private var currentInstaller: Qwen3ModelStoreLiveInstaller?

    init(
        fileManager: FileManager = .default,
        transport: any ModelDownloadTransport = Qwen3URLSessionModelDownloadTransport()
    ) {
        self.fileManager = fileManager
        self.transport = transport
    }

    func install(
        manifest: ModelManifest,
        progress: ModelDownloadObserver?
    ) async throws -> URL {
        AppLogger.general.info("Qwen3 model install begin: manifest=\(manifest)")
        let paths: ApplicationSupportPaths
        do {
            paths = try ApplicationSupportPaths.live(fileManager: fileManager)
        } catch ApplicationSupportPathsError.applicationSupportDirectoryUnavailable {
            AppLogger.general.error("ApplicationSupport unavailable for Qwen3 install")
            throw Qwen3ModelDownloadError.applicationSupportUnavailable
        }

        try paths.ensureDirectories(fileManager: fileManager)
        let installer = Qwen3ModelStoreLiveInstaller(
            storeRoot: paths.modelsDirectory,
            fileManager: fileManager,
            transport: transport
        )
        setCurrentInstaller(installer)
        defer { clearCurrentInstaller(installer) }
        let result = try await installer.install(
            manifest: manifest,
            progress: progress
        )
        AppLogger.general.info("Qwen3 model install completed: manifest=\(manifest)")
        return result
    }

    func cancelDownload() async {
        let installer = currentInstallerSnapshot()
        await installer?.cancelDownload()
    }

    private func setCurrentInstaller(_ installer: Qwen3ModelStoreLiveInstaller) {
        currentInstallerLock.lock()
        currentInstaller = installer
        currentInstallerLock.unlock()
    }

    private func clearCurrentInstaller(_ installer: Qwen3ModelStoreLiveInstaller) {
        currentInstallerLock.lock()
        if currentInstaller === installer {
            currentInstaller = nil
        }
        currentInstallerLock.unlock()
    }

    private func currentInstallerSnapshot() -> Qwen3ModelStoreLiveInstaller? {
        currentInstallerLock.lock()
        let installer = currentInstaller
        currentInstallerLock.unlock()
        return installer
    }
}

enum Qwen3ModelDownloader {
    typealias ProgressHandler = @MainActor (Qwen3ModelDownloadProgress) -> Void

    static func live() -> any Qwen3ModelDownloading {
        Qwen3ModelStoreBackedDownloader(
            metadataProvider: Qwen3ModelStoreMetadata.metadata(for:),
            installer: Qwen3LiveModelStoreInstaller()
        )
    }
}

extension Qwen3ModelStoreBackedDownloader: Qwen3ModelDownloading {
    func download(
        manifest: Qwen3ModelManifest,
        progress: @escaping Qwen3ModelDownloader.ProgressHandler
    ) async throws -> URL {
        let progressHandler: Qwen3ModelDownloadProgressHandler = { update in
            await progress(update)
        }
        return try await download(manifest: manifest, progress: progressHandler)
    }

    func missingRequiredLocalPaths(
        size: ASRManager.ModelSize,
        at directory: URL,
        fileManager: FileManager
    ) -> [String] {
        []
    }
}

enum Qwen3ModelDownloadError: LocalizedError {
    case applicationSupportUnavailable
    case runtimeUnsupported(String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "无法定位 Application Support 目录。"
        case .runtimeUnsupported(let message):
            return message
        }
    }
}
