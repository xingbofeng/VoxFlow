public struct CorrectionMatch: Sendable, Equatable {
    public let rule: CorrectionRule
    public let range: CorrectionTextRange
    public let matchedText: String

    public init(
        rule: CorrectionRule,
        range: CorrectionTextRange,
        matchedText: String
    ) {
        self.rule = rule
        self.range = range
        self.matchedText = matchedText
    }
}
