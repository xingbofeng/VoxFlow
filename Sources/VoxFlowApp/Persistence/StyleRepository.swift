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
    let outputFormat: StyleOutputFormat?

    /// 是否允许此 style 参与 AI 自动风格路由。内置风格默认开启；用户仍可
    /// 在自动匹配配置中关闭单个 style。
    let allowAutoMatch: Bool

    /// 一句话简介，供 AI router 理解此 style 适用场景。由用户编辑或由 AI 生成。
    /// `allowAutoMatch==true` 且简介非空的 style 才会形成 router 候选项。
    let autoMatchDescription: String?

    init(
        id: String,
        name: String,
        category: String,
        subtitle: String?,
        mode: String,
        prompt: String,
        sampleInput: String?,
        sampleOutput: String?,
        llmProviderID: String?,
        model: String?,
        temperature: Double,
        enabled: Bool,
        builtIn: Bool,
        isDefault: Bool,
        createdAt: Date,
        updatedAt: Date,
        outputFormat: StyleOutputFormat? = nil,
        allowAutoMatch: Bool = true,
        autoMatchDescription: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.subtitle = subtitle
        self.mode = mode
        self.prompt = prompt
        self.sampleInput = sampleInput
        self.sampleOutput = sampleOutput
        self.llmProviderID = llmProviderID
        self.model = model
        self.temperature = temperature
        self.enabled = enabled
        self.builtIn = builtIn
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.outputFormat = outputFormat
        self.allowAutoMatch = allowAutoMatch
        self.autoMatchDescription = autoMatchDescription
    }

    /// `true` 表示此 style 满足 AI router 候选条件：启用、允许自动匹配、
    /// 且 `autoMatchDescription` 非空。
    var isEligibleForAutoRouter: Bool {
        enabled && allowAutoMatch && !(autoMatchDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
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
    private let outputFormatEncoder = JSONEncoder()
    private let outputFormatDecoder = JSONDecoder()
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
                    built_in, is_default, created_at, updated_at,
                    output_format_json, allow_auto_match, auto_match_description
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                    updated_at = excluded.updated_at,
                    output_format_json = excluded.output_format_json,
                    allow_auto_match = excluded.allow_auto_match,
                    auto_match_description = excluded.auto_match_description
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
                       built_in, is_default, created_at, updated_at,
                       output_format_json, allow_auto_match, auto_match_description
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
                       built_in, is_default, created_at, updated_at,
                       output_format_json, allow_auto_match, auto_match_description
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
                   built_in, is_default, created_at, updated_at,
                   output_format_json, allow_auto_match, auto_match_description
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
                       built_in, is_default, created_at, updated_at,
                       output_format_json, allow_auto_match, auto_match_description
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
        try statement.bind(outputFormatJSON(effectiveOutputFormat(for: profile)), at: 17)
        try statement.bind(profile.allowAutoMatch ? 1 : 0, at: 18)
        try statement.bind(profile.autoMatchDescription, at: 19)
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

        let builtIn = statement.columnInt(at: 12) != 0
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
            builtIn: builtIn,
            isDefault: statement.columnInt(at: 13) != 0,
            createdAt: createdAt,
            updatedAt: updatedAt,
            outputFormat: outputFormat(from: statement.columnString(at: 16))
                ?? defaultOutputFormat(for: id, builtIn: builtIn),
            allowAutoMatch: statement.columnInt(at: 17) != 0,
            autoMatchDescription: statement.columnString(at: 18)
        )
    }

    private func outputFormatJSON(_ outputFormat: StyleOutputFormat?) throws -> String? {
        guard let outputFormat else { return nil }
        let data = try outputFormatEncoder.encode(outputFormat)
        return String(data: data, encoding: .utf8)
    }

    private func effectiveOutputFormat(for profile: StyleProfileRecord) -> StyleOutputFormat? {
        profile.outputFormat ?? defaultOutputFormat(for: profile.id, builtIn: profile.builtIn)
    }

    private func defaultOutputFormat(for profileID: String, builtIn: Bool) -> StyleOutputFormat {
        (builtIn ? StyleOutputFormat.builtInDefault(for: profileID) : nil)
            ?? StyleOutputFormat.systemDefault
    }

    private func outputFormat(from json: String?) -> StyleOutputFormat? {
        guard let json,
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? outputFormatDecoder.decode(StyleOutputFormat.self, from: data)
    }
}
