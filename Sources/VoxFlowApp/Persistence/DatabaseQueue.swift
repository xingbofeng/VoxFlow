import Foundation

final class DatabaseQueue {
    private static let currentQueueKey = DispatchSpecificKey<ObjectIdentifier>()

    private let connection: SQLiteConnection
    private let queue = DispatchQueue(label: "com.voxflow.app.database")

    init(connection: SQLiteConnection) throws {
        self.connection = connection
        queue.setSpecific(key: Self.currentQueueKey, value: ObjectIdentifier(self))
    }

    func read<T>(_ block: (SQLiteConnection) throws -> T) throws -> T {
        AppLogger.database.debug("DatabaseQueue read 开始")
        if isExecutingOnQueue {
            AppLogger.database.debug("DatabaseQueue nested read 直接执行")
            return try block(connection)
        }
        return try queue.sync {
            try block(connection)
        }
    }

    func write<T>(_ block: (SQLiteConnection) throws -> T) throws -> T {
        AppLogger.database.debug("DatabaseQueue write 开始")
        if isExecutingOnQueue {
            AppLogger.database.debug("DatabaseQueue nested write 直接执行")
            return try block(connection)
        }
        return try queue.sync {
            try block(connection)
        }
    }

    private var isExecutingOnQueue: Bool {
        DispatchQueue.getSpecific(key: Self.currentQueueKey) == ObjectIdentifier(self)
    }
}
