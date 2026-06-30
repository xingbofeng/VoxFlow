import Foundation

enum ScreenRecordingFileStorageError: Error, LocalizedError {
    case finalizeFailed(String)
    case deleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .finalizeFailed(let reason):
            return L10n.format("recording.error.file_finalize_failed_format", comment: "", reason)
        case .deleteFailed(let reason):
            return L10n.format("recording.error.file_delete_failed_format", comment: "", reason)
        }
    }
}

/// 区域录屏文件生命周期管理：id、临时文件、最终 `.mp4`、缩略图、清理。
///
/// 录屏先写入临时目录，成功后原子移动到最终目录；取消则删除临时文件。
/// 不持有 `SCStream` 或 `AVAssetWriter`，仅负责文件路径与移动/删除。
struct ScreenRecordingFileStorage {
    private let paths: ApplicationSupportPaths
    private let fileManager: FileManager

    init(paths: ApplicationSupportPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func makeID() -> String {
        UUID().uuidString
    }

    func temporaryURL(for id: String) -> URL {
        paths.screenRecordingTemporaryURL(forID: id)
    }

    func finalURL(for id: String) -> URL {
        paths.screenRecordingURL(forID: id)
    }

    func thumbnailURL(for id: String) -> URL {
        paths.screenRecordingsDirectory.appendingPathComponent("\(id).jpg", isDirectory: false)
    }

    /// 成功完成：把临时录屏文件原子移动到最终 `.mp4` 路径。
    /// 若最终路径已存在则先移除，保证幂等。
    @discardableResult
    func finalize(temporaryURL: URL, finalURL: URL) throws -> URL {
        AppLogger.general.debug("ScreenRecordingFileStorage finalize temp=\(temporaryURL.path) final=\(finalURL.path)")
        guard fileManager.fileExists(atPath: temporaryURL.path) else {
            throw ScreenRecordingFileStorageError.finalizeFailed(
                L10n.format("recording.error.temporary_file_missing_format", comment: "", temporaryURL.path)
            )
        }
        if fileManager.fileExists(atPath: finalURL.path) {
            try? fileManager.removeItem(at: finalURL)
        }
        do {
            try fileManager.moveItem(at: temporaryURL, to: finalURL)
        } catch {
            AppLogger.general.error("ScreenRecordingFileStorage finalize failed reason=\(error.localizedDescription)")
            throw ScreenRecordingFileStorageError.finalizeFailed(error.localizedDescription)
        }
        AppLogger.general.info("ScreenRecordingFileStorage finalize completed final=\(finalURL.path)")
        return finalURL
    }

    /// 取消或失败：删除临时录屏文件。不存在时静默忽略。
    func removeTemporary(at url: URL) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
        AppLogger.general.debug("ScreenRecordingFileStorage removeTemporary path=\(url.path)")
    }

    /// 返回文件大小（字节）；文件不存在或读取失败返回 nil。
    func fileSize(at url: URL) -> Int? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int else {
            return nil
        }
        return size
    }

    /// 删除最终录屏文件（多媒体历史删除时调用）。
    func removeFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw ScreenRecordingFileStorageError.deleteFailed(error.localizedDescription)
        }
    }

    /// 启动时清理过期的临时录屏文件（早于 cutoff 的临时文件视为残留并删除）。
    func cleanupStaleTemporaryFiles(olderThan cutoff: Date) {
        let tempDir = paths.screenRecordingTemporaryDirectory
        guard let entries = try? fileManager.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return
        }
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
            let modDate = values?.contentModificationDate ?? Date.distantPast
            if modDate < cutoff {
                try? fileManager.removeItem(at: entry)
                AppLogger.general.debug("ScreenRecordingFileStorage cleanup stale temp path=\(entry.path)")
            }
        }
    }
}
