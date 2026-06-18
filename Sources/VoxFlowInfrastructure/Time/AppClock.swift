import Foundation

public protocol AppClock: Sendable {
    var now: Date { get }
    func sleep(nanoseconds: UInt64) async throws
}

public struct SystemClock: AppClock {
    public init() {}

    public var now: Date {
        Date()
    }

    public func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}
