import Foundation

struct ScreenshotRecord: Equatable, Identifiable {
    let id: String
    let ocrText: String
    let translatedText: String?
    let summaryText: String?
    let imagePath: String?
    let charCount: Int
    var isFavorited: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}

struct ScreenshotRecordStats: Equatable {
    let totalRecords: Int
    let todayRecords: Int
    let totalCharacters: Int
    let favoritedRecords: Int
}

enum ScreenshotRecordFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case thisWeek
    case thisMonth
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .today: return "今天"
        case .thisWeek: return "本周"
        case .thisMonth: return "本月"
        case .favorites: return "收藏"
        }
    }
}

protocol ScreenshotRecordRepository {
    func save(_ record: ScreenshotRecord) throws
    func record(id: String) throws -> ScreenshotRecord?
    func list(filter: ScreenshotRecordFilter, search: String?) throws -> [ScreenshotRecord]
    func page(limit: Int, offset: Int, search: String?, onlyFavorites: Bool) throws -> ScreenshotRecordPage
    func toggleFavorite(id: String, isFavorited: Bool, updatedAt: Date) throws
    func softDelete(id: String, deletedAt: Date) throws
    func stats() throws -> ScreenshotRecordStats
}

struct ScreenshotRecordPage: Equatable {
    let records: [ScreenshotRecord]
    let totalCount: Int
}

final class SQLiteScreenshotRecordRepository: ScreenshotRecordRepository {
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

    func save(_ record: ScreenshotRecord) throws {
        AppLogger.database.debug(
            "保存截图记录：id=\(record.id), chars=\(record.charCount), favorite=\(record.isFavorited)"
        )
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                INSERT INTO screenshot_records (
                    id, ocr_text, translated_text, summary_text, image_path,
                    char_count, is_favorited, created_at, updated_at, deleted_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    ocr_text = excluded.ocr_text,
                    translated_text = excluded.translated_text,
                    summary_text = excluded.summary_text,
                    image_path = excluded.image_path,
                    char_count = excluded.char_count,
                    is_favorited = excluded.is_favorited,
                    updated_at = excluded.updated_at,
                    deleted_at = excluded.deleted_at
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
            _ = try statement.step()
        }
        AppLogger.database.info("截图记录已保存：id=\(record.id)")
    }

    func record(id: String) throws -> ScreenshotRecord? {
        AppLogger.database.debug("查询截图记录：id=\(id)")
        return try databaseQueue.read { connection in
            let statement = try connection.prepare(
                """
                SELECT id, ocr_text, translated_text, summary_text, image_path,
                       char_count, is_favorited, created_at, updated_at, deleted_at
                FROM screenshot_records
                WHERE id = ?
                """
            )
            try statement.bind(id, at: 1)
            guard try statement.step() else {
                AppLogger.database.warning("截图记录不存在：id=\(id)")
                return nil
            }
            return try row(from: statement)
        }
    }

    func list(filter: ScreenshotRecordFilter, search: String?) throws -> [ScreenshotRecord] {
        AppLogger.database.debug("列出截图记录：filter=\(filter.rawValue), searchLen=\(search?.count ?? 0)")
        var sql = """
            SELECT id, ocr_text, translated_text, summary_text, image_path,
                   char_count, is_favorited, created_at, updated_at, deleted_at
            FROM screenshot_records
            WHERE deleted_at IS NULL
        """

        switch filter {
        case .all:
            break
        case .today:
            sql += " AND created_at >= ? AND created_at < ?"
        case .thisWeek:
            sql += " AND created_at >= ? AND created_at < ?"
        case .thisMonth:
            sql += " AND created_at >= ? AND created_at < ?"
        case .favorites:
            sql += " AND is_favorited = 1"
        }

        if let search, !search.isEmpty {
            sql += " AND (ocr_text LIKE ? OR translated_text LIKE ? OR summary_text LIKE ?)"
        }

        sql += " ORDER BY created_at DESC"

        return try databaseQueue.read { connection in
            let statement = try connection.prepare(sql)
            var bindIndex: Int32 = 1
            if let interval = dateInterval(for: filter) {
                try statement.bind(formatter.string(from: interval.start), at: bindIndex)
                try statement.bind(formatter.string(from: interval.end), at: bindIndex + 1)
                bindIndex += 2
            }
            if let search, !search.isEmpty {
                let pattern = "%\(search)%"
                try statement.bind(pattern, at: bindIndex)
                try statement.bind(pattern, at: bindIndex + 1)
                try statement.bind(pattern, at: bindIndex + 2)
            }
            var records: [ScreenshotRecord] = []
            while try statement.step() {
                records.append(try row(from: statement))
            }
            AppLogger.database.debug("截图记录列表返回：count=\(records.count)")
            return records
        }
    }

