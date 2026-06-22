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
        let finder = OccurrenceFinder(pattern: rule.original, caseSensitive: rule.caseSensitive)

        while searchStart < text.endIndex,
              let range = finder.nextRange(
                  in: text,
                  searchRange: searchStart ..< text.endIndex,
                  options: options
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

private struct OccurrenceFinder {
    let pattern: String
    let caseSensitive: Bool
    private let compactPattern: String
    private let allowsFlexibleWhitespace: Bool

    init(pattern: String, caseSensitive: Bool) {
        self.pattern = pattern
        self.caseSensitive = caseSensitive
        compactPattern = pattern.filter { !$0.isWhitespace }
        allowsFlexibleWhitespace = pattern.contains(where: \.isWhitespace) && !compactPattern.isEmpty
    }

    func nextRange(
        in text: String,
        searchRange: Range<String.Index>,
        options: String.CompareOptions
    ) -> Range<String.Index>? {
        if allowsFlexibleWhitespace,
           let flexibleRange = flexibleWhitespaceRange(in: text, searchRange: searchRange) {
            return flexibleRange
        }
        return text.range(
            of: pattern,
            options: options,
            range: searchRange,
            locale: nil
        )
    }

    private func flexibleWhitespaceRange(
        in text: String,
        searchRange: Range<String.Index>
    ) -> Range<String.Index>? {
        var index = searchRange.lowerBound
        while index < searchRange.upperBound {
            if let range = matchCompactPattern(in: text, from: index, upperBound: searchRange.upperBound) {
                return range
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func matchCompactPattern(
        in text: String,
        from start: String.Index,
        upperBound: String.Index
    ) -> Range<String.Index>? {
        var textIndex = start
        var patternIndex = compactPattern.startIndex
        var matchedStart: String.Index?
        var matchedEnd: String.Index?

        while patternIndex < compactPattern.endIndex {
            while textIndex < upperBound, text[textIndex].isWhitespace {
                textIndex = text.index(after: textIndex)
            }
            guard textIndex < upperBound,
                  charactersEqual(text[textIndex], compactPattern[patternIndex]) else {
                return nil
            }

            if matchedStart == nil {
                matchedStart = textIndex
            }
            matchedEnd = text.index(after: textIndex)
            textIndex = text.index(after: textIndex)
            patternIndex = compactPattern.index(after: patternIndex)
        }

        guard let matchedStart, let matchedEnd else { return nil }
        return matchedStart ..< matchedEnd
    }

    private func charactersEqual(_ lhs: Character, _ rhs: Character) -> Bool {
        if caseSensitive {
            return lhs == rhs
        }
        return String(lhs).compare(String(rhs), options: [.caseInsensitive], locale: nil) == .orderedSame
    }
}
