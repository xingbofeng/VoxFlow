import Foundation

public struct ReplacementApplier: Sendable {
    public init() {}

    public func apply(
        rawText: String,
        matches: [CorrectionMatch]
    ) -> CorrectionResult {
        var correctedText = rawText
        var events: [CorrectionEvent] = []
        var warnings: [CorrectionWarning] = []

        var validMatches: [CorrectionMatch] = []
        for match in matches {
            let nsRange = NSRange(location: match.range.location, length: match.range.length)
            guard Range(nsRange, in: rawText) != nil else {
                warnings.append(.processingFailed)
                continue
            }
            validMatches.append(match)
        }

        var locationDelta = 0
        let ascendingMatches = validMatches.sorted {
            if $0.range.location != $1.range.location {
                return $0.range.location < $1.range.location
            }
            return $0.range.length > $1.range.length
        }
        for match in ascendingMatches {
            let correctedRange = CorrectionTextRange(
                location: match.range.location + locationDelta,
                length: match.rule.replacement.utf16.count
            )
            events.append(
                CorrectionEvent(
                    ruleID: match.rule.id,
                    original: match.matchedText,
                    replacement: match.rule.replacement,
                    range: correctedRange,
                    scope: match.rule.scope,
                    source: match.rule.source
                )
            )
            locationDelta += match.rule.replacement.utf16.count - match.range.length
        }

        let descendingMatches = validMatches.sorted {
            if $0.range.location != $1.range.location {
                return $0.range.location > $1.range.location
            }
            return $0.range.length > $1.range.length
        }

        for match in descendingMatches {
            let nsRange = NSRange(location: match.range.location, length: match.range.length)
            let range = Range(nsRange, in: correctedText)!
            correctedText.replaceSubrange(range, with: match.rule.replacement)
        }

        events.sort { $0.range.location < $1.range.location }
        return CorrectionResult(
            rawText: rawText,
            correctedText: correctedText,
            events: events,
            warnings: warnings
        )
    }
}
