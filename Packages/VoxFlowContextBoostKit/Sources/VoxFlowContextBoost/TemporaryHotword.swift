import Foundation

public struct TemporaryHotword: Sendable, Codable, Hashable {
    public let text: String
    public let normalizedText: String
    public let score: Double
    public let source: HotwordSource
    public let evidence: [HotwordEvidence]
    public let expiresAt: Date

    public init(
        text: String,
        normalizedText: String,
        score: Double,
        source: HotwordSource,
        evidence: [HotwordEvidence],
        expiresAt: Date
    ) {
        self.text = text
        self.normalizedText = normalizedText
        self.score = score
        self.source = source
        self.evidence = evidence
        self.expiresAt = expiresAt
    }
}

public enum HotwordSource: String, Sendable, Codable {
    case ocrKeyphrase
    case ocrNamedEntity
    case ocrShape
    case activeApp
    case windowTitle
}

public struct HotwordEvidence: Sendable, Codable, Hashable {
    public let reason: String
    public let weight: Double

    public init(reason: String, weight: Double) {
        self.reason = reason
        self.weight = weight
    }
}

public enum HotwordScope: Sendable, Codable, Hashable {
    case global
    case application(bundleID: String)
    case window(bundleID: String, windowID: String)
}
