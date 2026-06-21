public enum RuleScope: Codable, Sendable, Equatable, Hashable {
    case global
    case application(bundleIdentifier: String)
}
