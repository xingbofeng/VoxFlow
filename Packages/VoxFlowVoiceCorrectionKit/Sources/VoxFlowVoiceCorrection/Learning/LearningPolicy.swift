import Foundation

public enum LearningUndoAction: Sendable, Equatable {
    case delete(UUID)
    case suspend(UUID)
    case ignore
}

public struct LearningSuppressionEntry: Sendable, Equatable {
    public let pair: LearnedCorrectionPair
    public let bundleIdentifier: String?
    public let suppressedUntil: Date

    public init(
        pair: LearnedCorrectionPair,
        bundleIdentifier: String?,
        suppressedUntil: Date
    ) {
        self.pair = pair
        self.bundleIdentifier = bundleIdentifier
        self.suppressedUntil = suppressedUntil
    }
}

public struct LearningSuppressionList: Sendable, Equatable {
    public private(set) var entries: [LearningSuppressionEntry]

    public init(entries: [LearningSuppressionEntry] = []) {
        self.entries = entries
    }

    public mutating func suppress(
        _ pair: LearnedCorrectionPair,
        bundleIdentifier: String?,
        now: Date
    ) {
        entries.append(
            LearningSuppressionEntry(
                pair: pair,
                bundleIdentifier: bundleIdentifier,
                suppressedUntil: now.addingTimeInterval(30 * 24 * 60 * 60)
            )
        )
    }

    public func contains(
        _ pair: LearnedCorrectionPair,
        bundleIdentifier: String?,
        now: Date
    ) -> Bool {
        entries.contains {
            $0.suppressedUntil > now &&
                $0.bundleIdentifier == bundleIdentifier &&
                $0.pair.original.caseInsensitiveCompare(pair.original) == .orderedSame &&
                $0.pair.replacement.caseInsensitiveCompare(pair.replacement) == .orderedSame
        }
    }
}

public struct LearningPolicy: Sendable {
    public init() {}

    public func manualRule(
        original: String,
        replacement: String,
        scope: RuleScope,
        createdAt: Date
    ) -> CorrectionRule {
        CorrectionRule(
            original: original,
            replacement: replacement,
            matchPolicy: .boundary,
            scope: scope,
            lifecycle: .active,
            source: .manual,
            confidence: 1,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    public func learnedRule(
        pair: LearnedCorrectionPair,
        context: CorrectionContext,
        appliesImmediately: Bool,
        createdAt: Date
    ) -> CorrectionRule? {
        guard context.mode == .dictation,
              context.isFinalTranscript,
              !context.isSecureField,
              let bundleIdentifier = context.bundleIdentifier
        else {
            return nil
        }

        return CorrectionRule(
            original: pair.original,
            replacement: pair.replacement,
            matchPolicy: .boundary,
            scope: .application(bundleIdentifier: bundleIdentifier),
            lifecycle: appliesImmediately ? .active : .candidate,
            source: .automaticLearning,
            confidence: appliesImmediately ? 0.90 : 0.40,
            observedCount: 1,
            providerID: context.providerID,
            modelID: context.modelID,
            language: context.language,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    public func undoRecentAutomaticLearning(_ rule: CorrectionRule) -> LearningUndoAction {
        guard rule.source == .automaticLearning else {
            return .ignore
        }
        return .delete(rule.id)
    }

    public func wouldCreateFeedbackChain(
        _ pair: LearnedCorrectionPair,
        existingRules: [CorrectionRule]
    ) -> Bool {
        existingRules.contains {
            $0.source == .automaticLearning &&
                $0.replacement.caseInsensitiveCompare(pair.original) == .orderedSame
        }
    }
}
