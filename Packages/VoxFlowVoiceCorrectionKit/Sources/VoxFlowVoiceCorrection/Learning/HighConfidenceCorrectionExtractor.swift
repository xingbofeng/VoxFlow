import Foundation

public struct LearnedCorrectionPair: Codable, Sendable, Equatable {
    public let original: String
    public let replacement: String

    public init(original: String, replacement: String) {
        self.original = original
        self.replacement = replacement
    }
}

public struct HighConfidenceCorrectionExtractor: Sendable {
    public init() {}

    public func extract(
        original: String,
        edited: String
    ) -> [LearnedCorrectionPair] {
        let original = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let edited = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isHighConfidenceSubstitution(original: original, edited: edited) else {
            return []
        }
        return [LearnedCorrectionPair(original: original, replacement: edited)]
    }

    public func extract(
        insertedText: String,
        baselineText: String,
        editedText: String,
        appliedCorrectionRanges: [CorrectionTextRange] = []
    ) -> [LearnedCorrectionPair] {
        let insertedText = insertedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !insertedText.isEmpty,
              let changed = changedRanges(from: baselineText, to: editedText),
              !changed.baseline.isEmpty,
              !changed.edited.isEmpty,
              let insertedRange = uniqueInsertedRange(
                containing: changed.baseline,
                insertedText: insertedText,
                in: baselineText
              ),
              contains(outer: insertedRange, inner: changed.baseline),
              !overlapsAppliedCorrection(changed.baseline, in: baselineText, appliedCorrectionRanges)
        else {
            return []
        }

        let baselineTokenRange = expandedTokenRange(in: baselineText, around: changed.baseline)
        guard contains(outer: insertedRange, inner: baselineTokenRange) else {
            return []
        }

        let editedTokenRange = expandedTokenRange(in: editedText, around: changed.edited)
        return extract(
            original: String(baselineText[baselineTokenRange]),
            edited: String(editedText[editedTokenRange])
        )
    }

    private func isHighConfidenceSubstitution(
        original: String,
        edited: String
    ) -> Bool {
        guard !original.isEmpty,
              !edited.isEmpty,
              original != edited,
              original.caseInsensitiveCompare(edited) != .orderedSame
        else {
            return false
        }

        let originalTokens = tokens(in: original)
        let editedTokens = tokens(in: edited)
        guard !originalTokens.isEmpty,
              !editedTokens.isEmpty,
              originalTokens.count <= 3,
              editedTokens.count <= 3,
              Set(originalTokens.map { $0.lowercased() }).count == originalTokens.count,
              Set(editedTokens.map { $0.lowercased() }).count == editedTokens.count
        else {
            return false
        }

        guard !isTokenPrefix(originalTokens, of: editedTokens),
              !isTokenPrefix(editedTokens, of: originalTokens)
        else {
            return false
        }

        return !isPunctuationOnly(original) && !isPunctuationOnly(edited)
    }

    private func changedRanges(
        from baselineText: String,
        to editedText: String
    ) -> (baseline: Range<String.Index>, edited: Range<String.Index>)? {
        guard baselineText != editedText else {
            return nil
        }

        var baselinePrefix = baselineText.startIndex
        var editedPrefix = editedText.startIndex
        while baselinePrefix < baselineText.endIndex,
              editedPrefix < editedText.endIndex,
              baselineText[baselinePrefix] == editedText[editedPrefix] {
            baselineText.formIndex(after: &baselinePrefix)
            editedText.formIndex(after: &editedPrefix)
        }

        var baselineSuffix = baselineText.endIndex
        var editedSuffix = editedText.endIndex
        while baselineSuffix > baselinePrefix,
              editedSuffix > editedPrefix {
            let previousBaseline = baselineText.index(before: baselineSuffix)
            let previousEdited = editedText.index(before: editedSuffix)
            guard baselineText[previousBaseline] == editedText[previousEdited] else {
                break
            }
            baselineSuffix = previousBaseline
            editedSuffix = previousEdited
        }

        return (baselinePrefix ..< baselineSuffix, editedPrefix ..< editedSuffix)
    }

    private func uniqueInsertedRange(
        containing changedRange: Range<String.Index>,
        insertedText: String,
        in baselineText: String
    ) -> Range<String.Index>? {
        var matches: [Range<String.Index>] = []
        var searchStart = baselineText.startIndex
        while searchStart < baselineText.endIndex,
              let range = baselineText.range(of: insertedText, range: searchStart ..< baselineText.endIndex) {
            if contains(outer: range, inner: changedRange) {
                matches.append(range)
            }
            searchStart = range.upperBound
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private func expandedTokenRange(
        in text: String,
        around range: Range<String.Index>
    ) -> Range<String.Index> {
        var lowerBound = range.lowerBound
        while lowerBound > text.startIndex {
            let previous = text.index(before: lowerBound)
            guard !text[previous].isWhitespace else {
                break
            }
            lowerBound = previous
        }

        var upperBound = range.upperBound
        while upperBound < text.endIndex, !text[upperBound].isWhitespace {
            text.formIndex(after: &upperBound)
        }
        return lowerBound ..< upperBound
    }

    private func overlapsAppliedCorrection(
        _ range: Range<String.Index>,
        in text: String,
        _ appliedRanges: [CorrectionTextRange]
    ) -> Bool {
        let changed = NSRange(range, in: text)
        return appliedRanges.contains {
            changed.location < $0.location + $0.length &&
                $0.location < changed.location + changed.length
        }
    }

    private func contains(
        outer: Range<String.Index>,
        inner: Range<String.Index>
    ) -> Bool {
        inner.lowerBound >= outer.lowerBound && inner.upperBound <= outer.upperBound
    }

    private func tokens(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private func isTokenPrefix(_ prefix: [String], of values: [String]) -> Bool {
        guard prefix.count < values.count else {
            return false
        }
        return zip(prefix, values).allSatisfy { $0.0.caseInsensitiveCompare($0.1) == .orderedSame }
    }

    private func isPunctuationOnly(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0) ||
                CharacterSet.symbols.contains($0) ||
                CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }
}
