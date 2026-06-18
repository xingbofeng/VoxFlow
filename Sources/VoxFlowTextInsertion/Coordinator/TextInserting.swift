public enum TextInsertionResult: Equatable {
    case success
    case permissionDenied
    case eventCreationFailed
    case cancelled
    case unavailable(reason: String)
}

@MainActor
public protocol TextInserting: AnyObject {
    @discardableResult
    func insert(_ text: String) async -> TextInsertionResult
}
