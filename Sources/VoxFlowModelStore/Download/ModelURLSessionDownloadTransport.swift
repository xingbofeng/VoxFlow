import Foundation

/// `ModelDownloadTransport` 的默认实现：基于 `URLSession` 的断点续传下载。
///
/// 该实现与具体 Provider 无关，只依赖 `ModelComponentManifest` 描述的组件，
/// 因此放在 ModelStore 共享层，供所有 ModelStore 驱动的 Provider 复用。
public enum ModelStoreDownloadError: LocalizedError, Equatable, Sendable {
    case downloadedFileUnavailable
    case invalidResumeResponse(statusCode: Int)
    case invalidContentRange(String?)

    public var errorDescription: String? {
        switch self {
        case .downloadedFileUnavailable:
            return "模型文件下载完成但临时文件不可用。"
        case .invalidResumeResponse(let statusCode):
            return "模型断点续传响应无效（HTTP \(statusCode)）。"
        case .invalidContentRange:
            return "模型断点续传 Content-Range 与本地偏移不匹配。"
        }
    }
}

public final class ModelURLSessionDownloadTransport: NSObject, ModelDownloadTransport, URLSessionDownloadDelegate, @unchecked Sendable {
    private let fileManager: FileManager
    private var session: URLSession!
    private var activeContinuation: CheckedContinuation<Void, Error>?
    private var activeDestinationURL: URL?
    private var activeResumeOffset: Int64 = 0
    private var activeComponent: ModelComponentManifest?
    private var activeProgress: ModelDownloadProgressSink?
    private var activeMoveResult: Result<Void, Error>?
    private var activeDownloadTask: URLSessionDownloadTask?

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
        defer { clearActiveDownloadState() }

        var request = URLRequest(url: component.downloadURL)
        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                activeContinuation = continuation
                let task = session.downloadTask(with: request)
                activeDownloadTask = task
                task.resume()
            }
        } onCancel: {
            activeDownloadTask?.cancel()
        }
    }

    private func clearActiveDownloadState() {
        activeContinuation = nil
        activeDestinationURL = nil
        activeResumeOffset = 0
        activeComponent = nil
        activeProgress = nil
        activeMoveResult = nil
        activeDownloadTask = nil
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
            activeMoveResult = .failure(ModelStoreDownloadError.downloadedFileUnavailable)
            return
        }

        do {
            try Self.moveDownloadedFile(
                from: location,
                to: destinationURL,
                resumeOffset: activeResumeOffset,
                response: downloadTask.response,
                fileManager: fileManager
            )
            activeMoveResult = .success(())
        } catch {
            activeMoveResult = .failure(error)
        }
    }

    static func moveDownloadedFile(
        from location: URL,
        to destinationURL: URL,
        resumeOffset: Int64,
        response: URLResponse?,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if resumeOffset > 0, fileManager.fileExists(atPath: destinationURL.path) {
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ModelStoreDownloadError.downloadedFileUnavailable
            }
            switch httpResponse.statusCode {
            case 206:
                let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range")
                guard Self.contentRangeStart(contentRange) == resumeOffset else {
                    throw ModelStoreDownloadError.invalidContentRange(contentRange)
                }
                try appendDownloadedFile(from: location, to: destinationURL)
            case 200:
                try replaceDownloadedFile(from: location, to: destinationURL, fileManager: fileManager)
            default:
                throw ModelStoreDownloadError.invalidResumeResponse(statusCode: httpResponse.statusCode)
            }
        } else {
            try replaceDownloadedFile(from: location, to: destinationURL, fileManager: fileManager)
        }
    }

    private static func appendDownloadedFile(from location: URL, to destinationURL: URL) throws {
        let readHandle = try FileHandle(forReadingFrom: location)
        defer { try? readHandle.close() }
        let writeHandle = try FileHandle(forWritingTo: destinationURL)
        defer { try? writeHandle.close() }
        try writeHandle.seekToEnd()
        while true {
            let chunk = try readHandle.read(upToCount: 64 * 1024) ?? Data()
            guard !chunk.isEmpty else { break }
            try writeHandle.write(contentsOf: chunk)
        }
    }

    private static func replaceDownloadedFile(
        from location: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: location, to: destinationURL)
    }

    private static func contentRangeStart(_ value: String?) -> Int64? {
        guard let value else { return nil }
        let prefix = "bytes "
        guard value.hasPrefix(prefix) else { return nil }
        let range = value.dropFirst(prefix.count)
        guard let dashIndex = range.firstIndex(of: "-") else { return nil }
        return Int64(range[..<dashIndex])
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
                throwing: ModelStoreDownloadError.downloadedFileUnavailable
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
