import Foundation
import SQLite3

final class SQLiteConnection {
    private var handle: OpaquePointer?

    convenience init(url: URL) throws {
        try self.init(path: url.path)
    }

    private init(path: String) throws {
        AppLogger.database.debug("Opening SQLite database path=\(path)")
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(path, &database, flags, nil)

        guard status == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database."
            if let database {
                sqlite3_close(database)
            }
            AppLogger.database.error("SQLite open failed path=\(path), reason=\(message)")
            throw SQLiteError.openFailed(message)
        }

        handle = database
        AppLogger.database.info("SQLite database opened path=\(path)")
    }

    deinit {
        if let handle {
            AppLogger.database.debug("Closing SQLite database")
            sqlite3_close(handle)
        }
    }

    static func inMemory() throws -> SQLiteConnection {
        try SQLiteConnection(path: ":memory:")
    }

    func execute(_ sql: String) throws {
        AppLogger.database.debug("SQLite execute sqlPreview=\(sql.prefix(80))")
        let database = try databaseHandle()
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard status == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? self.errorMessage()
            sqlite3_free(errorMessage)
            AppLogger.database.error("SQLite execute failed sqlPreview=\(sql.prefix(80)), reason=\(message)")
            throw SQLiteError.executionFailed(message)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        AppLogger.database.debug("SQLite prepare sqlPreview=\(sql.prefix(80))")
        let database = try databaseHandle()
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(database, sql, -1, &statement, nil)

        guard status == SQLITE_OK, let statement else {
            AppLogger.database.error("SQLite prepare failed sqlPreview=\(sql.prefix(80)), reason=\(errorMessage())")
            throw SQLiteError.prepareFailed(errorMessage())
        }

        return SQLiteStatement(statement: statement)
    }

    func addColumnIfNeeded(table: String, column: String, definition: String) throws {
        AppLogger.database.debug("SQLite addColumnIfNeeded table=\(table) column=\(column)")
        let escapedTable = table.replacingOccurrences(of: "'", with: "''")
        let statement = try prepare("PRAGMA table_info('\(escapedTable)')")
        while try statement.step() {
            if statement.columnString(at: 1) == column {
                return
            }
        }
        try execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }

    private func databaseHandle() throws -> OpaquePointer {
        guard let handle else {
            throw SQLiteError.closed
        }
        return handle
    }

    private func errorMessage() -> String {
        guard let handle else {
            return "Database is closed."
        }
        return String(cString: sqlite3_errmsg(handle))
    }
}

final class SQLiteStatement {
    private let statement: OpaquePointer

    init(statement: OpaquePointer) {
        self.statement = statement
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func bind(_ value: String, at index: Int32) throws {
        AppLogger.database.debug("SQLite bind string index=\(index)")
        let status = sqlite3_bind_text(statement, index, value, -1, sqliteTransientDestructor)
        guard status == SQLITE_OK else {
            AppLogger.database.error("SQLite bind string failed index=\(index), reason=\(errorMessage())")
            throw SQLiteError.bindFailed(errorMessage())
        }
    }

    func bind(_ value: String?, at index: Int32) throws {
        guard let value else {
            AppLogger.database.debug("SQLite bind null string index=\(index)")
            let status = sqlite3_bind_null(statement, index)
            guard status == SQLITE_OK else {
                AppLogger.database.error("SQLite bind null string failed index=\(index), reason=\(errorMessage())")
                throw SQLiteError.bindFailed(errorMessage())
            }
            return
        }
        try bind(value, at: index)
    }

    func bind(_ value: Int, at index: Int32) throws {
        AppLogger.database.debug("SQLite bind int index=\(index)")
        let status = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        guard status == SQLITE_OK else {
            AppLogger.database.error("SQLite bind int failed index=\(index), reason=\(errorMessage())")
            throw SQLiteError.bindFailed(errorMessage())
        }
    }

    func bind(_ value: Int?, at index: Int32) throws {
        guard let value else {
            AppLogger.database.debug("SQLite bind null int index=\(index)")
            let status = sqlite3_bind_null(statement, index)
            guard status == SQLITE_OK else {
                AppLogger.database.error("SQLite bind null int failed index=\(index), reason=\(errorMessage())")
                throw SQLiteError.bindFailed(errorMessage())
            }
            return
        }
        try bind(value, at: index)
    }

    func bind(_ value: Double, at index: Int32) throws {
        AppLogger.database.debug("SQLite bind double index=\(index)")
        let status = sqlite3_bind_double(statement, index, value)
        guard status == SQLITE_OK else {
            AppLogger.database.error("SQLite bind double failed index=\(index), reason=\(errorMessage())")
            throw SQLiteError.bindFailed(errorMessage())
        }
    }

    func step() throws -> Bool {
        AppLogger.database.debug("SQLite step")
        let status = sqlite3_step(statement)
        switch status {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            AppLogger.database.error("SQLite step failed reason=\(errorMessage())")
            throw SQLiteError.stepFailed(errorMessage())
        }
    }

    func reset() throws {
        let resetStatus = sqlite3_reset(statement)
        let clearStatus = sqlite3_clear_bindings(statement)
        guard resetStatus == SQLITE_OK, clearStatus == SQLITE_OK else {
            throw SQLiteError.stepFailed(errorMessage())
        }
    }

    func columnString(at index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    func columnInt(at index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }

    func columnDouble(at index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    private func errorMessage() -> String {
        String(cString: sqlite3_errmsg(sqlite3_db_handle(statement)))
    }
}

enum SQLiteError: Error, LocalizedError {
    case openFailed(String)
    case executionFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case stepFailed(String)
    case closed

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "SQLite open failed: \(message)"
        case .executionFailed(let message):
            return "SQLite execution failed: \(message)"
        case .prepareFailed(let message):
            return "SQLite prepare failed: \(message)"
        case .bindFailed(let message):
            return "SQLite bind failed: \(message)"
        case .stepFailed(let message):
            return "SQLite step failed: \(message)"
        case .closed:
            return "SQLite database is closed."
        }
    }
}

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
