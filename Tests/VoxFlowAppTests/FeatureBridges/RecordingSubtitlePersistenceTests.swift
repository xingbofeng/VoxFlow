import XCTest
@testable import VoxFlowApp

final class RecordingSubtitlePersistenceTests: XCTestCase {
    private var queue: DatabaseQueue!
    private var repository: SQLiteMediaRecordRepository!
    private var screenshotRepository: SQLiteScreenshotRecordRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        repository = SQLiteMediaRecordRepository(databaseQueue: queue)
        screenshotRepository = SQLiteScreenshotRecordRepository(databaseQueue: queue)
    }

    override func tearDown() {
        repository = nil
        screenshotRepository = nil
        queue = nil
        super.tearDown()
    }

    // MARK: - 1.1 旧记录默认 subtitle_status = none

    func testLegacyScreenshotDefaultsToNoneSubtitleStatus() throws {
        let screenshot = ScreenshotRecord(
            id: UUID().uuidString,
            ocrText: "旧截图",
            translatedText: nil,
            summaryText: nil,
            imagePath: "/tmp/shot.png",
            charCount: 3,
            isFavorited: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            deletedAt: nil
        )
        try screenshotRepository.save(screenshot)

        let media = try XCTUnwrap(try repository.record(id: screenshot.id))
        XCTAssertEqual(media.subtitleStatus, .none)
        XCTAssertNil(media.subtitleDraftPath)
        XCTAssertNil(media.subtitledVideoPath)
        XCTAssertNil(media.subtitleUpdatedAt)
    }

    func testLegacyRecordingDefaultsToNoneSubtitleStatus() throws {
        let recording = makeRecordingRecord(audioMode: .microphone)
        try repository.save(recording)

        let fetched = try XCTUnwrap(try repository.record(id: recording.id))
        XCTAssertEqual(fetched.subtitleStatus, .none)
        XCTAssertNil(fetched.subtitleErrorMessage)
    }

    // MARK: - 1.2 保存并读取字幕状态与路径

    func testUpdateSubtitleStatePersistsStatusAndPaths() throws {
        let recording = makeRecordingRecord(audioMode: .microphone)
        try repository.save(recording)

        let now = Date(timeIntervalSince1970: 1_750_000_000)
        try repository.updateSubtitleState(
            id: recording.id,
            state: RecordingSubtitleState(
                status: .draftReady,
                draftPath: "/tmp/draft.json",
                srtPath: "/tmp/draft.srt",
                subtitledVideoPath: nil,
                errorMessage: nil,
                updatedAt: now
            ),
            updatedAt: now
        )

        let fetched = try repository.record(id: recording.id)
        XCTAssertEqual(fetched?.subtitleStatus, .draftReady)
        XCTAssertEqual(fetched?.subtitleDraftPath, "/tmp/draft.json")
        XCTAssertEqual(fetched?.subtitleSrtPath, "/tmp/draft.srt")
        XCTAssertNil(fetched?.subtitledVideoPath)
        XCTAssertEqual(fetched?.subtitleUpdatedAt, now)
    }

    func testUpdateSubtitleStateToBurnedKeepsOriginalVideoPath() throws {
        let recording = makeRecordingRecord(videoPath: "/tmp/original.mp4", audioMode: .microphone)
        try repository.save(recording)

        let now = Date()
        try repository.updateSubtitleState(
            id: recording.id,
            state: RecordingSubtitleState(
                status: .burned,
                draftPath: "/tmp/draft.json",
                srtPath: "/tmp/draft.srt",
                subtitledVideoPath: "/tmp/subtitled.mp4",
                errorMessage: nil,
                updatedAt: now
            ),
            updatedAt: now
        )

        let fetched = try repository.record(id: recording.id)
        XCTAssertEqual(fetched?.subtitleStatus, .burned)
        XCTAssertEqual(fetched?.subtitledVideoPath, "/tmp/subtitled.mp4")
        XCTAssertEqual(fetched?.videoPath, "/tmp/original.mp4")
    }

    func testUpdateSubtitleStateToFailedPersistsErrorMessage() throws {
        let recording = makeRecordingRecord(audioMode: .microphone)
        try repository.save(recording)

        let now = Date()
        try repository.updateSubtitleState(
            id: recording.id,
            state: RecordingSubtitleState(
                status: .failed,
                draftPath: nil,
                srtPath: nil,
                subtitledVideoPath: nil,
                errorMessage: "语音识别失败",
                updatedAt: now
            ),
            updatedAt: now
        )

        let fetched = try repository.record(id: recording.id)
        XCTAssertEqual(fetched?.subtitleStatus, .failed)
        XCTAssertEqual(fetched?.subtitleErrorMessage, "语音识别失败")
    }

    func testRestoringFailedStateRoundTripsThroughSave() throws {
        let now = Date()
        let recording = MediaRecord(
            id: UUID().uuidString,
            mediaType: .screenRecording,
            videoPath: "/tmp/rec.mp4",
            durationMs: 4_000,
            audioMode: .microphone,
            subtitleStatus: .failed,
            subtitleDraftPath: "/tmp/d.json",
            subtitleSrtPath: "/tmp/d.srt",
            subtitledVideoPath: nil,
            subtitleErrorMessage: "导出失败",
            subtitleUpdatedAt: now,
            createdAt: now,
            updatedAt: now
        )
        try repository.save(recording)

        let fetched = try repository.record(id: recording.id)
        XCTAssertEqual(fetched?.subtitleStatus, .failed)
        XCTAssertEqual(fetched?.subtitleErrorMessage, "导出失败")
        XCTAssertEqual(fetched?.subtitleDraftPath, "/tmp/d.json")
    }

    // MARK: - 迁移兼容：老库无字幕列时迁移补齐

    func testMigrationAddsSubtitleColumnsToLegacyTable() throws {
        let legacyQueue = try DatabaseQueue(connection: .inMemory())
        try legacyQueue.write { connection in
            try connection.execute(
                """
                CREATE TABLE schema_migrations (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    applied_at TEXT NOT NULL
                );
                """
            )
            for id in 1...16 {
                try connection.execute(
                    "INSERT INTO schema_migrations (id, name, applied_at) VALUES (\(id), 'legacy', '2026-06-23T00:00:00Z')"
                )
            }
            try connection.execute(
                """
                CREATE TABLE screenshot_records (
                    id TEXT PRIMARY KEY,
                    ocr_text TEXT NOT NULL DEFAULT '',
                    translated_text TEXT, summary_text TEXT, image_path TEXT,
                    char_count INTEGER NOT NULL DEFAULT 0, is_favorited INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT,
                    media_type TEXT NOT NULL DEFAULT 'screenshot',
                    video_path TEXT, thumbnail_path TEXT,
                    duration_ms INTEGER NOT NULL DEFAULT 0, width INTEGER NOT NULL DEFAULT 0,
                    height INTEGER NOT NULL DEFAULT 0, file_size_bytes INTEGER NOT NULL DEFAULT 0,
                    audio_mode TEXT NOT NULL DEFAULT 'none'
                );
                """
            )
            try connection.execute(
                """
                INSERT INTO screenshot_records (id, ocr_text, created_at, updated_at)
                VALUES ('legacy-rec', '旧录屏', '2026-06-01T00:00:00Z', '2026-06-01T00:00:00Z');
                """
            )
        }

        try AppDatabase.migrator().migrate(legacyQueue)

        let repaired = SQLiteMediaRecordRepository(databaseQueue: legacyQueue)
        let legacy = try XCTUnwrap(try repaired.record(id: "legacy-rec"))
        XCTAssertEqual(legacy.subtitleStatus, .none)
        XCTAssertNil(legacy.subtitleUpdatedAt)
    }

    // MARK: - Helper

    private func makeRecordingRecord(
        id: String = UUID().uuidString,
        videoPath: String = "/tmp/rec.mp4",
        audioMode: MediaAudioMode = .microphone
    ) -> MediaRecord {
        MediaRecord(
            id: id,
            mediaType: .screenRecording,
            videoPath: videoPath,
            durationMs: 3_000,
            width: 1280,
            height: 720,
            fileSizeBytes: 512,
            audioMode: audioMode,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
