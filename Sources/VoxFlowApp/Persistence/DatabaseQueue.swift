import Foundation

final class DatabaseQueue {
    private let connection: SQLiteConnection
    private let queue = DispatchQueue(label: "com.voxflow.app.database")

    init(connection: SQLiteConnection) throws {
        self.connection = connection
    }

    func read<T>(_ block: (SQLiteConnection) throws -> T) throws -> T {
        try queue.sync {
            try block(connection)
        }
    }

    func write<T>(_ block: (SQLiteConnection) throws -> T) throws -> T {
        try queue.sync {
            try block(connection)
        }
    }
}
