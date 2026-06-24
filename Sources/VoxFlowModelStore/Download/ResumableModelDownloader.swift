import Foundation

public typealias ModelDownloadProgressSink = @Sendable (ModelDownloadProgress) async throws -> Void
public typealias ModelDownloadObserver = @Sendable (ModelDownloadProgress) async -> Void

public enum ModelDownloadError: LocalizedError, Equatable, Sendable {
    case nonHTTPSDownloadURL(String)
    case insufficientDisk(requiredBytes: Int64, availableBytes: Int64)
    case paused
    case cancelled
    case networkFailure(String)

    public var errorDescription: String? {
        switch self {
        case .nonHTTPSDownloadURL:
            return "模型下载链接不安全，已停止下载。请更新模型清单后重试。"
        case .insufficientDisk(let requiredBytes, let availableBytes):
            return "磁盘空间不够，模型需要约 \(Self.formatBytes(requiredBytes))，当前可用约 \(Self.formatBytes(availableBytes))。请清理空间后重试。"
        case .paused:
            return "下载已暂停，可以稍后继续。"
        case .cancelled:
            return "下载已取消。"
        case .networkFailure(let reason):
            let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedReason.isEmpty else {
                return "模型下载中断，可能是网络或代理连接失败。请检查网络后重试。"
            }
            return "模型下载中断，可能是网络或代理连接失败。请检查网络后重试。详情：\(trimmedReason)"
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

public protocol ModelDownloadTransport: Sendable {
    func download(
        component: ModelComponentManifest,
        to destinationURL: URL,
        resumeFrom offset: Int64,
        progress: @escaping ModelDownloadProgressSink
    ) async throws
}

public struct ModelDownloadResumeState: Codable, Equatable, Sendable {
    public var componentOffsets: [String: Int64]

    public init(componentOffsets: [String: Int64] = [:]) {
        self.componentOffsets = componentOffsets
    }
}

public actor ResumableModelDownloader {
    private let transport: any ModelDownloadTransport
    private let fileManager: FileManager
    private let maxNetworkRetries: Int
    private var inFlight: [ModelInstallKey: Task<URL, Error>] = [:]
    private var pauseRequested = false
    private var cancelRequested = false

    public init(
        transport: any ModelDownloadTransport,
        fileManager: FileManager = .default,
        maxNetworkRetries: Int = 2
    ) {
        self.transport = transport
        self.fileManager = fileManager
        self.maxNetworkRetries = maxNetworkRetries
    }

    public func pause() {
        pauseRequested = true
    }

    public func cancel() {
        cancelRequested = true
        inFlight.values.forEach { $0.cancel() }
    }

    public func download(
        manifest: ModelManifest,
        storeRoot: URL,
        availableDiskBytes: Int64? = nil,
        progress: ModelDownloadObserver? = nil
    ) async throws -> URL {
        let key = try Self.installKey(for: manifest)
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task {
            try await self.performDownload(
                manifest: manifest,
                key: key,
                storeRoot: storeRoot,
                availableDiskBytes: availableDiskBytes,
                progress: progress
            )
        }
        inFlight[key] = task
        do {
            let url = try await task.value
            inFlight[key] = nil
            return url
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    public static func stagingRoot(
        for key: ModelInstallKey,
        storeRoot: URL
    ) -> URL {
        storeRoot
            .appendingPathComponent("staging", isDirectory: true)
            .appendingPathComponent("\(key.modelID.rawValue)-\(key.version).partial", isDirectory: true)
    }

    private func performDownload(
        manifest: ModelManifest,
        key: ModelInstallKey,
        storeRoot: URL,
        availableDiskBytes: Int64?,
        progress: ModelDownloadObserver?
    ) async throws -> URL {
        pauseRequested = false
        cancelRequested = false
        try validateHTTPSURLs(in: manifest)
        try precheckDisk(for: manifest, availableDiskBytes: availableDiskBytes)

        let stagingRoot = Self.stagingRoot(for: key, storeRoot: storeRoot)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let stateURL = stagingRoot.appendingPathComponent(".download-state.json")

        for component in manifest.components {
            let destinationURL = stagingRoot.appendingPathComponent(component.localPath)
            try await downloadComponent(
                component,
                to: destinationURL,
                stateURL: stateURL,
                progress: progress
            )
        }

        if fileManager.fileExists(atPath: stateURL.path) {
            try fileManager.removeItem(at: stateURL)
        }
        return stagingRoot
    }

    private func downloadComponent(
        _ component: ModelComponentManifest,
        to destinationURL: URL,
        stateURL: URL,
        progress: ModelDownloadObserver?
    ) async throws {
        var failures = 0
        while true {
            do {
                let resumeOffset = try resumeOffset(for: component, stateURL: stateURL, destinationURL: destinationURL)
                try await transport.download(
                    component: component,
                    to: destinationURL,
                    resumeFrom: resumeOffset
                ) { update in
                    try await self.handleProgress(
                        update,
                        stateURL: stateURL,
                        progress: progress
                    )
                }
                try recordOffset(component.localPath, offset: component.expectedSizeBytes, stateURL: stateURL)
                return
            } catch ModelDownloadError.paused {
                throw ModelDownloadError.paused
            } catch ModelDownloadError.cancelled {
                throw ModelDownloadError.cancelled
            } catch {
                if failures < maxNetworkRetries {
                    failures += 1
                    continue
                }
                if let downloadError = error as? ModelDownloadError {
                    throw downloadError
                }
                throw ModelDownloadError.networkFailure(String(describing: error))
            }
        }
    }

    private func handleProgress(
        _ update: ModelDownloadProgress,
        stateURL: URL,
        progress: ModelDownloadObserver?
    ) async throws {
        try recordOffset(update.componentID.rawValue, offset: update.bytesWritten, stateURL: stateURL)
        if let progress {
            await progress(update)
        }
        if cancelRequested {
            throw ModelDownloadError.cancelled
        }
        if pauseRequested {
            throw ModelDownloadError.paused
        }
    }

    private func validateHTTPSURLs(in manifest: ModelManifest) throws {
        for component in manifest.components where component.downloadURL.scheme?.lowercased() != "https" {
            throw ModelDownloadError.nonHTTPSDownloadURL(component.downloadURL.absoluteString)
        }
    }

    private func precheckDisk(
        for manifest: ModelManifest,
        availableDiskBytes: Int64?
    ) throws {
        guard let availableDiskBytes else {
            return
        }
        let requiredBytes = manifest.components.reduce(Int64(0)) { $0 + $1.expectedSizeBytes }
        guard availableDiskBytes >= requiredBytes else {
            throw ModelDownloadError.insufficientDisk(
                requiredBytes: requiredBytes,
                availableBytes: availableDiskBytes
            )
        }
    }

    private func resumeOffset(
        for component: ModelComponentManifest,
        stateURL: URL,
        destinationURL: URL
    ) throws -> Int64 {
        let state = try loadState(from: stateURL)
        if let offset = state.componentOffsets[component.localPath] {
            guard fileManager.fileExists(atPath: destinationURL.path) else {
                return 0
            }
            let fileSize = try fileSize(at: destinationURL)
            let resumeOffset = min(max(offset, 0), fileSize)
            if fileSize != resumeOffset {
                try truncateFile(at: destinationURL, to: resumeOffset)
            }
            return resumeOffset
        }
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            return 0
        }
        return try fileSize(at: destinationURL)
    }

    private func recordOffset(
        _ localPath: String,
        offset: Int64,
        stateURL: URL
    ) throws {
        var state = try loadState(from: stateURL)
        state.componentOffsets[localPath] = offset
        try saveState(state, to: stateURL)
    }

    private func loadState(from stateURL: URL) throws -> ModelDownloadResumeState {
        guard fileManager.fileExists(atPath: stateURL.path) else {
            return ModelDownloadResumeState()
        }
        let data = try Data(contentsOf: stateURL)
        return try JSONDecoder().decode(ModelDownloadResumeState.self, from: data)
    }

    private func saveState(
        _ state: ModelDownloadResumeState,
        to stateURL: URL
    ) throws {
        try fileManager.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(state)
        try data.write(to: stateURL, options: [.atomic])
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let size = attributes[.size] as? NSNumber
        return size?.int64Value ?? 0
    }

    private func truncateFile(at url: URL, to size: Int64) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(size))
    }

    private static func installKey(for manifest: ModelManifest) throws -> ModelInstallKey {
        guard let firstComponent = manifest.components.first else {
            throw ModelInstallError.emptyManifest
        }
        return ModelInstallKey(
            modelID: firstComponent.modelID,
            version: firstComponent.version
        )
    }
}
