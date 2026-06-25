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
        let original = trimLearningBoundaryPunctuation(
            original.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let edited = trimLearningBoundaryPunctuation(
            edited.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if let tokenAlignedPairs = extractTokenAlignedPairs(original: original, edited: edited) {
            return tokenAlignedPairs
        }
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

        if originalTokens.count == 1,
           editedTokens.count == 1,
           (cjkScalarCount(in: original) > 3 || cjkScalarCount(in: edited) > 3) {
            if isShortCJKPhraseToLatinName(original: original, edited: edited) {
                return true
            }
            return false
        }

        return !isPunctuationOnly(original) && !isPunctuationOnly(edited)
    }

    private func isShortCJKPhraseToLatinName(
        original: String,
        edited: String
    ) -> Bool {
        let originalCJKCount = cjkScalarCount(in: original)
        let editedCJKCount = cjkScalarCount(in: edited)
        let cjkCount = max(originalCJKCount, editedCJKCount)
        guard (2...5).contains(cjkCount) else {
            return false
        }

        if originalCJKCount > 0, editedCJKCount == 0 {
            return containsASCIILetterOrDigit(edited)
        }
        if editedCJKCount > 0, originalCJKCount == 0 {
            return containsASCIILetterOrDigit(original)
        }
        return false
    }

    private func extractTokenAlignedPairs(
        original: String,
        edited: String,
        maxSuggestions: Int = 3
    ) -> [LearnedCorrectionPair]? {
        let originalTokens = learningTokens(in: original)
        let editedTokens = learningTokens(in: edited)
        guard maxSuggestions > 0,
              !originalTokens.isEmpty,
              originalTokens.count == editedTokens.count
        else {
            return nil
        }

        var pairs: [LearnedCorrectionPair] = []
        var replacementsByOriginal: [String: String] = [:]
        for (originalToken, editedToken) in zip(originalTokens, editedTokens) where originalToken != editedToken {
            guard isHighConfidenceTokenSubstitution(original: originalToken, edited: editedToken) else {
                return []
            }

            let originalKey = originalToken.lowercased()
            let editedKey = editedToken.lowercased()
            if let existing = replacementsByOriginal[originalKey] {
                guard existing == editedKey else {
                    return []
                }
                continue
            }

            replacementsByOriginal[originalKey] = editedKey
            pairs.append(LearnedCorrectionPair(original: originalToken, replacement: editedToken))
            guard pairs.count <= maxSuggestions else {
                return []
            }
        }

        return pairs
    }

    private func isHighConfidenceTokenSubstitution(
        original: String,
        edited: String
    ) -> Bool {
        guard !original.isEmpty,
              !edited.isEmpty,
              original != edited,
              original.caseInsensitiveCompare(edited) != .orderedSame,
              !isPunctuationOnly(original),
              !isPunctuationOnly(edited)
        else {
            return false
        }

        if cjkScalarCount(in: original) > 3 || cjkScalarCount(in: edited) > 3 {
            return isShortCJKPhraseToLatinName(original: original, edited: edited)
        }
        return true
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

    private func learningTokens(in text: String) -> [String] {
        text.split { character in
            character.isWhitespace || character.unicodeScalars.allSatisfy {
                CharacterSet.punctuationCharacters.contains($0) ||
                    CharacterSet.symbols.contains($0)
            }
        }.map(String.init)
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

    private func containsASCIILetterOrDigit(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (65...90).contains(Int($0.value)) ||
                (97...122).contains(Int($0.value)) ||
                (48...57).contains(Int($0.value))
        }
    }

    private func trimLearningBoundaryPunctuation(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:，。！？；：、"))
    }

    private func cjkScalarCount(in text: String) -> Int {
        text.unicodeScalars.filter {
            (0x4E00...0x9FFF).contains(Int($0.value))
        }.count
    }
}
