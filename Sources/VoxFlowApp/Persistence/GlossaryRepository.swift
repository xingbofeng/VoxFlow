import Foundation

struct GlossaryTerm: Equatable {
    let id: String
    let term: String
    let aliases: [String]
    let category: String
    let enabled: Bool
    let priority: Int
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
}

protocol GlossaryRepository {
    func save(_ term: GlossaryTerm) throws
    func list(category: String?) throws -> [GlossaryTerm]
    func search(_ query: String) throws -> [GlossaryTerm]
    func delete(id: String) throws
}

final class SQLiteGlossaryRepository: GlossaryRepository {
    private let databaseQueue: DatabaseQueue
    private let formatter = ISO8601DateFormatter()

    init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    func save(_ term: GlossaryTerm) throws {
        let aliasesJSON = try String(
            data: JSONEncoder().encode(term.aliases),
            encoding: .utf8
        ) ?? "[]"

        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                INSERT INTO glossary_terms (
                    id, term, aliases_json, category, enabled, priority,
                    notes, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    term = excluded.term,
                    aliases_json = excluded.aliases_json,
                    category = excluded.category,
                    enabled = excluded.enabled,
                    priority = excluded.priority,
                    notes = excluded.notes,
                    updated_at = excluded.updated_at
                """
            )
            try statement.bind(term.id, at: 1)
            try statement.bind(term.term, at: 2)
            try statement.bind(aliasesJSON, at: 3)
            try statement.bind(term.category, at: 4)
            try statement.bind(term.enabled ? 1 : 0, at: 5)
            try statement.bind(term.priority, at: 6)
            try statement.bind(term.notes, at: 7)
            try statement.bind(formatter.string(from: term.createdAt), at: 8)
            try statement.bind(formatter.string(from: term.updatedAt), at: 9)
            _ = try statement.step()
        }
    }

    func list(category: String?) throws -> [GlossaryTerm] {
        if let category {
            return try query(
                """
                SELECT id, term, aliases_json, category, enabled, priority,
                       notes, created_at, updated_at
                FROM glossary_terms
                WHERE category = ?
                ORDER BY priority ASC, lower(term) ASC
                """,
                bindings: { statement in
                    try statement.bind(category, at: 1)
                }
            )
        }

        return try query(
            """
            SELECT id, term, aliases_json, category, enabled, priority,
                   notes, created_at, updated_at
            FROM glossary_terms
            ORDER BY priority ASC, lower(term) ASC
            """,
            bindings: { _ in }
        )
    }

    func search(_ queryText: String) throws -> [GlossaryTerm] {
        try query(
            """
            SELECT id, term, aliases_json, category, enabled, priority,
                   notes, created_at, updated_at
            FROM glossary_terms
            WHERE term LIKE ? OR aliases_json LIKE ?
            ORDER BY priority ASC, lower(term) ASC
            """,
            bindings: { statement in
                let pattern = "%\(queryText)%"
                try statement.bind(pattern, at: 1)
                try statement.bind(pattern, at: 2)
            }
        )
    }

    func delete(id: String) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare("DELETE FROM glossary_terms WHERE id = ?")
            try statement.bind(id, at: 1)
            _ = try statement.step()
        }
    }

    private func query(
        _ sql: String,
        bindings: (SQLiteStatement) throws -> Void
    ) throws -> [GlossaryTerm] {
        try databaseQueue.read { connection in
            let statement = try connection.prepare(sql)
            try bindings(statement)
            var terms: [GlossaryTerm] = []
            while try statement.step() {
                terms.append(try row(from: statement))
            }
            return terms
        }
    }

    private func row(from statement: SQLiteStatement) throws -> GlossaryTerm {
        guard let id = statement.columnString(at: 0),
              let term = statement.columnString(at: 1),
              let aliasesJSON = statement.columnString(at: 2),
              let category = statement.columnString(at: 3),
              let createdAtText = statement.columnString(at: 7),
              let updatedAtText = statement.columnString(at: 8),
              let createdAt = formatter.date(from: createdAtText),
              let updatedAt = formatter.date(from: updatedAtText) else {
            throw SQLiteError.stepFailed("Invalid glossary_terms row.")
        }

        let aliases = (try? JSONDecoder().decode([String].self, from: Data(aliasesJSON.utf8))) ?? []
        return GlossaryTerm(
            id: id,
            term: term,
            aliases: aliases,
            category: category,
            enabled: statement.columnInt(at: 4) != 0,
            priority: statement.columnInt(at: 5),
            notes: statement.columnString(at: 6),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
