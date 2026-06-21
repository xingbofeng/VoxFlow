public struct ConflictResolver: Sendable {
    public init() {}

    public func resolve(_ matches: [CorrectionMatch]) -> [CorrectionMatch] {
        let prioritized = matches.sorted(by: isHigherPriority)
        var accepted: [CorrectionMatch] = []

        for candidate in prioritized where !accepted.contains(where: { overlaps($0, candidate) }) {
            accepted.append(candidate)
        }

        return accepted.sorted {
            if $0.range.location != $1.range.location {
                return $0.range.location < $1.range.location
            }
            return $0.rule.id.uuidString < $1.rule.id.uuidString
        }
    }

    private func isHigherPriority(_ lhs: CorrectionMatch, _ rhs: CorrectionMatch) -> Bool {
        let lhsSource = sourcePriority(lhs.rule.source)
        let rhsSource = sourcePriority(rhs.rule.source)
        if lhsSource != rhsSource {
            return lhsSource > rhsSource
        }

        let lhsScope = scopePriority(lhs.rule.scope)
        let rhsScope = scopePriority(rhs.rule.scope)
        if lhsScope != rhsScope {
            return lhsScope > rhsScope
        }

        let lhsPolicy = policyPriority(lhs.rule.matchPolicy)
        let rhsPolicy = policyPriority(rhs.rule.matchPolicy)
        if lhsPolicy != rhsPolicy {
            return lhsPolicy > rhsPolicy
        }

        if lhs.rule.confidence != rhs.rule.confidence {
            return lhs.rule.confidence > rhs.rule.confidence
        }
        if lhs.range.length != rhs.range.length {
            return lhs.range.length > rhs.range.length
        }
        if lhs.range.location != rhs.range.location {
            return lhs.range.location < rhs.range.location
        }
        return lhs.rule.id.uuidString < rhs.rule.id.uuidString
    }

    private func overlaps(_ lhs: CorrectionMatch, _ rhs: CorrectionMatch) -> Bool {
        let lhsEnd = lhs.range.location + lhs.range.length
        let rhsEnd = rhs.range.location + rhs.range.length
        return lhs.range.location < rhsEnd && rhs.range.location < lhsEnd
    }

    private func sourcePriority(_ source: RuleSource) -> Int {
        switch source {
        case .manual: 3
        case .imported: 2
        case .automaticLearning: 1
        }
    }

    private func scopePriority(_ scope: RuleScope) -> Int {
        switch scope {
        case .application: 2
        case .global: 1
        }
    }

    private func policyPriority(_ policy: MatchPolicy) -> Int {
        switch policy {
        case .exact: 3
        case .boundary: 2
        case .substring: 1
        }
    }
}
