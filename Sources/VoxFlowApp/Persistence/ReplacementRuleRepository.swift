import Foundation

enum ReplacementMatchMode: String, CaseIterable, Hashable {
    case exact
    case contains
    case regex
}

enum ReplacementApplyStage: String, CaseIterable, Hashable {
    case beforeLLM
    case afterLLM
}

struct ReplacementRule: Equatable {
    let id: String
    let source: String
    let target: String
    let matchMode: ReplacementMatchMode
    let applyStage: ReplacementApplyStage
    let category: String
    let enabled: Bool
    let priority: Int
    let createdAt: Date
    let updatedAt: Date
}

protocol ReplacementRuleRepository {
    func save(_ rule: ReplacementRule) throws
    func list(category: String?) throws -> [ReplacementRule]
    func search(_ query: String) throws -> [ReplacementRule]
    func listEnabled(stage: ReplacementApplyStage) throws -> [ReplacementRule]
    func delete(id: String) throws
}

final class SQLiteReplacementRuleRepository: ReplacementRuleRepository {
    private let databaseQueue: DatabaseQueue
    private let formatter = ISO8601DateFormatter()

    init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    func save(_ rule: ReplacementRule) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                INSERT INTO replacement_rules (
                    id, source, target, match_mode, apply_stage, category,
                    enabled, priority, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    source = excluded.source,
                    target = excluded.target,
                    match_mode = excluded.match_mode,
                    apply_stage = excluded.apply_stage,
                    category = excluded.category,
                    enabled = excluded.enabled,
                    priority = excluded.priority,
                    updated_at = excluded.updated_at
                """
            )
            try statement.bind(rule.id, at: 1)
            try statement.bind(rule.source, at: 2)
            try statement.bind(rule.target, at: 3)
            try statement.bind(rule.matchMode.rawValue, at: 4)
            try statement.bind(rule.applyStage.rawValue, at: 5)
            try statement.bind(rule.category, at: 6)
            try statement.bind(rule.enabled ? 1 : 0, at: 7)
            try statement.bind(rule.priority, at: 8)
            try statement.bind(formatter.string(from: rule.createdAt), at: 9)
            try statement.bind(formatter.string(from: rule.updatedAt), at: 10)
            _ = try statement.step()
        }
    }

    func list(category: String?) throws -> [ReplacementRule] {
        if let category {
            return try query(
                """
                SELECT id, source, target, match_mode, apply_stage, category,
                       enabled, priority, created_at, updated_at
                FROM replacement_rules
                WHERE category = ?
                ORDER BY priority ASC, source ASC
                """,
                bindings: { statement in
                    try statement.bind(category, at: 1)
                }
            )
        }

        return try query(
            """
            SELECT id, source, target, match_mode, apply_stage, category,
                   enabled, priority, created_at, updated_at
            FROM replacement_rules
            ORDER BY priority ASC, source ASC
            """,
            bindings: { _ in }
        )
    }

    func search(_ queryText: String) throws -> [ReplacementRule] {
        try query(
            """
            SELECT id, source, target, match_mode, apply_stage, category,
                   enabled, priority, created_at, updated_at
            FROM replacement_rules
            WHERE source LIKE ? OR target LIKE ?
            ORDER BY priority ASC, source ASC
            """,
            bindings: { statement in
                let pattern = "%\(queryText)%"
                try statement.bind(pattern, at: 1)
                try statement.bind(pattern, at: 2)
            }
        )
    }

    func listEnabled(stage: ReplacementApplyStage) throws -> [ReplacementRule] {
        try query(
            """
            SELECT id, source, target, match_mode, apply_stage, category,
                   enabled, priority, created_at, updated_at
            FROM replacement_rules
            WHERE enabled = 1 AND apply_stage = ?
            ORDER BY priority ASC, source ASC
            """,
            bindings: { statement in
                try statement.bind(stage.rawValue, at: 1)
            }
        )
    }

    func delete(id: String) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare("DELETE FROM replacement_rules WHERE id = ?")
            try statement.bind(id, at: 1)
            _ = try statement.step()
        }
    }

    private func row(from statement: SQLiteStatement) throws -> ReplacementRule {
        guard let id = statement.columnString(at: 0),
              let source = statement.columnString(at: 1),
              let target = statement.columnString(at: 2),
              let matchModeRaw = statement.columnString(at: 3),
              let matchMode = ReplacementMatchMode(rawValue: matchModeRaw),
              let applyStageRaw = statement.columnString(at: 4),
              let applyStage = ReplacementApplyStage(rawValue: applyStageRaw),
              let category = statement.columnString(at: 5),
              let createdAtText = statement.columnString(at: 8),
              let updatedAtText = statement.columnString(at: 9),
              let createdAt = formatter.date(from: createdAtText),
              let updatedAt = formatter.date(from: updatedAtText) else {
            throw SQLiteError.stepFailed("Invalid replacement_rules row.")
        }

        return ReplacementRule(
            id: id,
            source: source,
            target: target,
            matchMode: matchMode,
            applyStage: applyStage,
            category: category,
            enabled: statement.columnInt(at: 6) != 0,
            priority: statement.columnInt(at: 7),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func query(
        _ sql: String,
        bindings: (SQLiteStatement) throws -> Void
    ) throws -> [ReplacementRule] {
        try databaseQueue.read { connection in
            let statement = try connection.prepare(sql)
            try bindings(statement)
            var rules: [ReplacementRule] = []
            while try statement.step() {
                rules.append(try row(from: statement))
            }
            return rules
        }
    }
}
