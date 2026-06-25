import Foundation

struct SherpaASRModelDownloadProgress: Sendable, Equatable {
    let fractionCompleted: Double?
    let status: String
    let bytesWritten: Int64?
    let totalBytes: Int64?

    init(
        fractionCompleted: Double?,
        status: String,
        bytesWritten: Int64? = nil,
        totalBytes: Int64? = nil
    ) {
        self.fractionCompleted = fractionCompleted
        self.status = status
        self.bytesWritten = bytesWritten
        self.totalBytes = totalBytes
    }
}

protocol SherpaASRModelDownloading: Sendable {
    func download(
        variant: SherpaASRModelVariant,
        progress: @escaping @MainActor @Sendable (SherpaASRModelDownloadProgress) -> Void
    ) async throws -> URL

    func cancelDownload() async
}

extension SherpaASRModelDownloading {
    func cancelDownload() async {}
}

enum SherpaASRModelDownloaderError: LocalizedError {
    case invalidArchive
    case extractionFailed(String)
    case incompleteModel([String])

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "模型下载文件无效。"
        case .extractionFailed(let message):
            return "模型解压失败：\(message)"
        case .incompleteModel(let paths):
            return "模型文件不完整：\(paths.joined(separator: "、"))"
        }
    }
}

struct SherpaASRModelDownloader: SherpaASRModelDownloading, @unchecked Sendable {
    private let fileManager: FileManager
    private let session: URLSession
    private let cancellationState: SherpaASRDownloadCancellationState

    init(
        fileManager: FileManager = .default,
        session: URLSession = .shared
    ) {
        self.fileManager = fileManager
        self.session = session
        self.cancellationState = SherpaASRDownloadCancellationState()
    }

