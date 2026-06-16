import Foundation

struct SherpaASRModelDownloadProgress: Sendable, Equatable {
    let fractionCompleted: Double?
    let status: String
}

protocol SherpaASRModelDownloading: Sendable {
    func download(
        variant: SherpaASRModelVariant,
        progress: @escaping @MainActor @Sendable (SherpaASRModelDownloadProgress) -> Void
    ) async throws -> URL
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

    init(
        fileManager: FileManager = .default,
        session: URLSession = .shared
    ) {
        self.fileManager = fileManager
        self.session = session
    }

    func download(
        variant: SherpaASRModelVariant,
        progress: @escaping @MainActor @Sendable (SherpaASRModelDownloadProgress) -> Void
    ) async throws -> URL {
        await progress(.init(fractionCompleted: nil, status: "下载 \(variant.archiveName)"))
        let (temporaryArchive, response) = try await session.download(from: variant.archiveURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw SherpaASRModelDownloaderError.invalidArchive
        }

        let destination = variant.defaultDirectoryURL
        let modelsRoot = destination.deletingLastPathComponent()
        let stagingRoot = modelsRoot.appendingPathComponent(
            ".\(variant.directoryName)-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: stagingRoot) }
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        await progress(.init(fractionCompleted: nil, status: "解压模型文件"))
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
            throw SherpaASRModelDownloaderError.extractionFailed(message)
        }

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
            throw SherpaASRModelDownloaderError.incompleteModel(missing)
        }

        try fileManager.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: extracted, to: destination)
        await progress(.init(fractionCompleted: 1, status: "模型已就绪"))
        return destination
    }
}
