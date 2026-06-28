import Foundation

struct StyleProfileRecord: Equatable {
    let id: String
    let name: String
    let category: String
    let subtitle: String?
    let mode: String
    let prompt: String
    let sampleInput: String?
    let sampleOutput: String?
    let llmProviderID: String?
    let model: String?
    let temperature: Double
    let enabled: Bool
    let builtIn: Bool
    let isDefault: Bool
    let createdAt: Date
    let updatedAt: Date
}

protocol StyleRepository {
    func save(_ profile: StyleProfileRecord) throws
    func profile(id: String) throws -> StyleProfileRecord?
    func list(category: String?) throws -> [StyleProfileRecord]
    func defaultProfile() throws -> StyleProfileRecord?
}

final class SQLiteStyleRepository: StyleRepository {
    private let databaseQueue: DatabaseQueue
    private let formatter = ISO8601DateFormatter()
    /// 兼容历史上写入带毫秒的 ISO8601 时间戳的脏数据；只在读取路径作为 fallback 使用。
    private let legacyFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    func save(_ profile: StyleProfileRecord) throws {
        AppLogger.database.debug("保存样式：id=\(profile.id), default=\(profile.isDefault)")
        try databaseQueue.write { connection in
            if profile.isDefault {
                try connection.execute("UPDATE style_profiles SET is_default = 0")
            }
            let statement = try connection.prepare(
                """
                INSERT INTO style_profiles (
                    id, name, category, subtitle, mode, prompt, sample_input,
                    sample_output, llm_provider_id, model, temperature, enabled,
                    built_in, is_default, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    category = excluded.category,
                    subtitle = excluded.subtitle,
                    mode = excluded.mode,
                    prompt = excluded.prompt,
                    sample_input = excluded.sample_input,
                    sample_output = excluded.sample_output,
                    llm_provider_id = excluded.llm_provider_id,
                    model = excluded.model,
                    temperature = excluded.temperature,
                    enabled = excluded.enabled,
                    built_in = excluded.built_in,
                    is_default = excluded.is_default,
                    updated_at = excluded.updated_at
                """
            )
            try bind(profile, to: statement)
            _ = try statement.step()
        }
        AppLogger.database.info("样式已保存：id=\(profile.id)")
    }

    func profile(id: String) throws -> StyleProfileRecord? {
        AppLogger.database.debug("查询样式：id=\(id)")
        return try databaseQueue.read { connection in
            let statement = try connection.prepare(
                """
                SELECT id, name, category, subtitle, mode, prompt, sample_input,
                       sample_output, llm_provider_id, model, temperature, enabled,
                       built_in, is_default, created_at, updated_at
                FROM style_profiles
                WHERE id = ?
                LIMIT 1
                """
            )
            try statement.bind(id, at: 1)
            guard try statement.step() else {
                AppLogger.database.warning("样式不存在：id=\(id)")
                return nil
            }
            return try row(from: statement)
        }
    }

    func list(category: String?) throws -> [StyleProfileRecord] {
        AppLogger.database.debug("列出样式：category=\(category ?? "nil")")
        if let category {
            return try query(
                """
                SELECT id, name, category, subtitle, mode, prompt, sample_input,
                       sample_output, llm_provider_id, model, temperature, enabled,
                       built_in, is_default, created_at, updated_at
                FROM style_profiles
                WHERE category = ?
                ORDER BY built_in DESC, name ASC
                """,
                bindings: { statement in
                    try statement.bind(category, at: 1)
                }
            )
        }

        return try query(
            """
            SELECT id, name, category, subtitle, mode, prompt, sample_input,
                   sample_output, llm_provider_id, model, temperature, enabled,
                   built_in, is_default, created_at, updated_at
            FROM style_profiles
            ORDER BY built_in DESC, name ASC
            """,
            bindings: { _ in }
        )
    }

    func defaultProfile() throws -> StyleProfileRecord? {
        AppLogger.database.debug("查询默认样式")
        return try databaseQueue.read { connection in
            let statement = try connection.prepare(
                """
                SELECT id, name, category, subtitle, mode, prompt, sample_input,
                       sample_output, llm_provider_id, model, temperature, enabled,
                       built_in, is_default, created_at, updated_at
                FROM style_profiles
                WHERE is_default = 1
                LIMIT 1
                """
            )
            guard try statement.step() else {
                AppLogger.database.warning("默认样式不存在")
                return nil
            }
            return try row(from: statement)
        }
    }

    private func query(
        _ sql: String,
        bindings: (SQLiteStatement) throws -> Void
    ) throws -> [StyleProfileRecord] {
        return try databaseQueue.read { connection in
            let statement = try connection.prepare(sql)
            try bindings(statement)
            var profiles: [StyleProfileRecord] = []
            while try statement.step() {
                profiles.append(try row(from: statement))
            }
            AppLogger.database.debug("样式查询返回 count=\(profiles.count)")
            return profiles
        }
    }

    private func bind(_ profile: StyleProfileRecord, to statement: SQLiteStatement) throws {
        try statement.bind(profile.id, at: 1)
        try statement.bind(profile.name, at: 2)
        try statement.bind(profile.category, at: 3)
        try statement.bind(profile.subtitle, at: 4)
        try statement.bind(profile.mode, at: 5)
        try statement.bind(profile.prompt, at: 6)
        try statement.bind(profile.sampleInput, at: 7)
        try statement.bind(profile.sampleOutput, at: 8)
        try statement.bind(profile.llmProviderID, at: 9)
        try statement.bind(profile.model, at: 10)
        try statement.bind(profile.temperature, at: 11)
        try statement.bind(profile.enabled ? 1 : 0, at: 12)
        try statement.bind(profile.builtIn ? 1 : 0, at: 13)
        try statement.bind(profile.isDefault ? 1 : 0, at: 14)
        try statement.bind(formatter.string(from: profile.createdAt), at: 15)
        try statement.bind(formatter.string(from: profile.updatedAt), at: 16)
    }

    private func row(from statement: SQLiteStatement) throws -> StyleProfileRecord {
        guard let id = statement.columnString(at: 0),
              let name = statement.columnString(at: 1),
              let category = statement.columnString(at: 2),
              let mode = statement.columnString(at: 4),
              let prompt = statement.columnString(at: 5),
              let createdAtText = statement.columnString(at: 14),
              let updatedAtText = statement.columnString(at: 15),
              let createdAt = formatter.date(from: createdAtText) ?? legacyFractionalFormatter.date(from: createdAtText),
              let updatedAt = formatter.date(from: updatedAtText) ?? legacyFractionalFormatter.date(from: updatedAtText) else {
            throw SQLiteError.stepFailed("Invalid style_profiles row.")
        }

        return StyleProfileRecord(
            id: id,
            name: name,
            category: category,
            subtitle: statement.columnString(at: 3),
            mode: mode,
            prompt: prompt,
            sampleInput: statement.columnString(at: 6),
            sampleOutput: statement.columnString(at: 7),
            llmProviderID: statement.columnString(at: 8),
            model: statement.columnString(at: 9),
            temperature: statement.columnDouble(at: 10),
            enabled: statement.columnInt(at: 11) != 0,
            builtIn: statement.columnInt(at: 12) != 0,
            isDefault: statement.columnInt(at: 13) != 0,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