    func toggleFavorite(id: String, isFavorited: Bool, updatedAt: Date) throws {
        AppLogger.database.debug("更新截图收藏：id=\(id), favorite=\(isFavorited)")
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                "UPDATE screenshot_records SET is_favorited = ?, updated_at = ? WHERE id = ?"
            )
            try statement.bind(isFavorited ? 1 : 0, at: 1)
            try statement.bind(formatter.string(from: updatedAt), at: 2)
            try statement.bind(id, at: 3)
            _ = try statement.step()
        }
        AppLogger.database.info("截图收藏已更新：id=\(id), favorite=\(isFavorited)")
    }

    func softDelete(id: String, deletedAt: Date) throws {
        AppLogger.database.debug("删除截图记录：id=\(id)")
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
        AppLogger.database.warning("截图记录已软删：id=\(id)")
    }

    func stats() throws -> ScreenshotRecordStats {
        AppLogger.database.debug("查询截图统计")
        return try databaseQueue.read { connection in
            let statement = try connection.prepare(
                """
                SELECT
                    (SELECT COUNT(*) FROM screenshot_records WHERE deleted_at IS NULL) AS total,
                    (SELECT COUNT(*) FROM screenshot_records WHERE deleted_at IS NULL AND created_at >= ? AND created_at < ?) AS today,
                    (SELECT COALESCE(SUM(char_count), 0) FROM screenshot_records WHERE deleted_at IS NULL) AS chars,
                    (SELECT COUNT(*) FROM screenshot_records WHERE deleted_at IS NULL AND is_favorited = 1) AS fav
                """
            )
            let today = dayInterval(containing: now())
            try statement.bind(formatter.string(from: today.start), at: 1)
            try statement.bind(formatter.string(from: today.end), at: 2)
            guard try statement.step() else {
                return ScreenshotRecordStats(totalRecords: 0, todayRecords: 0, totalCharacters: 0, favoritedRecords: 0)
            }
            let stats = ScreenshotRecordStats(
                totalRecords: statement.columnInt(at: 0),
                todayRecords: statement.columnInt(at: 1),
                totalCharacters: statement.columnInt(at: 2),
                favoritedRecords: statement.columnInt(at: 3)
            )
            AppLogger.database.debug(
                "截图统计返回：total=\(stats.totalRecords), today=\(stats.todayRecords), chars=\(stats.totalCharacters), fav=\(stats.favoritedRecords)"
            )
            return stats
        }
    }

    private func dateInterval(for filter: ScreenshotRecordFilter) -> DateInterval? {
        switch filter {
        case .all, .favorites:
            return nil
        case .today:
            return dayInterval(containing: now())
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now())
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now())
        }
    }

    private func dayInterval(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 24 * 60 * 60)
    }

    func page(limit: Int, offset: Int, search: String?, onlyFavorites: Bool = false) throws -> ScreenshotRecordPage {
        AppLogger.database.debug(
            "查询截图分页：limit=\(limit), offset=\(offset), favoritesOnly=\(onlyFavorites), searchLen=\(search?.count ?? 0)"
        )
        var whereClause = "WHERE deleted_at IS NULL"
        if onlyFavorites {
            whereClause += " AND is_favorited = 1"
        }
        if let search, !search.isEmpty {
            whereClause += " AND (ocr_text LIKE ? OR translated_text LIKE ? OR summary_text LIKE ?)"
        }

        let countSQL = "SELECT COUNT(*) FROM screenshot_records \(whereClause)"
        let dataSQL = """
            SELECT id, ocr_text, translated_text, summary_text, image_path,
                   char_count, is_favorited, created_at, updated_at, deleted_at
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

            var records: [ScreenshotRecord] = []
            while try dataStatement.step() {
                records.append(try row(from: dataStatement))
            }
            let page = ScreenshotRecordPage(records: records, totalCount: totalCount)
            AppLogger.database.debug("截图分页返回：count=\(records.count), total=\(totalCount)")
            return page
        }
    }

    private func row(from statement: SQLiteStatement) throws -> ScreenshotRecord {
        guard let id = statement.columnString(at: 0),
              let ocrText = statement.columnString(at: 1),
              let createdAtText = statement.columnString(at: 7),
              let updatedAtText = statement.columnString(at: 8),
              let createdAt = formatter.date(from: createdAtText),
              let updatedAt = formatter.date(from: updatedAtText) else {
            throw SQLiteError.stepFailed("Invalid screenshot_records row.")
        }

        let deletedAt = statement.columnString(at: 9).flatMap(formatter.date(from:))
        return ScreenshotRecord(
            id: id,
            ocrText: ocrText,
            translatedText: statement.columnString(at: 2),
            summaryText: statement.columnString(at: 3),
            imagePath: statement.columnString(at: 4),
            charCount: statement.columnInt(at: 5),
            isFavorited: statement.columnInt(at: 6) != 0,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}
