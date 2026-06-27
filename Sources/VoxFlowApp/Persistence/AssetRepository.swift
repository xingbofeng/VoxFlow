import Foundation

protocol AssetRepository {
    func save(_ item: AssetItem) throws
    func asset(id: String) throws -> AssetItem?
    func page(query: AssetQuery) throws -> AssetPage
    func softDelete(id: String, deletedAt: Date) throws
    func softDelete(ids: [String], deletedAt: Date) throws
    func clearAll(deletedAt: Date) throws
}

extension AssetRepository {
    func softDelete(ids: [String], deletedAt: Date) throws {
        for id in ids {
            try softDelete(id: id, deletedAt: deletedAt)
        }
    }

    func clearAll(deletedAt: Date) throws {
        while true {
            let page = try page(query: AssetQuery(limit: 500, offset: 0))
            guard !page.items.isEmpty else { break }
            try softDelete(ids: page.items.map(\.id), deletedAt: deletedAt)
        }
    }
}

final class SQLiteAssetRepository: AssetRepository {
    private let databaseQueue: DatabaseQueue
    private let formatter = ISO8601DateFormatter()

    init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    func save(_ item: AssetItem) throws {
        try item.validate()
        AppLogger.database.debug(
            "保存资产：id=\(item.id), source=\(item.source.rawValue), type=\(item.contentType.rawValue)"
        )
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                INSERT INTO asset_items (
                    id, source, content_type, title, preview_text, text, raw_text,
                    image_path, file_path, url, color_value, source_app_name,
                    source_app_bundle_id, content_hash, capture_reason, metadata_json,
                    created_at, updated_at, deleted_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    source = excluded.source,
                    content_type = excluded.content_type,
                    title = excluded.title,
                    preview_text = excluded.preview_text,
                    text = excluded.text,
                    raw_text = excluded.raw_text,
                    image_path = excluded.image_path,
                    file_path = excluded.file_path,
                    url = excluded.url,
                    color_value = excluded.color_value,
                    source_app_name = excluded.source_app_name,
                    source_app_bundle_id = excluded.source_app_bundle_id,
                    content_hash = excluded.content_hash,
                    capture_reason = excluded.capture_reason,
                    metadata_json = excluded.metadata_json,
                    created_at = excluded.created_at,
                    updated_at = excluded.updated_at,
                    deleted_at = excluded.deleted_at
                """
            )
            try bind(item, to: statement)
            _ = try statement.step()
        }
    }

    func asset(id: String) throws -> AssetItem? {
        try databaseQueue.read { connection in
            let statement = try connection.prepare(
                """
                SELECT \(Self.selectedColumns)
                FROM asset_items
                WHERE id = ? AND deleted_at IS NULL
                """
            )
            try statement.bind(id, at: 1)
            guard try statement.step() else {
                return nil
            }
            return try item(from: statement)
        }
    }

    func page(query: AssetQuery) throws -> AssetPage {
        AppLogger.database.debug(
            "查询资产分页：limit=\(query.limit), offset=\(query.offset), searchLen=\(query.searchText.count)"
        )
        return try databaseQueue.read { connection in
            let searchText = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if shouldUseFTS(for: searchText) {
                return try ftsPage(query: query, searchText: searchText, connection: connection)
            }
            return try likePage(query: query, connection: connection)
        }
    }

    private func likePage(query: AssetQuery, connection: SQLiteConnection) throws -> AssetPage {
        let filter = filterSQL(for: query)
        let countStatement = try connection.prepare(
            "SELECT COUNT(*) FROM asset_items \(filter)"
        )
        try bindFilters(query, to: countStatement)
        _ = try countStatement.step()
        let totalCount = countStatement.columnInt(at: 0)

        let pageStatement = try connection.prepare(
            """
            SELECT \(Self.selectedColumns)
            FROM asset_items
            \(filter)
            ORDER BY created_at DESC, id ASC
            LIMIT ? OFFSET ?
            """
        )
        let nextIndex = try bindFilters(query, to: pageStatement)
        try pageStatement.bind(max(1, query.limit), at: nextIndex)
        try pageStatement.bind(max(0, query.offset), at: nextIndex + 1)

        var items: [AssetItem] = []
        while try pageStatement.step() {
            items.append(try item(from: pageStatement))
        }
        return AssetPage(items: items, totalCount: totalCount)
    }

    private func ftsPage(
        query: AssetQuery,
        searchText: String,
        connection: SQLiteConnection
    ) throws -> AssetPage {
        let filter = filterSQL(for: query, includesSearch: false, tableName: "asset_items")
        let matchExpression = ftsMatchExpression(for: searchText)
        let countStatement = try connection.prepare(
            """
            SELECT COUNT(*)
            FROM asset_items_fts
            JOIN asset_items ON asset_items.rowid = asset_items_fts.rowid
            \(filter) AND asset_items_fts MATCH ?
            """
        )
        var nextIndex = try bindFilters(query, to: countStatement, includesSearch: false)
        try countStatement.bind(matchExpression, at: nextIndex)
        _ = try countStatement.step()
        let totalCount = countStatement.columnInt(at: 0)

        let pageStatement = try connection.prepare(
            """
            SELECT \(Self.selectedColumns(tableName: "asset_items"))
            FROM asset_items_fts
            JOIN asset_items ON asset_items.rowid = asset_items_fts.rowid
            \(filter) AND asset_items_fts MATCH ?
            ORDER BY bm25(asset_items_fts), asset_items.created_at DESC, asset_items.id ASC
            LIMIT ? OFFSET ?
            """
        )
        nextIndex = try bindFilters(query, to: pageStatement, includesSearch: false)
        try pageStatement.bind(matchExpression, at: nextIndex)
        try pageStatement.bind(max(1, query.limit), at: nextIndex + 1)
        try pageStatement.bind(max(0, query.offset), at: nextIndex + 2)

        var items: [AssetItem] = []
        while try pageStatement.step() {
            items.append(try item(from: pageStatement))
        }
        return AssetPage(items: items, totalCount: totalCount)
    }

    private func shouldUseFTS(for searchText: String) -> Bool {
        searchText.count >= 3
    }

    private func ftsMatchExpression(for searchText: String) -> String {
        "\"\(searchText.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    func softDelete(id: String, deletedAt: Date) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                "UPDATE asset_items SET deleted_at = ?, updated_at = ? WHERE id = ?"
            )
            let timestamp = formatter.string(from: deletedAt)
            try statement.bind(timestamp, at: 1)
            try statement.bind(timestamp, at: 2)
            try statement.bind(id, at: 3)
            _ = try statement.step()
        }
    }

    func softDelete(ids: [String], deletedAt: Date) throws {
        let ids = ids.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !ids.isEmpty else { return }
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                UPDATE asset_items
                SET deleted_at = ?, updated_at = ?
                WHERE id IN (\(placeholders(count: ids.count)))
                """
            )
            let timestamp = formatter.string(from: deletedAt)
            try statement.bind(timestamp, at: 1)
            try statement.bind(timestamp, at: 2)
            for (offset, id) in ids.enumerated() {
                try statement.bind(id, at: Int32(offset + 3))
            }
            _ = try statement.step()
        }
    }

    func clearAll(deletedAt: Date) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                "UPDATE asset_items SET deleted_at = ?, updated_at = ? WHERE deleted_at IS NULL"
            )
            let timestamp = formatter.string(from: deletedAt)
            try statement.bind(timestamp, at: 1)
            try statement.bind(timestamp, at: 2)
            _ = try statement.step()
        }
    }

    private func bind(_ item: AssetItem, to statement: SQLiteStatement) throws {
        try statement.bind(item.id, at: 1)
        try statement.bind(item.source.rawValue, at: 2)
        try statement.bind(item.contentType.rawValue, at: 3)
        try statement.bind(item.title, at: 4)
        try statement.bind(item.previewText, at: 5)
        try statement.bind(item.text, at: 6)
        try statement.bind(item.rawText, at: 7)
        try statement.bind(item.imagePath, at: 8)
        try statement.bind(item.filePath, at: 9)
        try statement.bind(item.url, at: 10)
        try statement.bind(item.colorValue, at: 11)
        try statement.bind(item.sourceAppName, at: 12)
        try statement.bind(item.sourceAppBundleID, at: 13)
        try statement.bind(item.contentHash, at: 14)
        try statement.bind(item.captureReason.rawValue, at: 15)
        try statement.bind(item.metadataJSON, at: 16)
        try statement.bind(formatter.string(from: item.createdAt), at: 17)
        try statement.bind(formatter.string(from: item.updatedAt), at: 18)
        try statement.bind(item.deletedAt.map(formatter.string(from:)), at: 19)
    }

    private func filterSQL(
        for query: AssetQuery,
        includesSearch: Bool = true,
        tableName: String? = nil
    ) -> String {
        var conditions = ["\(column("deleted_at", tableName: tableName)) IS NULL"]
        if includesSearch && !query.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            conditions.append(
                """
                (\(column("title", tableName: tableName)) LIKE ? COLLATE NOCASE
                 OR \(column("preview_text", tableName: tableName)) LIKE ? COLLATE NOCASE
                 OR \(column("text", tableName: tableName)) LIKE ? COLLATE NOCASE
                 OR \(column("source_app_name", tableName: tableName)) LIKE ? COLLATE NOCASE
                 OR \(column("url", tableName: tableName)) LIKE ? COLLATE NOCASE
                 OR \(column("file_path", tableName: tableName)) LIKE ? COLLATE NOCASE
                 OR \(column("color_value", tableName: tableName)) LIKE ? COLLATE NOCASE)
                """
            )
        }
        if !query.sources.isEmpty {
            conditions.append("\(column("source", tableName: tableName)) IN (\(placeholders(count: query.sources.count)))")
        }
        if !query.contentTypes.isEmpty {
            conditions.append("\(column("content_type", tableName: tableName)) IN (\(placeholders(count: query.contentTypes.count)))")
        }
        if query.startDate != nil {
            conditions.append("\(column("created_at", tableName: tableName)) >= ?")
        }
        if query.endDate != nil {
            conditions.append("\(column("created_at", tableName: tableName)) < ?")
        }
        return "WHERE " + conditions.joined(separator: " AND ")
    }

    @discardableResult
    private func bindFilters(
        _ query: AssetQuery,
        to statement: SQLiteStatement,
        includesSearch: Bool = true
    ) throws -> Int32 {
        var index: Int32 = 1
        let searchText = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if includesSearch && !searchText.isEmpty {
            let pattern = "%\(searchText)%"
            for _ in 0..<7 {
                try statement.bind(pattern, at: index)
                index += 1
            }
        }
        for source in query.sources.sorted(by: { $0.rawValue < $1.rawValue }) {
            try statement.bind(source.rawValue, at: index)
            index += 1
        }
        for contentType in query.contentTypes.sorted(by: { $0.rawValue < $1.rawValue }) {
            try statement.bind(contentType.rawValue, at: index)
            index += 1
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

    private func column(_ name: String, tableName: String?) -> String {
        guard let tableName else { return name }
        return "\(tableName).\(name)"
    }

    private func item(from statement: SQLiteStatement) throws -> AssetItem {
        guard let id = statement.columnString(at: 0),
              let sourceRaw = statement.columnString(at: 1),
              let source = AssetSource(rawValue: sourceRaw),
              let contentTypeRaw = statement.columnString(at: 2),
              let contentType = AssetContentType(rawValue: contentTypeRaw),
              let title = statement.columnString(at: 3),
              let contentHash = statement.columnString(at: 13),
              let captureReasonRaw = statement.columnString(at: 14),
              let captureReason = AssetCaptureReason(rawValue: captureReasonRaw),
              let createdAtText = statement.columnString(at: 16),
              let createdAt = formatter.date(from: createdAtText),
              let updatedAtText = statement.columnString(at: 17),
              let updatedAt = formatter.date(from: updatedAtText) else {
            throw SQLiteError.stepFailed("Invalid asset_items row.")
        }
        return AssetItem(
            id: id,
            source: source,
            contentType: contentType,
            title: title,
            previewText: statement.columnString(at: 4),
            text: statement.columnString(at: 5),
            rawText: statement.columnString(at: 6),
            imagePath: statement.columnString(at: 7),
            filePath: statement.columnString(at: 8),
            url: statement.columnString(at: 9),
            colorValue: statement.columnString(at: 10),
            sourceAppName: statement.columnString(at: 11),
            sourceAppBundleID: statement.columnString(at: 12),
            contentHash: contentHash,
            captureReason: captureReason,
            metadataJSON: statement.columnString(at: 15),
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: statement.columnString(at: 18).flatMap(formatter.date(from:))
        )
    }

    private func placeholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private static var selectedColumns: String {
        selectedColumns()
    }

    private static func selectedColumns(tableName: String? = nil) -> String {
        selectedColumnNames
            .map { column in
                guard let tableName else { return column }
                return "\(tableName).\(column)"
            }
            .joined(separator: ", ")
    }

    private static let selectedColumnNames = [
        "id", "source", "content_type", "title", "preview_text", "text", "raw_text",
        "image_path", "file_path", "url", "color_value", "source_app_name",
        "source_app_bundle_id", "content_hash", "capture_reason", "metadata_json",
        "created_at", "updated_at", "deleted_at",
    ]
}
