import Foundation

public struct CorrectionTextRange: Codable, Sendable, Equatable {
    public let location: Int
    public let length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

public struct CorrectionEvent: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let ruleID: UUID
    public let original: String
    public let replacement: String
    public let range: CorrectionTextRange
    public let scope: RuleScope
    public let source: RuleSource

    public init(
        id: UUID = UUID(),
        ruleID: UUID,
        original: String,
        replacement: String,
        range: CorrectionTextRange,
        scope: RuleScope,
        source: RuleSource
    ) {
        self.id = id
        self.ruleID = ruleID
        self.original = original
        self.replacement = replacement
        self.range = range
        self.scope = scope
        self.source = source
    }
}
