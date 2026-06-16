import Foundation

struct Qwen3ModelManifest: Equatable {
    struct File: Equatable {
        let repository: String?
        let remotePath: String
        let localPath: String

        init(repository: String? = nil, remotePath: String, localPath: String) {
            self.repository = repository
            self.remotePath = remotePath
            self.localPath = localPath
        }
    }

    let repository: String
    let localDirectoryName: String
    let files: [File]
    let requiredLocalPaths: [String]

    var fileCount: Int { files.count }

    static func manifest(for size: ASRManager.ModelSize) -> Qwen3ModelManifest {
        switch size {
        case .size0_6B:
            return Qwen3ModelManifest(
                repository: "FluidInference/qwen3-asr-0.6b-coreml",
                localDirectoryName: "qwen3-asr-0.6b-coreml-int8",
                files: [
                    File(remotePath: "int8/metadata.json", localPath: "metadata.json"),
                    File(remotePath: "int8/vocab.json", localPath: "vocab.json"),
                    File(remotePath: "int8/qwen3_asr_embeddings.bin", localPath: "qwen3_asr_embeddings.bin"),
                    File(remotePath: "int8/qwen3_asr_audio_encoder_v2.mlmodelc/analytics/coremldata.bin", localPath: "qwen3_asr_audio_encoder_v2.mlmodelc/analytics/coremldata.bin"),
                    File(remotePath: "int8/qwen3_asr_audio_encoder_v2.mlmodelc/coremldata.bin", localPath: "qwen3_asr_audio_encoder_v2.mlmodelc/coremldata.bin"),
                    File(remotePath: "int8/qwen3_asr_audio_encoder_v2.mlmodelc/metadata.json", localPath: "qwen3_asr_audio_encoder_v2.mlmodelc/metadata.json"),
                    File(remotePath: "int8/qwen3_asr_audio_encoder_v2.mlmodelc/model.mil", localPath: "qwen3_asr_audio_encoder_v2.mlmodelc/model.mil"),
                    File(remotePath: "int8/qwen3_asr_audio_encoder_v2.mlmodelc/weights/weight.bin", localPath: "qwen3_asr_audio_encoder_v2.mlmodelc/weights/weight.bin"),
                    File(remotePath: "int8/qwen3_asr_decoder_stateful.mlmodelc/analytics/coremldata.bin", localPath: "qwen3_asr_decoder_stateful.mlmodelc/analytics/coremldata.bin"),
                    File(remotePath: "int8/qwen3_asr_decoder_stateful.mlmodelc/coremldata.bin", localPath: "qwen3_asr_decoder_stateful.mlmodelc/coremldata.bin"),
                    File(remotePath: "int8/qwen3_asr_decoder_stateful.mlmodelc/metadata.json", localPath: "qwen3_asr_decoder_stateful.mlmodelc/metadata.json"),
                    File(remotePath: "int8/qwen3_asr_decoder_stateful.mlmodelc/model.mil", localPath: "qwen3_asr_decoder_stateful.mlmodelc/model.mil"),
                    File(remotePath: "int8/qwen3_asr_decoder_stateful.mlmodelc/weights/weight.bin", localPath: "qwen3_asr_decoder_stateful.mlmodelc/weights/weight.bin"),
                ],
                requiredLocalPaths: Self.requiredLoadablePaths
            )
        case .size1_7B:
            return Qwen3ModelManifest(
                repository: "Qwen/Qwen3-ASR-1.7B",
                localDirectoryName: "qwen3-asr-1.7b",
                files: [],
                requiredLocalPaths: [
                    "qwen3_asr_1_7b_runtime_not_supported"
                ]
            )
        }
    }

    static let requiredLoadablePaths = [
        "qwen3_asr_audio_encoder_v2.mlmodelc/coremldata.bin",
        "qwen3_asr_decoder_stateful.mlmodelc/coremldata.bin",
        "qwen3_asr_embeddings.bin",
        "vocab.json",
    ]

    static let supportedLoadablePathSets = [
        requiredLoadablePaths,
        [
            "qwen3_asr_audio_encoder_v2.mlpackage/Manifest.json",
            "qwen3_asr_decoder_stateful.mlpackage/Manifest.json",
            "qwen3_asr_embeddings.bin",
            "vocab.json",
        ],
    ]

