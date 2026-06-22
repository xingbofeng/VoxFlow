import Foundation

struct ASRProviderRecord: Equatable {
    let id: String
    let displayName: String
    let providerType: String
    let capabilitiesJSON: String
    let tagsJSON: String
    let configJSON: String
    let enabled: Bool
    let isDefault: Bool
    let lastHealthStatus: String?
    let lastHealthMessage: String?
    let lastCheckedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}

struct LLMProviderRecord: Equatable {
    let id: String
    let displayName: String
    let providerType: String
    let baseURL: String
    let defaultModel: String
    let apiKeyRef: String
    let temperature: Double
    let timeoutSeconds: Double
    let enabled: Bool
    let isDefault: Bool
    let lastHealthStatus: String?
    let lastHealthMessage: String?
    let lastLatencyMS: Int?
    let createdAt: Date
    let updatedAt: Date
}

protocol ASRProviderRepository {
    func save(_ provider: ASRProviderRecord) throws
    func provider(id: String) throws -> ASRProviderRecord?
    func list() throws -> [ASRProviderRecord]
    func delete(id: String) throws
}

protocol LLMProviderRepository {
    func save(_ provider: LLMProviderRecord) throws
    func provider(id: String) throws -> LLMProviderRecord?
    func list() throws -> [LLMProviderRecord]
    func delete(id: String) throws
}

final class SQLiteASRProviderRepository: ASRProviderRepository {
    private let databaseQueue: DatabaseQueue
    private let formatter = ISO8601DateFormatter()

    init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    func save(_ provider: ASRProviderRecord) throws {
        AppLogger.database.debug("保存 ASR 提供商：id=\(provider.id), default=\(provider.isDefault)")
        try databaseQueue.write { connection in
            if provider.isDefault {
                try connection.execute("UPDATE asr_providers SET is_default = 0")
            }
            let statement = try connection.prepare(
                """
                INSERT INTO asr_providers (
                    id, display_name, provider_type, capabilities_json, tags_json,
                    config_json, enabled, is_default, last_health_status,
                    last_health_message, last_checked_at, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    display_name = excluded.display_name,
                    provider_type = excluded.provider_type,
                    capabilities_json = excluded.capabilities_json,
                    tags_json = excluded.tags_json,
                    config_json = excluded.config_json,
                    enabled = excluded.enabled,
                    is_default = excluded.is_default,
                    last_health_status = excluded.last_health_status,
                    last_health_message = excluded.last_health_message,
                    last_checked_at = excluded.last_checked_at,
                    updated_at = excluded.updated_at
                """
            )
            try statement.bind(provider.id, at: 1)
            try statement.bind(provider.displayName, at: 2)
            try statement.bind(provider.providerType, at: 3)
            try statement.bind(provider.capabilitiesJSON, at: 4)
            try statement.bind(provider.tagsJSON, at: 5)
            try statement.bind(provider.configJSON, at: 6)
            try statement.bind(provider.enabled ? 1 : 0, at: 7)
            try statement.bind(provider.isDefault ? 1 : 0, at: 8)
            try statement.bind(provider.lastHealthStatus, at: 9)
            try statement.bind(provider.lastHealthMessage, at: 10)
            try statement.bind(provider.lastCheckedAt.map(formatter.string(from:)), at: 11)
            try statement.bind(formatter.string(from: provider.createdAt), at: 12)
            try statement.bind(formatter.string(from: provider.updatedAt), at: 13)
            _ = try statement.step()
        }
        AppLogger.database.info("ASR 提供商已保存：id=\(provider.id)")
    }

    func list() throws -> [ASRProviderRecord] {
        AppLogger.database.debug("列出 ASR 提供商")
        return try databaseQueue.read { connection in
            let statement = try connection.prepare(
                """
                SELECT id, display_name, provider_type, capabilities_json, tags_json,
                       config_json, enabled, is_default, last_health_status,
                       last_health_message, last_checked_at, created_at, updated_at
                FROM asr_providers
                ORDER BY created_at ASC, display_name ASC
                """
            )
            var records: [ASRProviderRecord] = []
            while try statement.step() {
                records.append(try row(from: statement))
            }
            AppLogger.database.debug("ASR 提供商列表返回 count=\(records.count)")
            return records
        }
    }

