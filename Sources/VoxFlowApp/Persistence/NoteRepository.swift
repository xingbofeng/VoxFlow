import Foundation

struct NoteRecord: Equatable {
    let id: String
    let title: String
    let bodyMarkdown: String
    let sourceType: String
    let sourceID: String?
    let tags: [String]
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}

protocol NoteRepository {
    func save(_ note: NoteRecord) throws
    func note(id: String) throws -> NoteRecord?
    func list() throws -> [NoteRecord]
    func search(_ query: String) throws -> [NoteRecord]
    func softDelete(id: String, deletedAt: Date) throws
}

final class SQLiteNoteRepository: NoteRepository {
    private let databaseQueue: DatabaseQueue
    private let formatter = ISO8601DateFormatter()

    init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    func save(_ note: NoteRecord) throws {
        AppLogger.database.debug("保存笔记：id=\(note.id), titleLen=\(note.title.count)")
        let tagsJSON = try String(data: JSONEncoder().encode(note.tags), encoding: .utf8) ?? "[]"
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                INSERT INTO notes (
                    id, title, body_markdown, source_type, source_id, tags_json,
                    created_at, updated_at, deleted_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    body_markdown = excluded.body_markdown,
                    source_type = excluded.source_type,
                    source_id = excluded.source_id,
                    tags_json = excluded.tags_json,
                    updated_at = excluded.updated_at,
                    deleted_at = excluded.deleted_at
                """
            )
            try statement.bind(note.id, at: 1)
            try statement.bind(note.title, at: 2)
            try statement.bind(note.bodyMarkdown, at: 3)
            try statement.bind(note.sourceType, at: 4)
            try statement.bind(note.sourceID, at: 5)
            try statement.bind(tagsJSON, at: 6)
            try statement.bind(formatter.string(from: note.createdAt), at: 7)
            try statement.bind(formatter.string(from: note.updatedAt), at: 8)
            try statement.bind(note.deletedAt.map(formatter.string(from:)), at: 9)
            _ = try statement.step()
        }
        AppLogger.database.info("笔记已保存：id=\(note.id)")
    }

    func note(id: String) throws -> NoteRecord? {
        AppLogger.database.debug("查询笔记：id=\(id)")
        return try databaseQueue.read { connection in
            let statement = try connection.prepare(
                """
                SELECT id, title, body_markdown, source_type, source_id,
                       tags_json, created_at, updated_at, deleted_at
                FROM notes
                WHERE id = ?
                """
            )
            try statement.bind(id, at: 1)
            guard try statement.step() else {
                AppLogger.database.warning("笔记不存在：id=\(id)")
                return nil
            }
            return try row(from: statement)
        }
    }

    func list() throws -> [NoteRecord] {
        AppLogger.database.debug("列出全部笔记")
        return try query(
            """
            SELECT id, title, body_markdown, source_type, source_id,
                   tags_json, created_at, updated_at, deleted_at
                FROM notes
                WHERE deleted_at IS NULL
                ORDER BY updated_at DESC
            """,
            bindings: { _ in }
        )
    }

    func search(_ queryText: String) throws -> [NoteRecord] {
        AppLogger.database.debug("搜索笔记：queryLen=\(queryText.count)")
        return try query(
            """
            SELECT id, title, body_markdown, source_type, source_id,
                   tags_json, created_at, updated_at, deleted_at
            FROM notes
            WHERE deleted_at IS NULL
              AND (title LIKE ? OR body_markdown LIKE ? OR tags_json LIKE ?)
            ORDER BY updated_at DESC
            """,
            bindings: { statement in
                let pattern = "%\(queryText)%"
                try statement.bind(pattern, at: 1)
                try statement.bind(pattern, at: 2)
                try statement.bind(pattern, at: 3)
            }
        )
    }

    func softDelete(id: String, deletedAt: Date) throws {
        AppLogger.database.warning("软删笔记：id=\(id)")
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                "UPDATE notes SET deleted_at = ?, updated_at = ? WHERE id = ?"
            )
            let timestamp = formatter.string(from: deletedAt)
            try statement.bind(timestamp, at: 1)
            try statement.bind(timestamp, at: 2)
            try statement.bind(id, at: 3)
            _ = try statement.step()
        }
        AppLogger.database.info("笔记软删除完成：id=\(id)")
    }

    private func query(
        _ sql: String,
        bindings: (SQLiteStatement) throws -> Void
    ) throws -> [NoteRecord] {
        return try databaseQueue.read { connection in
            let statement = try connection.prepare(sql)
            try bindings(statement)
            var notes: [NoteRecord] = []
            while try statement.step() {
                notes.append(try row(from: statement))
            }
            return notes
        }
    }

    private func row(from statement: SQLiteStatement) throws -> NoteRecord {
        guard let id = statement.columnString(at: 0),
              let title = statement.columnString(at: 1),
              let bodyMarkdown = statement.columnString(at: 2),
              let sourceType = statement.columnString(at: 3),
              let tagsJSON = statement.columnString(at: 5),
              let createdAtText = statement.columnString(at: 6),
              let updatedAtText = statement.columnString(at: 7),
              let createdAt = formatter.date(from: createdAtText),
              let updatedAt = formatter.date(from: updatedAtText) else {
            throw SQLiteError.stepFailed("Invalid notes row.")
        }

        let tags = (try? JSONDecoder().decode([String].self, from: Data(tagsJSON.utf8))) ?? []
        let deletedAt = statement.columnString(at: 8).flatMap(formatter.date(from:))
        return NoteRecord(
            id: id,
            title: title,
            bodyMarkdown: bodyMarkdown,
            sourceType: sourceType,
            sourceID: statement.columnString(at: 4),
            tags: tags,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}
