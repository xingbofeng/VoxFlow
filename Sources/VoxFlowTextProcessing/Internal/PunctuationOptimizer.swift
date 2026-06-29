import Foundation

/// Punctuation optimization: sentence-ending punctuation completion, half-width
/// → full-width CJK punctuation normalization, and consecutive punctuation
/// collapse. Supports word and CJK character thresholds to decide whether a
/// segment is CJK context (for half→full conversion).
///
/// Protected regions (URLs, paths, emails, versions, backtick code spans,
/// identifiers) are masked before processing to prevent punctuation inside
/// code-like content from being converted or modified.
public enum PunctuationOptimizer {
    public struct Context: Sendable, Equatable {
        public let cjkThreshold: Int
        public let wordThreshold: Int
        public init(cjkThreshold: Int = 3, wordThreshold: Int = 4) {
            self.cjkThreshold = cjkThreshold
            self.wordThreshold = wordThreshold
        }
    }

    public static func process(_ text: String, context: Context = Context()) -> String {
        // Mask protected regions to prevent punctuation inside URLs, paths,
        // versions, code spans, and identifiers from being converted.
        let protected = CJKLatinSpacer.ProtectedRegions.mask(text)
        var result = protected.masked
        let cjkContext = isCJKContext(result, threshold: context.cjkThreshold)
        if cjkContext {
            result = convertHalfWidthToFullWidth(result)
        }
        result = collapseConsecutivePunctuation(result)
        result = completeSentenceEndingPunctuation(
            result,
            cjkContext: cjkContext,
            wordThreshold: context.wordThreshold
        )
        return CJKLatinSpacer.ProtectedRegions.unmask(result, regions: protected.regions)
    }

    /// Returns true when the text has at least `threshold` CJK characters.
    static func isCJKContext(_ text: String, threshold: Int) -> Bool {
        var cjkCount = 0
        for scalar in text.unicodeScalars {
            if isCJK(scalar) {
                cjkCount += 1
                if cjkCount >= threshold { return true }
            }
        }
        return cjkCount >= threshold
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        // CJK Unified Ideographs, extensions A/B, etc.
        let value = scalar.value
        return (0x4E00...0x9FFF).contains(value)
            || (0x3400...0x4DBF).contains(value)
            || (0x20000...0x2A6DF).contains(value)
    }

    /// Convert half-width punctuation to full-width in CJK context.
    static func convertHalfWidthToFullWidth(_ text: String) -> String {
        var result = text
        let mapping: [(String, String)] = [
            (",", "，"),
            (".", "。"),
            ("!", "！"),
            ("?", "？"),
            (";", "；"),
            (":", "："),
            ("(", "（"),
            (")", "）"),
        ]
        for (half, full) in mapping {
            // Only replace when adjacent to CJK characters, to avoid
            // converting punctuation inside English/code segments.
            result = replacePunctuationIfCJKAdjacent(result, half: half, full: full)
        }
        return result
    }

    private static func replacePunctuationIfCJKAdjacent(_ text: String, half: String, full: String) -> String {
        var output = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if String(ch) == half {
                let prevIsCJK = i > 0 && isCJKChar(chars[i - 1])
                let nextIsCJK = i < chars.count - 1 && isCJKChar(chars[i + 1])
                if prevIsCJK || nextIsCJK {
                    output += full
                } else {
                    output += String(ch)
                }
            } else {
                output += String(ch)
            }
            i += 1
        }
        return output
    }

    private static func isCJKChar(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        return isCJK(scalar)
    }

    /// Collapse repeated punctuation: "。。。" → "。", "！！！" → "！".
    static func collapseConsecutivePunctuation(_ text: String) -> String {
        let pattern = "([，。！？,\\.!?；;：:])\\1{2,}"
        guard let regex = cachedRegex(pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1$1")
    }

    /// Add a sentence-ending punctuation if the text has none and looks like a
    /// complete sentence (CJK or English). Conservative: only adds 。or . .
    ///
    /// `wordThreshold` gates English-context completion: short English fragments
    /// below the threshold are not auto-terminated, avoiding adding `.` to
    /// single tokens or short labels that look like sentences but aren't.
    static func completeSentenceEndingPunctuation(
        _ text: String,
        cjkContext: Bool,
        wordThreshold: Int
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        guard let lastChar = trimmed.last else { return text }
        let endingSet = CharacterSet(charactersIn: "。.！？!?…")
        if lastChar.unicodeScalars.allSatisfy({ endingSet.contains($0) }) {
            return text
        }
        // Only add ending punctuation for reasonably complete sentences.
        // Avoid adding to code snippets, URLs, or short fragments.
        if cjkContext || isCJKContext(trimmed, threshold: 2) {
            return text + "。"
        }
        // English: only add if it looks like a sentence (has a space, ends with
        // a letter, and meets the word threshold).
        guard trimmed.contains(" ") && lastChar.isLetter else { return text }
        let wordCount = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        guard wordCount >= wordThreshold else { return text }
        return text + "."
    }

    private static let regexCache = PunctuationRegexCache()

    private static func cachedRegex(_ pattern: String) -> NSRegularExpression? {
        regexCache.regex(for: pattern)
    }
}

private final class PunctuationRegexCache: @unchecked Sendable {
    private var values: [String: NSRegularExpression] = [:]
    private let lock = NSLock()

    func regex(for pattern: String) -> NSRegularExpression? {
        lock.lock()
        if let cached = values[pattern] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let compiled = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        lock.lock()
        values[pattern] = compiled
        lock.unlock()
        return compiled
    }
}
