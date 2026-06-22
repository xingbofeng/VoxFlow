import Foundation

final class DatabaseQueue {
    private let connection: SQLiteConnection
    private let queue = DispatchQueue(label: "com.voxflow.app.database")

    init(connection: SQLiteConnection) throws {
        self.connection = connection
    }

    func read<T>(_ block: (SQLiteConnection) throws -> T) throws -> T {
        AppLogger.database.debug("DatabaseQueue read 开始")
        return try queue.sync {
            try block(connection)
        }
    }

    func write<T>(_ block: (SQLiteConnection) throws -> T) throws -> T {
        AppLogger.database.debug("DatabaseQueue write 开始")
        return try queue.sync {
            try block(connection)
        }
    }
}
