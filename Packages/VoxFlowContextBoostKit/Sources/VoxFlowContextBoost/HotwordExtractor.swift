import Foundation

public struct NamedEntityCandidate: Sendable, Codable, Hashable {
    public let text: String
    public let kind: NamedEntityKind

    public init(text: String, kind: NamedEntityKind) {
        self.text = text
        self.kind = kind
    }
}

public enum NamedEntityKind: String, Sendable, Codable, Hashable {
    case person
    case place
    case organization
    case other
}

public struct HotwordExtractor: Sendable {
    private let maxCharacters: Int
    private let maxCandidates: Int
    private let ttlSeconds: TimeInterval
    private let rakeExtractor: RakeKeywordExtractor

    public init(
        maxCharacters: Int = 8_000,
        maxCandidates: Int = 200,
        ttlSeconds: TimeInterval = 120,
        rakeExtractor: RakeKeywordExtractor = RakeKeywordExtractor()
    ) {
        self.maxCharacters = max(0, maxCharacters)
        self.maxCandidates = max(0, maxCandidates)
        self.ttlSeconds = ttlSeconds
        self.rakeExtractor = rakeExtractor
    }

    public func extract(
        from text: String,
        namedEntities: [NamedEntityCandidate],
        now: Date = Date()
    ) -> [TemporaryHotword] {
        let limited = String(text.prefix(maxCharacters))
        var candidates: [String: TemporaryHotword] = [:]

        for entity in namedEntities {
            addCandidate(
                entity.text,
                source: .ocrNamedEntity,
                reason: "named_entity:\(entity.kind.rawValue)",
                weight: 8,
                now: now,
                candidates: &candidates
            )
        }

        for phrase in rakeExtractor.extractPhrases(from: limited) {
            addCandidate(
                phrase,
                source: .ocrKeyphrase,
                reason: "rake_phrase",
                weight: rakeWeight(for: phrase),
                now: now,
                candidates: &candidates
            )
        }

        for token in extractShapeCandidates(from: limited) {
            addCandidate(
                token,
                source: .ocrShape,
                reason: "shape_candidate",
                weight: 7,
                now: now,
                candidates: &candidates
            )
        }

        for phrase in extractChinesePhrases(from: limited) {
            addCandidate(
                phrase,
                source: .ocrKeyphrase,
                reason: "short_chinese_phrase",
                weight: 4,
                now: now,
                candidates: &candidates
            )
        }

        return Array(candidates.values)
            .sorted {
                if $0.score == $1.score {
                    return $0.text.localizedCaseInsensitiveCompare($1.text) == .orderedAscending
                }
                return $0.score > $1.score
            }
            .prefix(maxCandidates)
            .map { $0 }
    }

    private func addCandidate(
        _ rawText: String,
        source: HotwordSource,
        reason: String,
        weight: Double,
        now: Date,
        candidates: inout [String: TemporaryHotword]
    ) {
        let text = clean(rawText)
        guard shouldKeep(text) else { return }
        let normalized = normalize(text)
        let evidence = HotwordEvidence(reason: reason, weight: weight)
        if let existing = candidates[normalized] {
            candidates[normalized] = TemporaryHotword(
                text: existing.text,
                normalizedText: existing.normalizedText,
                score: existing.score + weight,
                source: existing.source,
                evidence: existing.evidence + [evidence],
                expiresAt: existing.expiresAt
            )
            return
        }
        candidates[normalized] = TemporaryHotword(
            text: text,
            normalizedText: normalized,
            score: weight,
            source: source,
            evidence: [evidence],
            expiresAt: now.addingTimeInterval(ttlSeconds)
        )
    }

    private func extractShapeCandidates(from text: String) -> [String] {
        guard let regex = Self.shapeCandidateRegex else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    private func extractChinesePhrases(from text: String) -> [String] {
        guard let regex = Self.shortChinesePhraseRegex else { return [] }
        var phrases: [String] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            for segment in chineseSegments(in: trimmedLine) {
                let range = NSRange(segment.startIndex..<segment.endIndex, in: segment)
                guard regex.firstMatch(in: segment, range: range) != nil else { continue }
                phrases.append(segment)
            }
        }

        return phrases
    }

    private func chineseSegments(in line: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        return line.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func rakeWeight(for phrase: String) -> Double {
        let words = phrase.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return 5 }
        if words.allSatisfy(isTitlecaseWord) {
            return 6
        }
        return 5
    }

    private func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private func shouldKeep(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard !Self.genericUILabels.contains(text) else { return false }
        guard text.count <= 60 else { return false }
        if text.count == 1 { return false }
        if text.contains(" ") {
            return text.split(separator: " ").count <= 4
        }
        return true
    }

    private func isTitlecaseWord(_ word: String) -> Bool {
        guard let first = word.unicodeScalars.first,
              CharacterSet.uppercaseLetters.contains(first) else {
            return false
        }
        return word.dropFirst().contains { $0.isLowercase }
    }

    private static let genericUILabels: Set<String> = [
        "取消", "确定", "设置", "保存", "关闭", "返回", "下一步", "完成",
        "Cancel", "OK", "Settings", "Save", "Close", "Back", "Next", "Done"
    ]

    private static let shapeCandidateRegex = try? NSRegularExpression(
        pattern: #"[A-Za-z][A-Za-z0-9]*(?:[._-][A-Za-z0-9]+)+|[A-Z]{2,}[A-Za-z0-9]*|[A-Z][a-z]+(?:[A-Z][A-Za-z0-9]+)+"#
    )

    private static let shortChinesePhraseRegex = try? NSRegularExpression(
        pattern: #"^[\p{Han}]{2,8}$"#
    )
}
