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
        guard let task = try repository.fetch(id: taskID) else {
            // Task not found — delete orphan audio if it exists.
            deleteAudioFile(forTaskID: taskID)
            return
        }
        guard task.status == .completed || task.status == .partiallyCompleted else {
            // Non-successful status — retain audio for potential retry/debugging.
            return
        }
        deleteAudioFile(forTaskID: taskID)
    }

    /// Deletes audio files for failed tasks whose audio is older than 24 hours.
    /// Called on app launch.
    func cleanupStaleAudio() throws {
        let audioDirectory = paths.voiceTaskAudioDirectory
        guard fileManager.fileExists(atPath: audioDirectory.path) else {
            return
        }

        let cutoff = clock.now.addingTimeInterval(-Self.failedTaskRetentionInterval)

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
                try? fileManager.removeItem(at: fileURL)
                continue
            }

            guard task.status == .failed || task.status == .cancelled else {
                continue
            }

            // Use the task's updatedAt as the reference time for age.
            if task.updatedAt < cutoff {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    // MARK: - Private

    private func deleteAudioFile(forTaskID taskID: String) {
        let audioURL = paths.voiceTaskAudioURL(forTaskID: taskID)
        if fileManager.fileExists(atPath: audioURL.path) {
            try? fileManager.removeItem(at: audioURL)
        }
    }
}
