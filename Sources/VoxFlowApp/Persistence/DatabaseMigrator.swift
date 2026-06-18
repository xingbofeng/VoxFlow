import Foundation

struct DatabaseMigration {
    let id: Int
    let name: String
    let apply: (SQLiteConnection) throws -> Void
}

final class DatabaseMigrator {
    private let migrations: [DatabaseMigration]
    private let clock: any AppClock

    init(
        migrations: [DatabaseMigration],
        clock: any AppClock = SystemClock()
    ) {
        self.migrations = migrations.sorted { $0.id < $1.id }
        self.clock = clock
    }

    func migrate(_ databaseQueue: DatabaseQueue) throws {
        try databaseQueue.write { connection in
            try ensureMigrationTable(on: connection)
            let appliedIDs = try appliedMigrationIDs(on: connection)

            for migration in migrations where !appliedIDs.contains(migration.id) {
                try apply(migration, on: connection)
            }
        }
    }

    private func ensureMigrationTable(on connection: SQLiteConnection) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                applied_at TEXT NOT NULL
            )
            """
        )
    }

    private func appliedMigrationIDs(on connection: SQLiteConnection) throws -> Set<Int> {
        let statement = try connection.prepare("SELECT id FROM schema_migrations")
        var ids = Set<Int>()
        while try statement.step() {
            ids.insert(statement.columnInt(at: 0))
        }
        return ids
    }

    private func apply(_ migration: DatabaseMigration, on connection: SQLiteConnection) throws {
        try connection.execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try migration.apply(connection)
            try record(migration, on: connection)
            try connection.execute("COMMIT")
        } catch {
            try? connection.execute("ROLLBACK")
            throw error
        }
    }

    private func record(_ migration: DatabaseMigration, on connection: SQLiteConnection) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO schema_migrations (id, name, applied_at)
            VALUES (?, ?, ?)
            """
        )
        try statement.bind(migration.id, at: 1)
        try statement.bind(migration.name, at: 2)
        try statement.bind(ISO8601DateFormatter().string(from: clock.now), at: 3)
        _ = try statement.step()
    }
}
