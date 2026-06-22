import Foundation

final class VoiceTaskAudioService {
    private let paths: ApplicationSupportPaths
    private let repository: VoiceTaskRepository
    private let clock: any AppClock
    private let fileManager: FileManager

    /// Audio for failed transcriptions is retained for this duration before cleanup.
    static let failedTaskRetentionInterval: TimeInterval = 24 * 3600

    init(
        paths: ApplicationSupportPaths,
        repository: VoiceTaskRepository,
        clock: any AppClock,
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.repository = repository
        self.clock = clock
        self.fileManager = fileManager
    }

    /// Deletes the audio file for a task after successful transcription.
    /// If the task status is not completed/partiallyCompleted, the audio is retained.
    func cleanupAfterSuccessfulTranscription(taskID: String) throws {
        AppLogger.audio.debug("清理成功任务音频：taskID=\(taskID)")
        guard let task = try repository.fetch(id: taskID) else {
            // Task not found — delete orphan audio if it exists.
            AppLogger.audio.warning("未找到任务记录，尝试清理孤儿音频：taskID=\(taskID)")
            deleteAudioFile(forTaskID: taskID)
            return
        }
        guard task.status == .completed || task.status == .partiallyCompleted else {
            // Non-successful status — retain audio for potential retry/debugging.
            AppLogger.audio.debug("任务未成功完成，保留音频：taskID=\(taskID), status=\(task.status.rawValue)")
            return
        }
        AppLogger.audio.debug("删除已完成任务音频：taskID=\(taskID), status=\(task.status.rawValue)")
        deleteAudioFile(forTaskID: taskID)
    }

    /// Deletes audio files for failed tasks whose audio is older than 24 hours.
    /// Called on app launch.
    func cleanupStaleAudio() throws {
        AppLogger.audio.debug("启动过期音频清理")
        let audioDirectory = paths.voiceTaskAudioDirectory
        guard fileManager.fileExists(atPath: audioDirectory.path) else {
            AppLogger.audio.debug("音频目录不存在，跳过清理：\(audioDirectory.path)")
            return
        }

        let cutoff = clock.now.addingTimeInterval(-Self.failedTaskRetentionInterval)
        AppLogger.audio.debug("过期阈值: \(cutoff)")

        let contents = try fileManager.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )

        for fileURL in contents where fileURL.pathExtension == "m4a" {
            let taskID = fileURL.deletingPathExtension().lastPathComponent

            // Check the task record: only clean up failed or cancelled tasks.
            guard let task = try repository.fetch(id: taskID) else {
                // No task record — orphan file, safe to delete.
                AppLogger.audio.info("清理孤儿任务音频：\(taskID)")
                try? fileManager.removeItem(at: fileURL)
                continue
            }

            guard task.status == .failed || task.status == .cancelled else {
                AppLogger.audio.debug("保留非失败音频：taskID=\(taskID), status=\(task.status.rawValue)")
                continue
            }

            // Use the task's updatedAt as the reference time for age.
            if task.updatedAt < cutoff {
                AppLogger.audio.info("删除过期失败/取消任务音频：taskID=\(taskID), updatedAt=\(task.updatedAt)")
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    // MARK: - Private

    private func deleteAudioFile(forTaskID taskID: String) {
        let audioURL = paths.voiceTaskAudioURL(forTaskID: taskID)
        if fileManager.fileExists(atPath: audioURL.path) {
            AppLogger.audio.debug("删除音频文件：\(audioURL.path)")
            try? fileManager.removeItem(at: audioURL)
        } else {
            AppLogger.audio.debug("音频文件不存在，跳过删除：\(audioURL.path)")
        }
    }
}
