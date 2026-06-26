import Foundation

/// Commits a finished screen recording into durable storage and multimedia history.
///
/// This object deliberately knows nothing about `SCStream` or `AVAssetWriter`.
/// It only binds the file lifecycle to history persistence: a recording enters
/// history after the temporary `.mp4` has been finalized successfully.
struct ScreenRecordingCompletionCommitter {
    private let fileStorage: ScreenRecordingFileStorage
    private let repository: any MediaRecordRepository
    private let now: () -> Date

    init(
        fileStorage: ScreenRecordingFileStorage,
        repository: any MediaRecordRepository,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileStorage = fileStorage
        self.repository = repository
        self.now = now
    }

    @discardableResult
    func commitSuccessfulRecording(
        id: String,
        temporaryURL: URL,
        completion: ScreenRecordingCompletion
    ) throws -> MediaRecord {
        let finalURL = fileStorage.finalURL(for: id)
        let finalizedURL = try fileStorage.finalize(
            temporaryURL: temporaryURL,
            finalURL: finalURL
        )
        let timestamp = now()
        let fileSize = fileStorage.fileSize(at: finalizedURL) ?? completion.fileSizeBytes
        let record = MediaRecord(
            id: id,
            mediaType: .screenRecording,
            videoPath: finalizedURL.path,
            thumbnailPath: completion.thumbnailPath,
            durationMs: completion.durationMs,
            width: completion.width,
            height: completion.height,
            fileSizeBytes: fileSize,
            audioMode: completion.audioMode,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        try repository.save(record)
        return record
    }

    func discardCancelledRecording(temporaryURL: URL) {
        fileStorage.removeTemporary(at: temporaryURL)
    }

    func discardFailedRecording(temporaryURL: URL) {
        fileStorage.removeTemporary(at: temporaryURL)
    }
}
