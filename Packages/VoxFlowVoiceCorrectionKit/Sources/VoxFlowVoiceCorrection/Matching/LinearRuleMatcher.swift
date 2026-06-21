import Foundation

public struct LinearRuleMatcher: Sendable {
    private let boundaryClassifier: BoundaryClassifier

    public init(boundaryClassifier: BoundaryClassifier = BoundaryClassifier()) {
        self.boundaryClassifier = boundaryClassifier
    }

    public func matches(
        in text: String,
        rules: [CorrectionRule]
    ) -> [CorrectionMatch] {
        rules.flatMap { matches(in: text, rule: $0) }
    }

    private func matches(
        in text: String,
        rule: CorrectionRule
    ) -> [CorrectionMatch] {
        guard !rule.original.isEmpty else {
            return []
        }

        switch rule.matchPolicy {
        case .exact:
            return exactMatch(in: text, rule: rule).map { [$0] } ?? []
        case .boundary, .substring:
            return occurrenceMatches(in: text, rule: rule)
        }
    }

    private func exactMatch(
        in text: String,
        rule: CorrectionRule
    ) -> CorrectionMatch? {
        let trimmedRange = text.startIndex ..< text.endIndex
        guard let firstContent = text[trimmedRange].firstIndex(where: { !$0.isWhitespace }),
              let lastContent = text[trimmedRange].lastIndex(where: { !$0.isWhitespace })
        else {
            return nil
        }

        let contentRange = firstContent ..< text.index(after: lastContent)
        let matchedText = String(text[contentRange])
        guard stringsEqual(matchedText, rule.original, caseSensitive: rule.caseSensitive),
              matchedText != rule.replacement
        else {
            return nil
        }
        return makeMatch(text: text, range: contentRange, rule: rule)
    }

    private func occurrenceMatches(
        in text: String,
        rule: CorrectionRule
    ) -> [CorrectionMatch] {
        var result: [CorrectionMatch] = []
        var searchStart = text.startIndex
        let options: String.CompareOptions = rule.caseSensitive ? [] : [.caseInsensitive]

        while searchStart < text.endIndex,
              let range = text.range(
                  of: rule.original,
                  options: options,
                  range: searchStart ..< text.endIndex,
                  locale: nil
              ) {
            let accepted = rule.matchPolicy == .substring
                || boundaryClassifier.isBoundaryMatch(in: text, range: range)
            if accepted, String(text[range]) != rule.replacement {
                result.append(makeMatch(text: text, range: range, rule: rule))
            }
            searchStart = range.upperBound
        }

        return result
    }

    private func makeMatch(
        text: String,
        range: Range<String.Index>,
        rule: CorrectionRule
    ) -> CorrectionMatch {
        let utf16Range = NSRange(range, in: text)
        return CorrectionMatch(
            rule: rule,
            range: CorrectionTextRange(location: utf16Range.location, length: utf16Range.length),
            matchedText: String(text[range])
        )
    }

    private func stringsEqual(
        _ lhs: String,
        _ rhs: String,
        caseSensitive: Bool
    ) -> Bool {
        if caseSensitive {
            return lhs == rhs
        }
        return lhs.compare(rhs, options: [.caseInsensitive], locale: nil) == .orderedSame
    }
}
