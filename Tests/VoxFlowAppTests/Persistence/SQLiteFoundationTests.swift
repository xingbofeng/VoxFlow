import XCTest
@testable import VoxFlowApp

final class SQLiteFoundationTests: XCTestCase {
    func testConnectionExecutesAndQueriesRows() throws {
        let connection = try SQLiteConnection.inMemory()
        try connection.execute("CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")

        let insert = try connection.prepare("INSERT INTO items (name) VALUES (?)")
        try insert.bind("VoiceInput", at: 1)
        XCTAssertFalse(try insert.step())

        let query = try connection.prepare("SELECT name FROM items WHERE id = 1")
        XCTAssertTrue(try query.step())
        XCTAssertEqual(query.columnString(at: 0), "VoiceInput")
        XCTAssertFalse(try query.step())
    }

    func testDatabaseQueueRunsReadAndWriteBlocksAgainstSameConnection() throws {
        let queue = try DatabaseQueue(connection: .inMemory())

        try queue.write { connection in
            try connection.execute("CREATE TABLE counters (value INTEGER NOT NULL)")
            let statement = try connection.prepare("INSERT INTO counters (value) VALUES (?)")
            try statement.bind(42, at: 1)
            _ = try statement.step()
        }

        let value = try queue.read { connection in
            let statement = try connection.prepare("SELECT value FROM counters")
            XCTAssertTrue(try statement.step())
            return statement.columnInt(at: 0)
        }

        XCTAssertEqual(value, 42)
    }

    func testMigratorCreatesMigrationTableAndRecordsAppliedMigration() throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        let migrator = DatabaseMigrator(migrations: [
            DatabaseMigration(id: 1, name: "create_history") { connection in
                try connection.execute("CREATE TABLE history (id TEXT PRIMARY KEY)")
            }
        ])

        try migrator.migrate(queue)

        let applied = try queue.read { connection in
            let statement = try connection.prepare(
                "SELECT name FROM schema_migrations WHERE id = 1"
            )
            XCTAssertTrue(try statement.step())
            return statement.columnString(at: 0)
        }
        XCTAssertEqual(applied, "create_history")
    }

    func testMigratorDoesNotRunAppliedMigrationTwice() throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        let counter = Counter()
        let migrator = DatabaseMigrator(migrations: [
            DatabaseMigration(id: 1, name: "create_notes") { connection in
                counter.value += 1
                try connection.execute("CREATE TABLE notes (id TEXT PRIMARY KEY)")
            }
        ])

        try migrator.migrate(queue)
        try migrator.migrate(queue)

        XCTAssertEqual(counter.value, 1)
    }

    func testAppDatabaseInitialMigrationCreatesRequiredTables() throws {
        let queue = try DatabaseQueue(connection: .inMemory())

        try AppDatabase.migrator().migrate(queue)

        let tables = try queue.read { connection in
            try tableNames(on: connection)
        }

        XCTAssertTrue(tables.isSuperset(of: [
            "schema_migrations",
            "dictation_history",
            "style_profiles",
            "asr_providers",
            "llm_providers",
            "transcription_jobs",
            "notes",
            "app_settings",
            "voice_correction_rules",
            "voice_correction_events",
            "voice_correction_learning_suppression",
        ]))
        XCTAssertFalse(tables.contains("glossary_terms"))
        XCTAssertFalse(tables.contains("replacement_rules"))
    }

    func testAppDatabaseMigrationDropsLegacyGlossaryAndReplacementTables() throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        try queue.write { connection in
            try connection.execute(
                """
                CREATE TABLE schema_migrations (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    applied_at TEXT NOT NULL
                );
                CREATE TABLE glossary_terms (id TEXT PRIMARY KEY);
                CREATE TABLE replacement_rules (id TEXT PRIMARY KEY);
                INSERT INTO schema_migrations (id, name, applied_at)
                VALUES
                    (1, 'initial_schema', '2026-01-01T00:00:00Z'),
                    (2, 'dictation_history_processing_trace', '2026-01-01T00:00:00Z'),
                    (3, 'voice_tasks', '2026-01-01T00:00:00Z'),
                    (4, 'llm_provider_timeout_30s', '2026-01-01T00:00:00Z'),
                    (5, 'voice_task_asr_metadata', '2026-01-01T00:00:00Z');
                """
            )
        }

        try AppDatabase.migrator().migrate(queue)

        let tables = try queue.read { connection in
            try tableNames(on: connection)
        }
        XCTAssertFalse(tables.contains("glossary_terms"))
        XCTAssertFalse(tables.contains("replacement_rules"))
    }

    func testLLMProvidersStoreOnlyKeychainReference() throws {
        let queue = try DatabaseQueue(connection: .inMemory())

        try AppDatabase.migrator().migrate(queue)

        let columns = try queue.read { connection in
            try columnNames(table: "llm_providers", on: connection)
        }

        XCTAssertTrue(columns.contains("api_key_ref"))
        XCTAssertFalse(columns.contains("api_key"))
        XCTAssertFalse(columns.contains("apiKey"))
    }

    private func tableNames(on connection: SQLiteConnection) throws -> Set<String> {
        let statement = try connection.prepare(
            """
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
            """
        )
        var names = Set<String>()
        while try statement.step() {
            if let name = statement.columnString(at: 0) {
                names.insert(name)
            }
        }
        return names
    }

    private func columnNames(table: String, on connection: SQLiteConnection) throws -> Set<String> {
        let statement = try connection.prepare("PRAGMA table_info(\(table))")
        var names = Set<String>()
        while try statement.step() {
            if let name = statement.columnString(at: 1) {
                names.insert(name)
            }
        }
        return names
    }
}

private final class Counter {
    var value = 0
}
