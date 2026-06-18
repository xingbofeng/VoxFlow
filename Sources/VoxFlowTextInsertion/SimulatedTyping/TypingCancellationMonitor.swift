public protocol TypingCancellationMonitoring: AnyObject {
    var isCancelled: Bool { get }
}

public final class TypingCancellationToken: TypingCancellationMonitoring {
    public private(set) var isCancelled = false

    public init() {}

    public func cancel() {
        isCancelled = true
    }
}