    func remoteURL(for file: File) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.path = "/\(file.repository ?? repository)/resolve/main/\(file.remotePath)"
        return components.url!
    }

    func modelsExist(at directory: URL, fileManager: FileManager = .default) -> Bool {
        missingRequiredLocalPaths(at: directory, fileManager: fileManager).isEmpty
            && Self.hasValidEmbeddingFile(at: directory, fileManager: fileManager)
    }

    func missingRequiredLocalPaths(at directory: URL, fileManager: FileManager = .default) -> [String] {
        requiredLocalPaths.filter { path in
            !fileManager.fileExists(atPath: directory.appendingPathComponent(path).path)
        }
    }

    static func missingRequiredLocalPaths(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> [String] {
        supportedLoadablePathSets
            .map { paths in
                paths.filter { path in
                    !fileManager.fileExists(atPath: directory.appendingPathComponent(path).path)
                }
            }
            .min { lhs, rhs in lhs.count < rhs.count } ?? []
    }

    static func supportedModelExists(at directory: URL, fileManager: FileManager = .default) -> Bool {
        supportedLoadablePathSets.contains { paths in
            paths.allSatisfy { path in
                fileManager.fileExists(atPath: directory.appendingPathComponent(path).path)
            }
        } && hasValidEmbeddingFile(at: directory, fileManager: fileManager)
    }

    private static func hasValidEmbeddingFile(
        at directory: URL,
        fileManager: FileManager
    ) -> Bool {
        let url = directory.appendingPathComponent("qwen3_asr_embeddings.bin")
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let fileSize = (attributes[.size] as? NSNumber)?.uint64Value,
              fileSize == 8 + UInt64(151_936) * 1_024 * 2,
              let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 8), header.count == 8 else {
            return false
        }
        let vocab = header.withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self))
        }
        let hidden = header.withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
        }
        return vocab == 151_936 && hidden == 1_024
    }

}

struct Qwen3ModelDownloadProgress: Equatable {
    let fileIndex: Int
    let fileCount: Int
    let fileName: String
    let fileProgress: Double

    var overallProgress: Double {
        guard fileCount > 0 else { return 0 }
        return (Double(fileIndex) + fileProgress) / Double(fileCount)
    }
}

final class Qwen3ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    typealias ProgressHandler = @MainActor (Qwen3ModelDownloadProgress) -> Void

    private let fileManager: FileManager
    private var session: URLSession!
    private var activeContinuation: CheckedContinuation<Void, Error>?
    private var activeDestinationURL: URL?
    private var activeProgress: Qwen3ModelDownloadProgress?
    private var activeProgressHandler: ProgressHandler?
    private var activeMoveResult: Result<Void, Error>?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        super.init()
        self.session = URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: nil
        )
    }

    func download(
        manifest: Qwen3ModelManifest,
        progress: @escaping ProgressHandler
    ) async throws -> URL {
        let rootURL = try modelRootURL()
            .appendingPathComponent(manifest.localDirectoryName, isDirectory: true)
        let partialURL = rootURL.appendingPathExtension("partial")

        if fileManager.fileExists(atPath: partialURL.path) {
            try fileManager.removeItem(at: partialURL)
        }
        try fileManager.createDirectory(
            at: partialURL,
            withIntermediateDirectories: true
        )

        for (index, file) in manifest.files.enumerated() {
            let destinationURL = partialURL.appendingPathComponent(file.localPath)
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try await downloadFile(
                from: manifest.remoteURL(for: file),
                to: destinationURL,
                progress: Qwen3ModelDownloadProgress(
                    fileIndex: index,
                    fileCount: manifest.fileCount,
                    fileName: file.localPath,
                    fileProgress: 0
                ),
                progressHandler: progress
            )
        }

        if fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.removeItem(at: rootURL)
        }
        try fileManager.moveItem(at: partialURL, to: rootURL)
        return rootURL
    }

    private func modelRootURL() throws -> URL {
        let paths: ApplicationSupportPaths
        do {
            paths = try ApplicationSupportPaths.live(fileManager: fileManager)
        } catch ApplicationSupportPathsError.applicationSupportDirectoryUnavailable {
            throw Qwen3ModelDownloadError.applicationSupportUnavailable
        }

        try paths.ensureDirectories(fileManager: fileManager)
        return paths.modelsDirectory
    }

    private func downloadFile(
        from sourceURL: URL,
        to destinationURL: URL,
        progress: Qwen3ModelDownloadProgress,
        progressHandler: @escaping ProgressHandler
    ) async throws {
        activeDestinationURL = destinationURL
        activeProgress = progress
        activeProgressHandler = progressHandler
        activeMoveResult = nil
        await progressHandler(progress)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                activeContinuation = continuation
                session.downloadTask(with: sourceURL).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }

        activeContinuation = nil
        activeDestinationURL = nil
        activeProgress = nil
        activeProgressHandler = nil
        activeMoveResult = nil
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let activeProgress, totalBytesExpectedToWrite > 0 else { return }
        let progress = Qwen3ModelDownloadProgress(
            fileIndex: activeProgress.fileIndex,
            fileCount: activeProgress.fileCount,
            fileName: activeProgress.fileName,
            fileProgress: min(
                1,
                Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            )
        )
        Task { @MainActor [activeProgressHandler] in
            activeProgressHandler?(progress)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let destinationURL = activeDestinationURL else {
            activeMoveResult = .failure(Qwen3ModelDownloadError.downloadedFileUnavailable)
            return
        }

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: location, to: destinationURL)
            activeMoveResult = .success(())
        } catch {
            activeMoveResult = .failure(error)
        }
    }

    func urlSession(
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
                throwing: Qwen3ModelDownloadError.downloadedFileUnavailable
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

enum Qwen3ModelDownloadError: LocalizedError {
    case applicationSupportUnavailable
    case downloadedFileUnavailable

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "无法定位 Application Support 目录。"
        case .downloadedFileUnavailable:
            return "模型文件下载完成但临时文件不可用。"
        }
    }
}
