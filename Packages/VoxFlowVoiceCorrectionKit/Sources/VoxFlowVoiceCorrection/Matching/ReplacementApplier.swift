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

        let descendingMatches = matches.sorted {
            if $0.range.location != $1.range.location {
                return $0.range.location > $1.range.location
            }
            return $0.range.length > $1.range.length
        }

        for match in descendingMatches {
            let nsRange = NSRange(location: match.range.location, length: match.range.length)
            guard let range = Range(nsRange, in: correctedText) else {
                warnings.append(.processingFailed)
                continue
            }

            correctedText.replaceSubrange(range, with: match.rule.replacement)
            events.append(
                CorrectionEvent(
                    ruleID: match.rule.id,
                    original: match.matchedText,
                    replacement: match.rule.replacement,
                    range: match.range,
                    scope: match.rule.scope,
                    source: match.rule.source
                )
            )
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
