public enum MatchPolicy: String, Codable, Sendable, CaseIterable {
    case exact
    case boundary
    case substring
}
