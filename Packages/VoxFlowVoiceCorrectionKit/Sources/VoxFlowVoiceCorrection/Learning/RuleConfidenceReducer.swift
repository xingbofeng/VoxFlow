import Foundation

public struct RuleConfidenceReducer: Sendable {
    public init() {}

    public func recordRevert(
        _ rule: CorrectionRule,
        at date: Date
    ) -> CorrectionRule {
        var updated = rule
        updated.revertedCount += 1
        updated.confidence = max(0, updated.confidence - 0.35)
        updated.updatedAt = date
        if updated.revertedCount >= 2 {
            updated.lifecycle = .suspended
        }
        return updated
    }
}
