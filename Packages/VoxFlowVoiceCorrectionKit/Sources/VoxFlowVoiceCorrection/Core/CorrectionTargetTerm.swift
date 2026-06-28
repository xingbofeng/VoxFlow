import Foundation

public struct CorrectionTargetTerm: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var text: String
    public var normalizedText: String
    public var scope: RuleScope
    public var lifecycle: RuleLifecycle
    public var source: RuleSource
    public var observedCount: Int
    public var appliedCount: Int
    public var revertedCount: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var lastAppliedAt: Date?

    /// Non-overlapping occurrence count of this hotword in final output text.
    public var hitCount: Int

    /// When true, this hotword is blocklisted and auto-learning must not re-add it.
    public var isBlocklisted: Bool

    /// Timestamp of the most recent hit in final output text.
    public var lastHitAt: Date?

    public init(
        id: UUID = UUID(),
        text: String,
        normalizedText: String? = nil,
        scope: RuleScope = .global,
        lifecycle: RuleLifecycle = .active,
        source: RuleSource = .manual,
        observedCount: Int = 0,
        appliedCount: Int = 0,
        revertedCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastAppliedAt: Date? = nil,
        hitCount: Int = 0,
        isBlocklisted: Bool = false,
        lastHitAt: Date? = nil
    ) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.text = trimmedText
        self.normalizedText = normalizedText ?? Self.normalize(trimmedText)
        self.scope = scope
        self.lifecycle = lifecycle
        self.source = source
        self.observedCount = observedCount
        self.appliedCount = appliedCount
        self.revertedCount = revertedCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAppliedAt = lastAppliedAt
        self.hitCount = hitCount
        self.isBlocklisted = isBlocklisted
        self.lastHitAt = lastHitAt
    }

    public func validate() throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CorrectionTargetTermValidationError.emptyText
        }
        guard text.count <= CorrectionRule.maximumTextLength else {
            throw CorrectionTargetTermValidationError.textTooLong
        }
    }

    public static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

public enum CorrectionTargetTermValidationError: String, Error, Codable, Sendable, Equatable {
    case emptyText
    case textTooLong
}
