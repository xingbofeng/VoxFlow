import Foundation

public struct HotwordRanker: Sendable {
    public static let defaultLimit = 8
    public static let hardLimit = 12

    public init() {}

    public func rank(
        _ hotwords: [TemporaryHotword],
        limit: Int = Self.defaultLimit
    ) -> [TemporaryHotword] {
        let cappedLimit = min(max(0, limit), Self.hardLimit)
        let merged = mergeDuplicates(hotwords)
        return Array(
            merged
                .sorted(by: Self.sortHotwords)
                .prefix(cappedLimit)
        )
    }

    private func mergeDuplicates(_ hotwords: [TemporaryHotword]) -> [TemporaryHotword] {
        var byNormalizedText: [String: TemporaryHotword] = [:]
        for hotword in hotwords {
            guard let existing = byNormalizedText[hotword.normalizedText] else {
                byNormalizedText[hotword.normalizedText] = hotword
                continue
            }
            let preferredText = preferredDisplayText(existing.text, hotword.text)
            byNormalizedText[hotword.normalizedText] = TemporaryHotword(
                text: preferredText,
                normalizedText: hotword.normalizedText,
                score: existing.score + hotword.score,
                source: hotword.score >= existing.score ? hotword.source : existing.source,
                evidence: existing.evidence + hotword.evidence,
                expiresAt: max(existing.expiresAt, hotword.expiresAt)
            )
        }
        return Array(byNormalizedText.values)
    }

    private func preferredDisplayText(_ lhs: String, _ rhs: String) -> String {
        if lhs.count == rhs.count {
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending ? lhs : rhs
        }
        return lhs.count < rhs.count ? lhs : rhs
    }

    private static func sortHotwords(_ lhs: TemporaryHotword, _ rhs: TemporaryHotword) -> Bool {
        if lhs.score == rhs.score {
            return lhs.text.localizedCaseInsensitiveCompare(rhs.text) == .orderedAscending
        }
        return lhs.score > rhs.score
    }
}
