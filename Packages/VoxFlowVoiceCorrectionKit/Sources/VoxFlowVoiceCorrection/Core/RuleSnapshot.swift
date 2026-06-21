public struct RuleSnapshot: Codable, Sendable, Equatable {
    public let version: UInt64
    public let rules: [CorrectionRule]

    public init(version: UInt64, rules: [CorrectionRule]) {
        self.version = version
        self.rules = rules
    }

    public static let empty = RuleSnapshot(version: 0, rules: [])
}
