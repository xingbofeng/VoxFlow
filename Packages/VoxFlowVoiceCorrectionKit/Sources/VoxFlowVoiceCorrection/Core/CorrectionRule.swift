import Foundation

public struct CorrectionRule: Identifiable, Codable, Sendable, Equatable {
    public static let maximumTextLength = 256

    public let id: UUID
    public var targetID: UUID?
    public var original: String
    public var replacement: String
    public var matchPolicy: MatchPolicy
    public var scope: RuleScope
    public var allowedModes: Set<CorrectionInputMode>
    public var lifecycle: RuleLifecycle
    public var source: RuleSource
    public var caseSensitive: Bool
    public var confidence: Double
    public var observedCount: Int
    public var appliedCount: Int
    public var revertedCount: Int
    public var providerID: String?
    public var modelID: String?
    public var language: String?
    public var isEnabled: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var lastAppliedAt: Date?

    public init(
        id: UUID = UUID(),
        targetID: UUID? = nil,
        original: String,
        replacement: String,
        matchPolicy: MatchPolicy = .boundary,
        scope: RuleScope = .global,
        allowedModes: Set<CorrectionInputMode> = [.dictation],
        lifecycle: RuleLifecycle = .active,
        source: RuleSource = .manual,
        caseSensitive: Bool = false,
        confidence: Double = 1,
        observedCount: Int = 0,
        appliedCount: Int = 0,
        revertedCount: Int = 0,
        providerID: String? = nil,
        modelID: String? = nil,
        language: String? = nil,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastAppliedAt: Date? = nil
    ) {
        self.id = id
        self.targetID = targetID
        self.original = original
        self.replacement = replacement
        self.matchPolicy = matchPolicy
        self.scope = scope
        self.allowedModes = allowedModes
        self.lifecycle = lifecycle
        self.source = source
        self.caseSensitive = caseSensitive
        self.confidence = confidence
        self.observedCount = observedCount
        self.appliedCount = appliedCount
        self.revertedCount = revertedCount
        self.providerID = providerID
        self.modelID = modelID
        self.language = language
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAppliedAt = lastAppliedAt
    }

    public func validate() throws {
        let normalizedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedOriginal.isEmpty else {
            throw CorrectionRuleValidationError.emptyOriginal
        }
        guard original != replacement else {
            throw CorrectionRuleValidationError.identicalReplacement
        }
        guard original.count <= Self.maximumTextLength else {
            throw CorrectionRuleValidationError.originalTooLong
        }
        guard replacement.count <= Self.maximumTextLength else {
            throw CorrectionRuleValidationError.replacementTooLong
        }
        guard (0 ... 1).contains(confidence) else {
            throw CorrectionRuleValidationError.invalidConfidence
        }

        if source == .automaticLearning {
            guard matchPolicy == .boundary else {
                throw CorrectionRuleValidationError.automaticLearningRequiresBoundary
            }
            guard !Self.isSingleCJKCharacter(normalizedOriginal) else {
                throw CorrectionRuleValidationError.automaticLearningSingleCJK
            }
            guard !replacement.isEmpty else {
                throw CorrectionRuleValidationError.automaticLearningEmptyReplacement
            }
        }
    }

    private static func isSingleCJKCharacter(_ value: String) -> Bool {
        guard value.count == 1, let scalar = value.unicodeScalars.first else {
            return false
        }

        switch scalar.value {
        case 0x3400 ... 0x4DBF,
             0x4E00 ... 0x9FFF,
             0xF900 ... 0xFAFF,
             0x20000 ... 0x2FA1F:
            return true
        default:
            return false
        }
    }
}

public enum CorrectionRuleValidationError: String, Error, Codable, Sendable, Equatable {
    case emptyOriginal
    case identicalReplacement
    case originalTooLong
    case replacementTooLong
    case invalidConfidence
    case automaticLearningRequiresBoundary
    case automaticLearningSingleCJK
    case automaticLearningEmptyReplacement
}