    func download(
        variant: SherpaASRModelVariant,
        progress: @escaping @MainActor @Sendable (SherpaASRModelDownloadProgress) -> Void
    ) async throws -> URL {
        let cancellationToken = cancellationState.beginDownload()
        defer { cancellationState.finishDownload(cancellationToken) }
        AppLogger.general.info("Start Sherpa ASR model download: \(variant.directoryName)")
        let expectedBytes = variant.expectedArchiveBytes
        await progress(.init(
            fractionCompleted: 0,
            status: "下载 \(variant.archiveName)",
            bytesWritten: 0,
            totalBytes: expectedBytes
        ))
        let (temporaryArchive, downloadedBytes) = try await downloadArchive(
            variant: variant,
            expectedBytes: expectedBytes,
            status: "下载 \(variant.archiveName)",
            cancellationToken: cancellationToken,
            progress: progress
        )
        defer { try? fileManager.removeItem(at: temporaryArchive) }

        let destination = variant.defaultDirectoryURL
        let modelsRoot = destination.deletingLastPathComponent()
        let stagingRoot = modelsRoot.appendingPathComponent(
            ".\(variant.directoryName)-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: stagingRoot) }
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        try cancellationState.checkCancellation(cancellationToken)

        let completedBytes = expectedBytes > 0 ? expectedBytes : downloadedBytes
        await progress(.init(
            fractionCompleted: 1,
            status: "解压模型文件",
            bytesWritten: completedBytes,
            totalBytes: completedBytes > 0 ? completedBytes : nil
        ))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", temporaryArchive.path, "-C", stagingRoot.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "tar exited with \(process.terminationStatus)"
            AppLogger.general.error("Sherpa model extraction failed: \(message)")
            throw SherpaASRModelDownloaderError.extractionFailed(message)
        }
        try cancellationState.checkCancellation(cancellationToken)

        let extracted = stagingRoot.appendingPathComponent(variant.directoryName, isDirectory: true)
        let missing = variant.requiredPaths.filter {
            let path = extracted.appendingPathComponent($0).path
            guard fileManager.isReadableFile(atPath: path),
                  let attributes = try? fileManager.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? NSNumber else {
                return true
            }
            return size.int64Value <= 0
        }
        guard missing.isEmpty else {
            AppLogger.general.error("Sherpa model extraction incomplete: missingFiles=\(missing.joined(separator: ","))")
            throw SherpaASRModelDownloaderError.incompleteModel(missing)
        }

        try fileManager.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            AppLogger.general.warning("Sherpa model destination exists, replacing: \(destination.path)")
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: extracted, to: destination)
        AppLogger.general.info("Sherpa model download and extract completed: \(destination.path)")
        await progress(.init(
            fractionCompleted: 1,
            status: "模型已就绪",
            bytesWritten: completedBytes,
            totalBytes: completedBytes > 0 ? completedBytes : nil
        ))
        return destination
    }

    func cancelDownload() async {
        cancellationState.cancel()
    }

    private func downloadArchive(
        variant: SherpaASRModelVariant,
        expectedBytes: Int64,
        status: String,
        cancellationToken: UUID,
        progress: @escaping @MainActor @Sendable (SherpaASRModelDownloadProgress) -> Void
    ) async throws -> (URL, Int64) {
        let downloadDirectory = variant.partialArchiveURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        let partialArchive = variant.partialArchiveURL
        var existingBytes = archiveSize(at: partialArchive)
        if expectedBytes > 0, existingBytes >= expectedBytes {
            await reportDownloadProgress(
                written: existingBytes,
                expectedBytes: expectedBytes,
                status: status,
                progress: progress
            )
            return (partialArchive, existingBytes)
        }

        var request = URLRequest(url: variant.archiveURL)
        if existingBytes > 0 {
            request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.general.error("Sherpa model download failed: invalid response type")
            throw SherpaASRModelDownloaderError.invalidArchive
        }
        AppLogger.general.debug("Sherpa download response code=\(httpResponse.statusCode)")
        guard (200..<300).contains(httpResponse.statusCode) else {
            AppLogger.general.error("Sherpa model download failed: HTTP \(httpResponse.statusCode)")
            throw SherpaASRModelDownloaderError.invalidArchive
        }
        if existingBytes > 0, httpResponse.statusCode != 206 {
            AppLogger.general.info("Sherpa model server ignored range request; restarting archive download")
            try? fileManager.removeItem(at: partialArchive)
            existingBytes = 0
        }
        if !fileManager.fileExists(atPath: partialArchive.path) {
            guard fileManager.createFile(atPath: partialArchive.path, contents: nil) else {
                throw SherpaASRModelDownloaderError.invalidArchive
            }
        }
        let handle = try FileHandle(forWritingTo: partialArchive)
        try handle.seekToEnd()
        var written = existingBytes
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        do {
            try cancellationState.checkCancellation(cancellationToken)
            for try await byte in bytes {
                try cancellationState.checkCancellation(cancellationToken)
                buffer.append(byte)
                if buffer.count >= 64 * 1024 {
                    try handle.write(contentsOf: buffer)
                    written += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    await reportDownloadProgress(
                        written: written,
                        expectedBytes: expectedBytes,
                        status: status,
                        progress: progress
                    )
                }
            }
            try cancellationState.checkCancellation(cancellationToken)
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
            }
            try handle.close()
            await reportDownloadProgress(
                written: written,
                expectedBytes: expectedBytes,
                status: status,
                progress: progress
            )
            guard expectedBytes <= 0 || written >= expectedBytes else {
                AppLogger.general.error(
                    "Sherpa model download incomplete: written=\(written) expected=\(expectedBytes)"
                )
                throw SherpaASRModelDownloaderError.invalidArchive
            }
            return (partialArchive, written)
        } catch {
            try? handle.close()
            throw error
        }
    }

    private func archiveSize(at url: URL) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    @MainActor
    private func reportDownloadProgress(
        written: Int64,
        expectedBytes: Int64,
        status: String,
        progress: @escaping @MainActor @Sendable (SherpaASRModelDownloadProgress) -> Void
    ) {
        progress(.init(
            fractionCompleted: expectedBytes > 0 ? min(1, Double(written) / Double(expectedBytes)) : nil,
            status: status,
            bytesWritten: written,
            totalBytes: expectedBytes > 0 ? expectedBytes : nil
        ))
    }
}

private final class SherpaASRDownloadCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var currentToken: UUID?
    private var cancelledTokens: Set<UUID> = []

    func beginDownload() -> UUID {
        let token = UUID()
        lock.lock()
        currentToken = token
        lock.unlock()
        return token
    }

    func cancel() {
        lock.lock()
        if let currentToken {
            cancelledTokens.insert(currentToken)
        }
        lock.unlock()
    }

    func finishDownload(_ token: UUID) {
        lock.lock()
        if currentToken == token {
            currentToken = nil
        }
        cancelledTokens.remove(token)
        lock.unlock()
    }

    func checkCancellation(_ token: UUID) throws {
        lock.lock()
        let isCancelled = cancelledTokens.contains(token)
        lock.unlock()
        if isCancelled || Task.isCancelled {
            throw CancellationError()
        }
    }
}

private extension SherpaASRModelVariant {
    var expectedArchiveBytes: Int64 {
        switch self {
        case .funASRInt8:
            return 841_730_611
        case .funASRFP32:
            return 1_317_656_544
        }
    }
}