    func provider(id: String) throws -> ASRProviderRecord? {
        AppLogger.database.debug("查询 ASR 提供商：id=\(id)")
        return try databaseQueue.read { connection in
            let stmt = try connection.prepare("SELECT id, display_name, provider_type, capabilities_json, tags_json, config_json, enabled, is_default, last_health_status, last_health_message, last_checked_at, created_at, updated_at FROM asr_providers WHERE id = ?")
            try stmt.bind(id, at: 1)
            guard try stmt.step() else { return nil }
            AppLogger.database.warning("ASR 提供商不存在：id=\(id)")
            return try row(from: stmt)
        }
    }

    func delete(id: String) throws {
        AppLogger.database.warning("删除 ASR 提供商：id=\(id)")
        try databaseQueue.write { connection in
            let stmt = try connection.prepare("DELETE FROM asr_providers WHERE id = ?")
            try stmt.bind(id, at: 1); _ = try stmt.step()
        }
    }

    private func row(from statement: SQLiteStatement) throws -> ASRProviderRecord {
        guard let id = statement.columnString(at: 0),
              let displayName = statement.columnString(at: 1),
              let providerType = statement.columnString(at: 2),
              let capabilitiesJSON = statement.columnString(at: 3),
              let tagsJSON = statement.columnString(at: 4),
              let configJSON = statement.columnString(at: 5),
              let createdAtText = statement.columnString(at: 11),
              let updatedAtText = statement.columnString(at: 12),
              let createdAt = formatter.date(from: createdAtText),
              let updatedAt = formatter.date(from: updatedAtText) else {
            throw SQLiteError.stepFailed("Invalid asr_providers row.")
        }

        return ASRProviderRecord(
            id: id,
            displayName: displayName,
            providerType: providerType,
            capabilitiesJSON: capabilitiesJSON,
            tagsJSON: tagsJSON,
            configJSON: configJSON,
            enabled: statement.columnInt(at: 6) != 0,
            isDefault: statement.columnInt(at: 7) != 0,
            lastHealthStatus: statement.columnString(at: 8),
            lastHealthMessage: statement.columnString(at: 9),
            lastCheckedAt: statement.columnString(at: 10).flatMap(formatter.date(from:)),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

final class SQLiteLLMProviderRepository: LLMProviderRepository {
    private let databaseQueue: DatabaseQueue
    private let formatter = ISO8601DateFormatter()

    init(databaseQueue: DatabaseQueue) {
        self.databaseQueue = databaseQueue
    }

    func save(_ provider: LLMProviderRecord) throws {
        AppLogger.database.debug("保存 LLM 提供商：id=\(provider.id), default=\(provider.isDefault)")
        try databaseQueue.write { connection in
            if provider.isDefault {
                try connection.execute("UPDATE llm_providers SET is_default = 0")
            }
            let statement = try connection.prepare(
                """
                INSERT INTO llm_providers (
                    id, display_name, provider_type, base_url, default_model,
                    api_key_ref, temperature, timeout_seconds, enabled, is_default,
                    last_health_status, last_health_message, last_latency_ms,
                    created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    display_name = excluded.display_name,
                    provider_type = excluded.provider_type,
                    base_url = excluded.base_url,
                    default_model = excluded.default_model,
                    api_key_ref = excluded.api_key_ref,
                    temperature = excluded.temperature,
                    timeout_seconds = excluded.timeout_seconds,
                    enabled = excluded.enabled,
                    is_default = excluded.is_default,
                    last_health_status = excluded.last_health_status,
                    last_health_message = excluded.last_health_message,
                    last_latency_ms = excluded.last_latency_ms,
                    updated_at = excluded.updated_at
                """
            )
            try statement.bind(provider.id, at: 1)
            try statement.bind(provider.displayName, at: 2)
            try statement.bind(provider.providerType, at: 3)
            try statement.bind(provider.baseURL, at: 4)
            try statement.bind(provider.defaultModel, at: 5)
            try statement.bind(provider.apiKeyRef, at: 6)
            try statement.bind(provider.temperature, at: 7)
            try statement.bind(provider.timeoutSeconds, at: 8)
            try statement.bind(provider.enabled ? 1 : 0, at: 9)
            try statement.bind(provider.isDefault ? 1 : 0, at: 10)
            try statement.bind(provider.lastHealthStatus, at: 11)
            try statement.bind(provider.lastHealthMessage, at: 12)
            try statement.bind(provider.lastLatencyMS, at: 13)
            try statement.bind(formatter.string(from: provider.createdAt), at: 14)
            try statement.bind(formatter.string(from: provider.updatedAt), at: 15)
            _ = try statement.step()
        }
        AppLogger.database.info("LLM 提供商已保存：id=\(provider.id)")
    }

    func provider(id: String) throws -> LLMProviderRecord? {
        AppLogger.database.debug("查询 LLM 提供商：id=\(id)")
        return try databaseQueue.read { connection in
            let statement = try connection.prepare(selectSQL + " WHERE id = ?")
            try statement.bind(id, at: 1)
            guard try statement.step() else {
                AppLogger.database.warning("LLM 提供商不存在：id=\(id)")
                return nil
            }
            return try row(from: statement)
        }
    }

    func list() throws -> [LLMProviderRecord] {
        AppLogger.database.debug("列出 LLM 提供商")
        return try databaseQueue.read { connection in
            let statement = try connection.prepare(selectSQL + " ORDER BY created_at ASC, display_name ASC")
            var records: [LLMProviderRecord] = []
            while try statement.step() {
                records.append(try row(from: statement))
            }
            AppLogger.database.debug("LLM 提供商列表返回 count=\(records.count)")
            return records
        }
    }

    func delete(id: String) throws {
        AppLogger.database.warning("删除 LLM 提供商：id=\(id)")
        try databaseQueue.write { connection in
            let statement = try connection.prepare("DELETE FROM llm_providers WHERE id = ?")
            try statement.bind(id, at: 1)
            _ = try statement.step()
        }
    }

    private var selectSQL: String {
        """
        SELECT id, display_name, provider_type, base_url, default_model,
               api_key_ref, temperature, timeout_seconds, enabled, is_default,
               last_health_status, last_health_message, last_latency_ms,
               created_at, updated_at
        FROM llm_providers
        """
    }

    private func row(from statement: SQLiteStatement) throws -> LLMProviderRecord {
        guard let id = statement.columnString(at: 0),
              let displayName = statement.columnString(at: 1),
              let providerType = statement.columnString(at: 2),
              let baseURL = statement.columnString(at: 3),
              let defaultModel = statement.columnString(at: 4),
              let apiKeyRef = statement.columnString(at: 5),
              let createdAtText = statement.columnString(at: 13),
              let updatedAtText = statement.columnString(at: 14),
              let createdAt = formatter.date(from: createdAtText),
              let updatedAt = formatter.date(from: updatedAtText) else {
            throw SQLiteError.stepFailed("Invalid llm_providers row.")
        }

        return LLMProviderRecord(
            id: id,
            displayName: displayName,
            providerType: providerType,
            baseURL: baseURL,
            defaultModel: defaultModel,
            apiKeyRef: apiKeyRef,
            temperature: statement.columnDouble(at: 6),
            timeoutSeconds: statement.columnDouble(at: 7),
            enabled: statement.columnInt(at: 8) != 0,
            isDefault: statement.columnInt(at: 9) != 0,
            lastHealthStatus: statement.columnString(at: 10),
            lastHealthMessage: statement.columnString(at: 11),
            lastLatencyMS: statement.columnString(at: 12) == nil ? nil : statement.columnInt(at: 12),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
