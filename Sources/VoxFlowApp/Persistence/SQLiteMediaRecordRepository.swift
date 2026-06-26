import Foundation

/// `MediaRecordRepository` 的 SQLite 实现。
///
/// 复用 `screenshot_records` 表（已扩展媒体列）。旧截图行通过 `media_type` 默认值
/// `'screenshot'` 自动归为截图类型，无需回填。
final class SQLiteMediaRecordRepository: MediaRecordRepository {
    private let databaseQueue: DatabaseQueue
    private let formatter = ISO8601DateFormatter()
    private let calendar: Calendar
    private let now: () -> Date

    init(
        databaseQueue: DatabaseQueue,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        self.databaseQueue = databaseQueue
        self.calendar = calendar
        self.now = now
    }

    func save(_ record: MediaRecord) throws {
        AppLogger.database.debug(
            "保存多媒体记录：id=\(record.id), type=\(record.mediaType.rawValue), favorite=\(record.isFavorited)"
        )
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                INSERT INTO screenshot_records (
                    id, ocr_text, translated_text, summary_text, image_path,
                    char_count, is_favorited, created_at, updated_at, deleted_at,
                    media_type, video_path, thumbnail_path, duration_ms, width, height,
                    file_size_bytes, audio_mode
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    ocr_text = excluded.ocr_text,
                    translated_text = excluded.translated_text,
                    summary_text = excluded.summary_text,
                    image_path = excluded.image_path,
                    char_count = excluded.char_count,
                    is_favorited = excluded.is_favorited,
                    updated_at = excluded.updated_at,
                    deleted_at = excluded.deleted_at,
                    media_type = excluded.media_type,
                    video_path = excluded.video_path,
                    thumbnail_path = excluded.thumbnail_path,
                    duration_ms = excluded.duration_ms,
                    width = excluded.width,
                    height = excluded.height,
                    file_size_bytes = excluded.file_size_bytes,
                    audio_mode = excluded.audio_mode
                """
            )
            try statement.bind(record.id, at: 1)
            try statement.bind(record.ocrText, at: 2)
            try statement.bind(record.translatedText, at: 3)
            try statement.bind(record.summaryText, at: 4)
            try statement.bind(record.imagePath, at: 5)
            try statement.bind(record.charCount, at: 6)
            try statement.bind(record.isFavorited ? 1 : 0, at: 7)
            try statement.bind(formatter.string(from: record.createdAt), at: 8)
            try statement.bind(formatter.string(from: record.updatedAt), at: 9)
            try statement.bind(record.deletedAt.map(formatter.string(from:)), at: 10)
            try statement.bind(record.mediaType.rawValue, at: 11)
            try statement.bind(record.videoPath, at: 12)
            try statement.bind(record.thumbnailPath, at: 13)
            try statement.bind(record.durationMs, at: 14)
            try statement.bind(record.width, at: 15)
            try statement.bind(record.height, at: 16)
            try statement.bind(record.fileSizeBytes, at: 17)
            try statement.bind(record.audioMode.rawValue, at: 18)
            _ = try statement.step()
        }
        AppLogger.database.info("多媒体记录已保存：id=\(record.id), type=\(record.mediaType.rawValue)")
    }

    func record(id: String) throws -> MediaRecord? {
        AppLogger.database.debug("查询多媒体记录：id=\(id)")
        return try databaseQueue.read { connection in
            let statement = try connection.prepare(
                """
                SELECT id, ocr_text, translated_text, summary_text, image_path,
                       char_count, is_favorited, created_at, updated_at, deleted_at,
                       media_type, video_path, thumbnail_path, duration_ms, width, height,
                       file_size_bytes, audio_mode
                FROM screenshot_records
                WHERE id = ?
                """
            )
            try statement.bind(id, at: 1)
            guard try statement.step() else {
                AppLogger.database.warning("多媒体记录不存在：id=\(id)")
                return nil
            }
            return try row(from: statement)
        }
    }

    func page(
        limit: Int,
        offset: Int,
        filter: MediaRecordFilter,
        search: String?
    ) throws -> MediaRecordPage {
        AppLogger.database.debug(
            "查询多媒体分页：limit=\(limit), offset=\(offset), filter=\(filter.rawValue), searchLen=\(search?.count ?? 0)"
        )
        var whereClause = "WHERE deleted_at IS NULL"
        switch filter {
        case .all:
            break
        case .screenshots:
            whereClause += " AND media_type = 'screenshot'"
        case .recordings:
            whereClause += " AND media_type = 'screenRecording'"
        case .favorites:
            whereClause += " AND is_favorited = 1"
        }
        if let search, !search.isEmpty {
            whereClause += " AND (ocr_text LIKE ? OR translated_text LIKE ? OR summary_text LIKE ?)"
        }

        let countSQL = "SELECT COUNT(*) FROM screenshot_records \(whereClause)"
        let dataSQL = """
            SELECT id, ocr_text, translated_text, summary_text, image_path,
                   char_count, is_favorited, created_at, updated_at, deleted_at,
                   media_type, video_path, thumbnail_path, duration_ms, width, height,
                   file_size_bytes, audio_mode
            FROM screenshot_records
            \(whereClause)
            ORDER BY created_at DESC
            LIMIT ? OFFSET ?
        """

        return try databaseQueue.read { connection in
            let countStatement = try connection.prepare(countSQL)
            if let search, !search.isEmpty {
                let pattern = "%\(search)%"
                try countStatement.bind(pattern, at: 1)
                try countStatement.bind(pattern, at: 2)
                try countStatement.bind(pattern, at: 3)
            }
            _ = try countStatement.step()
            let totalCount = countStatement.columnInt(at: 0)

            let dataStatement = try connection.prepare(dataSQL)
            var bindIndex: Int32 = 1
            if let search, !search.isEmpty {
                let pattern = "%\(search)%"
                try dataStatement.bind(pattern, at: bindIndex)
                try dataStatement.bind(pattern, at: bindIndex + 1)
                try dataStatement.bind(pattern, at: bindIndex + 2)
                bindIndex += 3
            }
            try dataStatement.bind(max(1, limit), at: bindIndex)
            try dataStatement.bind(max(0, offset), at: bindIndex + 1)

            var records: [MediaRecord] = []
            while try dataStatement.step() {
                records.append(try row(from: dataStatement))
            }
            let page = MediaRecordPage(records: records, totalCount: totalCount)
            AppLogger.database.debug("多媒体分页返回：count=\(records.count), total=\(totalCount)")
            return page
        }
    }

    func toggleFavorite(id: String, isFavorited: Bool, updatedAt: Date) throws {
        AppLogger.database.debug("更新多媒体收藏：id=\(id), favorite=\(isFavorited)")
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                "UPDATE screenshot_records SET is_favorited = ?, updated_at = ? WHERE id = ?"
            )
            try statement.bind(isFavorited ? 1 : 0, at: 1)
            try statement.bind(formatter.string(from: updatedAt), at: 2)
            try statement.bind(id, at: 3)
            _ = try statement.step()
        }
        AppLogger.database.info("多媒体收藏已更新：id=\(id), favorite=\(isFavorited)")
    }

    func softDelete(id: String, deletedAt: Date) throws {
        AppLogger.database.debug("删除多媒体记录：id=\(id)")
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                "UPDATE screenshot_records SET deleted_at = ?, updated_at = ? WHERE id = ?"
            )
            let timestamp = formatter.string(from: deletedAt)
            try statement.bind(timestamp, at: 1)
            try statement.bind(timestamp, at: 2)
            try statement.bind(id, at: 3)
            _ = try statement.step()
        }
        AppLogger.database.warning("多媒体记录已软删：id=\(id)")
    }

    func stats() throws -> MediaRecordStats {
        AppLogger.database.debug("查询多媒体统计")
        return try databaseQueue.read { connection in
            let statement = try connection.prepare(
                """
                SELECT
                    (SELECT COUNT(*) FROM screenshot_records WHERE deleted_at IS NULL) AS total,
                    (SELECT COUNT(*) FROM screenshot_records WHERE deleted_at IS NULL AND created_at >= ? AND created_at < ?) AS today,
                    (SELECT COUNT(*) FROM screenshot_records WHERE deleted_at IS NULL AND media_type = 'screenshot') AS screenshots,
                    (SELECT COUNT(*) FROM screenshot_records WHERE deleted_at IS NULL AND media_type = 'screenRecording') AS recordings
                """
            )
            let today = dayInterval(containing: now())
            try statement.bind(formatter.string(from: today.start), at: 1)
            try statement.bind(formatter.string(from: today.end), at: 2)
            guard try statement.step() else {
                return MediaRecordStats(totalMedia: 0, todayMedia: 0, screenshotCount: 0, recordingCount: 0)
            }
            let stats = MediaRecordStats(
                totalMedia: statement.columnInt(at: 0),
                todayMedia: statement.columnInt(at: 1),
                screenshotCount: statement.columnInt(at: 2),
                recordingCount: statement.columnInt(at: 3)
            )
            AppLogger.database.debug(
                "多媒体统计返回：total=\(stats.totalMedia), today=\(stats.todayMedia), screenshots=\(stats.screenshotCount), recordings=\(stats.recordingCount)"
            )
            return stats
        }
    }

    // MARK: - Row decoding

    private func row(from statement: SQLiteStatement) throws -> MediaRecord {
        guard let id = statement.columnString(at: 0),
              let ocrText = statement.columnString(at: 1),
              let createdAtText = statement.columnString(at: 7),
              let updatedAtText = statement.columnString(at: 8),
              let createdAt = formatter.date(from: createdAtText),
              let updatedAt = formatter.date(from: updatedAtText) else {
            throw SQLiteError.stepFailed("Invalid screenshot_records media row.")
        }

        let deletedAt = statement.columnString(at: 9).flatMap(formatter.date(from:))
        let mediaType = MediaType(rawValue: statement.columnString(at: 10) ?? MediaType.screenshot.rawValue) ?? .screenshot
        let audioMode = MediaAudioMode(rawValue: statement.columnString(at: 17) ?? MediaAudioMode.none.rawValue) ?? .none

        return MediaRecord(
            id: id,
            mediaType: mediaType,
            ocrText: ocrText,
            translatedText: statement.columnString(at: 2),
            summaryText: statement.columnString(at: 3),
            imagePath: statement.columnString(at: 4),
            videoPath: statement.columnString(at: 11),
            thumbnailPath: statement.columnString(at: 12),
            durationMs: statement.columnInt(at: 13),
            width: statement.columnInt(at: 14),
            height: statement.columnInt(at: 15),
            fileSizeBytes: statement.columnInt(at: 16),
            audioMode: audioMode,
            charCount: statement.columnInt(at: 5),
            isFavorited: statement.columnInt(at: 6) != 0,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    private func dayInterval(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 24 * 60 * 60)
    }
}
