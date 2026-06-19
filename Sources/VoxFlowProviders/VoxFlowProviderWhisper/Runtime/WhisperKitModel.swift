import Foundation
@preconcurrency import WhisperKit

public enum WhisperKitModelVariant: String, CaseIterable, Sendable {
    case turbo
    case largeV3

    public var remoteName: String {
        switch self {
        case .turbo:
            return "openai_whisper-large-v3-v20240930_turbo_632MB"
        case .largeV3:
            return "openai_whisper-large-v3_947MB"
        }
    }

    public var requiredPaths: [String] {
        [
            "MelSpectrogram.mlmodelc",
            "AudioEncoder.mlmodelc",
            "TextDecoder.mlmodelc",
        ]
    }

    public func defaultDirectoryURL(modelsDirectory: URL) -> URL {
        modelsDirectory
            .appendingPathComponent("WhisperKit", isDirectory: true)
            .appendingPathComponent(remoteName, isDirectory: true)
    }

    public func modelsExist(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        requiredPaths.allSatisfy { relativePath in
            let url = directory.appendingPathComponent(relativePath, isDirectory: true)
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
            ) else {
                return false
            }
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true,
                      (values.fileSize ?? 0) > 0 else {
                    continue
                }
                return true
            }
            return false
        }
    }
}

public struct WhisperKitModelDownloadProgress: Sendable, Equatable {
    public let fractionCompleted: Double
    public let status: String

    public init(fractionCompleted: Double, status: String) {
        self.fractionCompleted = fractionCompleted
        self.status = status
    }
}

public protocol WhisperKitModelDownloading: Sendable {
    func download(
        variant: WhisperKitModelVariant,
        modelsDirectory: URL,
        progress: @escaping @MainActor @Sendable (WhisperKitModelDownloadProgress) -> Void
    ) async throws -> URL
}

public struct WhisperKitModelDownloader: WhisperKitModelDownloading, @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func download(
        variant: WhisperKitModelVariant,
        modelsDirectory: URL,
        progress: @escaping @MainActor @Sendable (WhisperKitModelDownloadProgress) -> Void
    ) async throws -> URL {
        let destination = variant.defaultDirectoryURL(modelsDirectory: modelsDirectory)
        let modelsRoot = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        await progress(.init(fractionCompleted: 0, status: "下载 \(variant.remoteName)"))

        let downloaded = try await WhisperKit.download(
            variant: variant.remoteName,
            downloadBase: modelsRoot.appendingPathComponent(".downloads", isDirectory: true)
        ) { update in
            Task { @MainActor in
                progress(.init(
                    fractionCompleted: update.fractionCompleted,
                    status: "下载 Whisper 模型"
                ))
            }
        }
        guard variant.modelsExist(at: downloaded, fileManager: fileManager) else {
            throw WhisperProviderError.modelNotInstalled
        }

        let staging = modelsRoot.appendingPathComponent(
            ".\(variant.remoteName)-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.copyItem(at: downloaded, to: staging)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: staging, to: destination)
        await progress(.init(fractionCompleted: 1, status: "模型已就绪"))
        return destination
    }
}
