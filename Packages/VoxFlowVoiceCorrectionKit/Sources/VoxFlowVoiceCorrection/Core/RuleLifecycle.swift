public enum RuleLifecycle: String, Codable, Sendable, CaseIterable {
    case candidate
    case active
    case suspended
    case retired
}

public enum RuleSource: String, Codable, Sendable, CaseIterable {
    case manual
    case imported
    case automaticLearning
}
