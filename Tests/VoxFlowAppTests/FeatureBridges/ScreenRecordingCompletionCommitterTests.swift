import XCTest
@testable import VoxFlowApp

final class ScreenRecordingCompletionCommitterTests: XCTestCase {
    private func makeSubject() throws -> (
        committer: ScreenRecordingCompletionCommitter,
        repository: CapturingMediaRecordRepository,
        storage: ScreenRecordingFileStorage,
        paths: ApplicationSupportPaths,
        root: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxFlowRecCommit-\(UUID().uuidString)", isDirectory: true)
        let paths = ApplicationSupportPaths(applicationSupportDirectory: root)
        try paths.ensureDirectories()
        let storage = ScreenRecordingFileStorage(paths: paths)
        let repository = CapturingMediaRecordRepository()
        let committer = ScreenRecordingCompletionCommitter(
            fileStorage: storage,
            repository: repository,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        return (committer, repository, storage, paths, root)
    }

    func testSuccessfulCommitFinalizesTemporaryMP4AndSavesMediaRecord() throws {
        let subject = try makeSubject()
        defer { try? FileManager.default.removeItem(at: subject.root) }

        let id = "recording-1"
        let temporaryURL = subject.storage.temporaryURL(for: id)
        try Data("mp4-bytes".utf8).write(to: temporaryURL)

        let record = try subject.committer.commitSuccessfulRecording(
            id: id,
            temporaryURL: temporaryURL,
            completion: ScreenRecordingCompletion(
                url: temporaryURL,
                durationMs: 2_500,
                width: 1280,
                height: 720,
                fileSizeBytes: 9,
                audioMode: .none,
                thumbnailPath: nil
            )
        )

        let finalURL = subject.storage.finalURL(for: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalURL.path))
        XCTAssertEqual(record.mediaType, .screenRecording)
        XCTAssertEqual(record.videoPath, finalURL.path)
        XCTAssertEqual(record.durationMs, 2_500)
        XCTAssertEqual(record.width, 1280)
        XCTAssertEqual(record.height, 720)
        XCTAssertEqual(record.fileSizeBytes, 9)
        XCTAssertEqual(subject.repository.savedRecords.map(\.id), [id])
    }

    func testCancelRemovesTemporaryFileWithoutSavingHistory() throws {
        let subject = try makeSubject()
        defer { try? FileManager.default.removeItem(at: subject.root) }

        let temporaryURL = subject.storage.temporaryURL(for: "cancelled")
        try Data("tmp".utf8).write(to: temporaryURL)

        subject.committer.discardCancelledRecording(temporaryURL: temporaryURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
        XCTAssertTrue(subject.repository.savedRecords.isEmpty)
    }

    func testFailureRemovesTemporaryFileWithoutSavingHistory() throws {
        let subject = try makeSubject()
        defer { try? FileManager.default.removeItem(at: subject.root) }

        let temporaryURL = subject.storage.temporaryURL(for: "failed")
        try Data("tmp".utf8).write(to: temporaryURL)

        subject.committer.discardFailedRecording(temporaryURL: temporaryURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
        XCTAssertTrue(subject.repository.savedRecords.isEmpty)
    }
}

private final class CapturingMediaRecordRepository: MediaRecordRepository {
    private(set) var savedRecords: [MediaRecord] = []

    func save(_ record: MediaRecord) throws {
        savedRecords.append(record)
    }

    func record(id: String) throws -> MediaRecord? {
        savedRecords.first { $0.id == id }
    }

    func page(limit: Int, offset: Int, filter: MediaRecordFilter, search: String?) throws -> MediaRecordPage {
        MediaRecordPage(records: savedRecords, totalCount: savedRecords.count)
    }

    func toggleFavorite(id: String, isFavorited: Bool, updatedAt: Date) throws {}

    func updateSubtitleState(id: String, state: RecordingSubtitleState, updatedAt: Date) throws {}

    func softDelete(id: String, deletedAt: Date) throws {}

    func stats() throws -> MediaRecordStats {
        MediaRecordStats(totalMedia: savedRecords.count, todayMedia: savedRecords.count, screenshotCount: 0, recordingCount: savedRecords.count)
    }
}
