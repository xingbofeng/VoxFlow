import Foundation

struct HomeHistoryQuery: Equatable {
    var searchText: String = ""
    var startDate: Date?
    var endDate: Date?
    var limit: Int
    var offset: Int
}

struct HomeHistoryRecord: Equatable {
    let id: String
    let rawText: String
    let finalText: String
    let appBundleID: String?
    let appName: String?
    let charCount: Int
    let cpm: Double
    let createdAt: Date
    let taskMode: VoiceTaskMode?
    let taskStatus: VoiceTaskStatus?
}

struct HomeHistoryPage: Equatable {
    let records: [HomeHistoryRecord]
    let totalCount: Int
}

struct HomeHistoryActivityDay: Equatable {
    let date: Date
    let characters: Int
}

struct HomeDashboardAggregate: Equatable {
    let totalCharacters: Int
    let totalDurationMS: Int
    let focusedCharacters: Int
    let activityDays: [HomeHistoryActivityDay]
}

protocol HomeHistoryQuerying {
    func page(query: HomeHistoryQuery) throws -> HomeHistoryPage
    func dashboardAggregate(
        statsStartDate: Date?,
        statsEndDate: Date?,
        focusStartDate: Date,
        focusEndDate: Date,
        activityStartDate: Date,
        activityEndDate: Date,
        activityTimeZoneOffsetSeconds: Int
    ) throws -> HomeDashboardAggregate
    func clearAll(deletedAt: Date) throws
}

final class HomeHistoryRepository: HomeHistoryQuerying {
    private let databaseQueue: DatabaseQueue
    private let formatter = ISO8601DateFormatter()

    init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    func page(query: HomeHistoryQuery) throws -> HomeHistoryPage {
        AppLogger.database.debug(
            "查询历史分页：limit=\(query.limit), offset=\(query.offset), searchLen=\(query.searchText.count)"
        )
        return try databaseQueue.read { connection in
            let filter = filterSQL(for: query)
            let countStatement = try connection.prepare(
                "\(Self.combinedSQL) SELECT COUNT(*) FROM combined \(filter)"
            )
            try bindFilters(query, to: countStatement)
            _ = try countStatement.step()
            let totalCount = countStatement.columnInt(at: 0)

            let pageStatement = try connection.prepare(
                """
                \(Self.combinedSQL)
                SELECT id, raw_text, final_text, app_bundle_id, app_name,
                       char_count, cpm, created_at, task_mode, task_status
                FROM combined
                \(filter)
                ORDER BY created_at DESC, source_rank ASC, id ASC
                LIMIT ? OFFSET ?
                """
            )
            let nextIndex = try bindFilters(query, to: pageStatement)
            try pageStatement.bind(max(1, query.limit), at: nextIndex)
            try pageStatement.bind(max(0, query.offset), at: nextIndex + 1)

            var records: [HomeHistoryRecord] = []
            while try pageStatement.step() {
                records.append(try record(from: pageStatement))
            }
            let page = HomeHistoryPage(records: records, totalCount: totalCount)
            AppLogger.database.debug("历史分页返回：count=\(records.count), total=\(totalCount)")
            return page
        }
    }

    func dashboardAggregate(
        statsStartDate: Date? = nil,
        statsEndDate: Date? = nil,
        focusStartDate: Date,
        focusEndDate: Date,
        activityStartDate: Date,
        activityEndDate: Date,
        activityTimeZoneOffsetSeconds: Int = 0
    ) throws -> HomeDashboardAggregate {
        AppLogger.database.debug("查询历史聚合")
        return try databaseQueue.read { connection in
            var statsConditions = ["deleted_at IS NULL"]
            if statsStartDate != nil { statsConditions.append("created_at >= ?") }
            if statsEndDate != nil { statsConditions.append("created_at < ?") }
            let stats = try connection.prepare(
                """
                SELECT
                    COALESCE(SUM(CASE WHEN duration_ms >= 300 AND char_count > 0 THEN char_count ELSE 0 END), 0),
                    COALESCE(SUM(CASE WHEN duration_ms >= 300 AND char_count > 0 THEN duration_ms ELSE 0 END), 0)
                FROM dictation_history
                WHERE \(statsConditions.joined(separator: " AND "))
                """
            )
            var statsIndex: Int32 = 1
            if let statsStartDate {
                try stats.bind(formatter.string(from: statsStartDate), at: statsIndex)
                statsIndex += 1
            }
            if let statsEndDate {
                try stats.bind(formatter.string(from: statsEndDate), at: statsIndex)
            }
            _ = try stats.step()

            let focus = try connection.prepare(
                """
                SELECT COALESCE(SUM(char_count), 0)
                FROM dictation_history
                WHERE deleted_at IS NULL AND created_at >= ? AND created_at < ?
                """
            )
            try focus.bind(formatter.string(from: focusStartDate), at: 1)
            try focus.bind(formatter.string(from: focusEndDate), at: 2)
            _ = try focus.step()

            let activity = try connection.prepare(
                """
                SELECT strftime(
                           '%Y-%m-%dT00:00:00Z',
                           created_at,
                           printf('%+d seconds', ?)
                       ) AS day,
                       COALESCE(SUM(MAX(char_count, 0)), 0)
                FROM dictation_history
                WHERE deleted_at IS NULL AND created_at >= ? AND created_at < ?
                GROUP BY day
                ORDER BY day ASC
                """
            )
            try activity.bind(activityTimeZoneOffsetSeconds, at: 1)
            try activity.bind(formatter.string(from: activityStartDate), at: 2)
            try activity.bind(formatter.string(from: activityEndDate), at: 3)
            var activityDays: [HomeHistoryActivityDay] = []
            while try activity.step() {
                guard let dayText = activity.columnString(at: 0),
                      let localDayLabel = formatter.date(from: dayText) else {
                    throw SQLiteError.stepFailed("Invalid dashboard activity day.")
                }
                let day = localDayLabel.addingTimeInterval(
                    TimeInterval(-activityTimeZoneOffsetSeconds)
                )
                activityDays.append(
                    HomeHistoryActivityDay(date: day, characters: activity.columnInt(at: 1))
                )
            }

            let aggregate = HomeDashboardAggregate(
                totalCharacters: stats.columnInt(at: 0),
                totalDurationMS: stats.columnInt(at: 1),
                focusedCharacters: focus.columnInt(at: 0),
                activityDays: activityDays
            )
            AppLogger.database.debug(
                "历史聚合返回：totalChars=\(aggregate.totalCharacters), totalDurationMS=\(aggregate.totalDurationMS), focusedChars=\(aggregate.focusedCharacters), activityDays=\(aggregate.activityDays.count)"
            )
            return aggregate
        }
    }

