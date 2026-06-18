import Foundation

struct AppSettingRecord: Equatable {
    let key: String
    let valueJSON: String
    let updatedAt: Date
}

protocol SettingsRepository {
    func value(forKey key: String) throws -> String?
    func set(_ key: String, jsonValue: String) throws
    func deleteValue(forKey key: String) throws
    func list() throws -> [AppSettingRecord]
}

final class SQLiteSettingsRepository: SettingsRepository {
    private let databaseQueue: DatabaseQueue
    private let clock: any AppClock

    init(
        databaseQueue: DatabaseQueue,
        clock: any AppClock = SystemClock()
    ) {
        self.databaseQueue = databaseQueue
        self.clock = clock
    }

    func value(forKey key: String) throws -> String? {
        try databaseQueue.read { connection in
            let statement = try connection.prepare(
                "SELECT value_json FROM app_settings WHERE key = ?"
            )
            try statement.bind(key, at: 1)
            guard try statement.step() else {
                return nil
            }
            return statement.columnString(at: 0)
        }
    }

    func set(_ key: String, jsonValue: String) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare(
                """
                INSERT INTO app_settings (key, value_json, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    value_json = excluded.value_json,
                    updated_at = excluded.updated_at
                """
            )
            try statement.bind(key, at: 1)
            try statement.bind(jsonValue, at: 2)
            try statement.bind(ISO8601DateFormatter().string(from: clock.now), at: 3)
            _ = try statement.step()
        }
    }

    func deleteValue(forKey key: String) throws {
        try databaseQueue.write { connection in
            let statement = try connection.prepare("DELETE FROM app_settings WHERE key = ?")
            try statement.bind(key, at: 1)
            _ = try statement.step()
        }
    }

    func list() throws -> [AppSettingRecord] {
        try databaseQueue.read { connection in
            let statement = try connection.prepare(
                "SELECT key, value_json, updated_at FROM app_settings ORDER BY key ASC"
            )
            var records: [AppSettingRecord] = []
            while try statement.step() {
                guard let key = statement.columnString(at: 0),
                      let valueJSON = statement.columnString(at: 1),
                      let updatedAtText = statement.columnString(at: 2),
                      let updatedAt = ISO8601DateFormatter().date(from: updatedAtText) else {
                    throw SQLiteError.stepFailed("Invalid app_settings row.")
                }
                records.append(
                    AppSettingRecord(
                        key: key,
                        valueJSON: valueJSON,
                        updatedAt: updatedAt
                    )
                )
            }
            return records
        }
    }
}
