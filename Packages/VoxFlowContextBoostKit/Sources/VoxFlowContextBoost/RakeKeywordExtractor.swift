import Foundation

public struct RakeKeywordExtractor: Sendable {
    private let maxPhraseWords: Int
    private let maxPhrases: Int
    private let stopwords: Set<String>

    public init(
        maxPhraseWords: Int = 5,
        maxPhrases: Int = 80,
        stopwords: Set<String> = Self.defaultStopwords
    ) {
        self.maxPhraseWords = max(1, maxPhraseWords)
        self.maxPhrases = max(0, maxPhrases)
        self.stopwords = stopwords
    }

    public func extractPhrases(from text: String) -> [String] {
        let phrases = candidatePhrases(from: text)
        guard !phrases.isEmpty else { return [] }

        var frequency: [String: Double] = [:]
        var degree: [String: Double] = [:]
        for phrase in phrases {
            let words = normalizedWords(in: phrase)
            let phraseDegree = Double(max(words.count - 1, 0))
            for word in words {
                frequency[word, default: 0] += 1
                degree[word, default: 0] += phraseDegree
            }
        }

        for (word, count) in frequency {
            degree[word, default: 0] += count
        }

        let scored = phrases.compactMap { phrase -> (text: String, score: Double)? in
            let words = normalizedWords(in: phrase)
            guard !words.isEmpty else { return nil }
            let score = words.reduce(0.0) { partial, word in
                partial + ((degree[word] ?? 0) / max(frequency[word] ?? 1, 1))
            }
            return (phrase.joined(separator: " "), score)
        }

        var seen: Set<String> = []
        return scored
            .sorted {
                if $0.score == $1.score {
                    return $0.text.localizedCaseInsensitiveCompare($1.text) == .orderedAscending
                }
                return $0.score > $1.score
            }
            .compactMap { phrase, _ in
                let key = normalize(phrase)
                guard !seen.contains(key) else { return nil }
                seen.insert(key)
                return phrase
            }
            .prefix(maxPhrases)
            .map { $0 }
    }

    private func candidatePhrases(from text: String) -> [[String]] {
        var phrases: [[String]] = []
        for line in text.components(separatedBy: .newlines) {
            var current: [String] = []
            var lineTokens = tokens(in: line)
            if let first = lineTokens.first,
               Self.lineLeadingActionWords.contains(normalize(first)) {
                lineTokens.removeFirst()
            }
            for token in lineTokens {
                let normalized = normalize(token)
                if normalized.isEmpty || stopwords.contains(normalized) {
                    appendPhrase(current, to: &phrases)
                    current.removeAll()
                } else {
                    current.append(token)
                }
            }
            appendPhrase(current, to: &phrases)
        }
        return phrases
    }

    private func appendPhrase(_ phrase: [String], to phrases: inout [[String]]) {
        let cleaned = phrase.map(cleanDisplayToken).filter { !$0.isEmpty }
        guard cleaned.count >= 2 else { return }
        let capped = Array(cleaned.prefix(maxPhraseWords))
        phrases.append(capped)

        if capped.count > 3 {
            phrases.append(Array(capped.prefix(3)))
        }
        let titlecaseRun = leadingTitlecaseRun(in: capped)
        if titlecaseRun.count >= 2 {
            phrases.append(titlecaseRun)
            phrases.append(Array(titlecaseRun.prefix(2)))
        }
    }

    private func normalizedWords(in phrase: [String]) -> [String] {
        phrase.map(normalize).filter { !$0.isEmpty }
    }

    private func tokens(in line: String) -> [String] {
        line.split { character in
            !(character.isLetter || character.isNumber || character == "-" || character == "_" || character == ".")
        }
        .map(String.init)
    }

    private func normalize(_ text: String) -> String {
        cleanDisplayToken(text)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private func cleanDisplayToken(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func leadingTitlecaseRun(in words: [String]) -> [String] {
        var result: [String] = []
        for word in words {
            guard isTitlecaseWord(word) else {
                break
            }
            result.append(word)
        }
        return result
    }

    private func isTitlecaseWord(_ word: String) -> Bool {
        guard let first = word.unicodeScalars.first,
              CharacterSet.uppercaseLetters.contains(first) else {
            return false
        }
        return word.dropFirst().contains { $0.isLowercase }
    }

    public static let defaultStopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "before", "by", "for", "from",
        "in", "is", "of", "on", "or", "the", "to", "with", "about"
    ]

    private static let lineLeadingActionWords: Set<String> = [
        "check", "compare", "follow", "open", "review", "sync", "update"
    ]
}