    func clearAll(deletedAt: Date) throws {
        AppLogger.database.warning("清空历史记录：deletedAt=\(formatter.string(from: deletedAt))")
        try databaseQueue.write { connection in
            try connection.execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                let timestamp = formatter.string(from: deletedAt)
                let history = try connection.prepare(
                    """
                    UPDATE dictation_history
                    SET deleted_at = ?, updated_at = ?
                    WHERE deleted_at IS NULL
                    """
                )
                try history.bind(timestamp, at: 1)
                try history.bind(timestamp, at: 2)
                _ = try history.step()
                try connection.execute(
                    """
                    DELETE FROM voice_tasks
                    WHERE mode IN ('agentCompose', 'agentDispatch')
                      AND status != 'inProgress'
                    """
                )
                try connection.execute("COMMIT")
                AppLogger.database.info("历史记录清理已提交")
            } catch {
                AppLogger.database.warning("清空历史记录失败，准备回滚：\(error.localizedDescription)")
                try? connection.execute("ROLLBACK")
                throw error
            }
        }
    }

    private func filterSQL(for query: HomeHistoryQuery) -> String {
        var conditions: [String] = []
        if !query.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            conditions.append("(raw_text LIKE ? COLLATE NOCASE OR final_text LIKE ? COLLATE NOCASE OR app_name LIKE ? COLLATE NOCASE)")
        }
        if query.startDate != nil {
            conditions.append("created_at >= ?")
        }
        if query.endDate != nil {
            conditions.append("created_at < ?")
        }
        return conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
    }

    @discardableResult
    private func bindFilters(_ query: HomeHistoryQuery, to statement: SQLiteStatement) throws -> Int32 {
        var index: Int32 = 1
        let searchText = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !searchText.isEmpty {
            let pattern = "%\(searchText)%"
            for _ in 0..<3 {
                try statement.bind(pattern, at: index)
                index += 1
            }
        }
        if let startDate = query.startDate {
            try statement.bind(formatter.string(from: startDate), at: index)
            index += 1
        }
        if let endDate = query.endDate {
            try statement.bind(formatter.string(from: endDate), at: index)
            index += 1
        }
        return index
    }

    private func record(from statement: SQLiteStatement) throws -> HomeHistoryRecord {
        guard let id = statement.columnString(at: 0),
              let rawText = statement.columnString(at: 1),
              let finalText = statement.columnString(at: 2),
              let createdAtText = statement.columnString(at: 7),
              let createdAt = formatter.date(from: createdAtText) else {
            throw SQLiteError.stepFailed("Invalid combined home history row.")
        }
        return HomeHistoryRecord(
            id: id,
            rawText: rawText,
            finalText: finalText,
            appBundleID: statement.columnString(at: 3),
            appName: statement.columnString(at: 4),
            charCount: statement.columnInt(at: 5),
            cpm: statement.columnDouble(at: 6),
            createdAt: createdAt,
            taskMode: statement.columnString(at: 8).flatMap(VoiceTaskMode.init(rawValue:)),
            taskStatus: statement.columnString(at: 9).flatMap(VoiceTaskStatus.init(rawValue:))
        )
    }

    private static let combinedSQL = """
    WITH combined AS (
        SELECT 0 AS source_rank,
               id,
               raw_text,
               final_text,
               target_app_bundle_id AS app_bundle_id,
               target_app_name AS app_name,
               char_count,
               cpm,
               created_at,
               NULL AS task_mode,
               NULL AS task_status
        FROM dictation_history
        WHERE deleted_at IS NULL
        UNION ALL
        SELECT 1 AS source_rank,
               id,
               COALESCE(raw_transcript, '') AS raw_text,
               COALESCE(final_text, raw_transcript, '') AS final_text,
               target_app_bundle_id AS app_bundle_id,
               target_app_name AS app_name,
               length(COALESCE(final_text, raw_transcript, '')) AS char_count,
               0.0 AS cpm,
               created_at,
               mode AS task_mode,
               status AS task_status
        FROM voice_tasks
        WHERE mode IN ('agentCompose', 'agentDispatch')
          AND status != 'inProgress'
    )
    """
}
