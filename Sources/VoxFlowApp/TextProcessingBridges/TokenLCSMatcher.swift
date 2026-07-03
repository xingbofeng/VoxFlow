import Foundation

/// UI-independent pure helper that owns the token LCS algorithm backbone.
///
/// The home transcript comparison presentation uses this helper for token
/// diffing. Presentation types (`TextDiffSegment`, similarity percent
/// rounding) stay in `TextComparisonPresentation`; this helper only knows
/// about tokens and LCS cells.
struct TokenLCSMatcher {
    /// Tokenizes text into LCS tokens.
    ///
    /// Rules (mirrors the original `TokenLCSDiffEngine`):
    /// - ASCII letters and digits group into a single token (e.g. `Qwen3`, `42`).
    /// - Each CJK character (Han, Hiragana, Katakana, Hangul) is its own token.
    /// - Each punctuation, symbol, or whitespace character is its own token.
    static func tokenize(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        var tokens: [String] = []
        var current = ""
        for scalar in text.unicodeScalars {
            if isASCIILetterOrDigit(scalar) {
                current.unicodeScalars.append(scalar)
                continue
            }
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
            tokens.append(String(scalar))
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    /// Computes the LCS table cell length for two token arrays and returns
    /// the count of tokens shared in their longest common subsequence.
    static func lcsLength(_ source: [String], _ processed: [String]) -> Int {
        let m = source.count
        let n = processed.count
        if m == 0 || n == 0 { return 0 }
        var prev = Array(repeating: 0, count: n + 1)
        var curr = Array(repeating: 0, count: n + 1)
        for i in 1...m {
            for j in 1...n {
                if source[i - 1] == processed[j - 1] {
                    curr[j] = prev[j - 1] + 1
                } else {
                    curr[j] = max(prev[j], curr[j - 1])
                }
            }
            swap(&prev, &curr)
            curr = Array(repeating: 0, count: n + 1)
        }
        return prev[n]
    }

    /// Builds the LCS table and walks it back into ordered segments of equal
    /// / inserted / deleted tokens. Adjacent segments are *not* coalesced —
    /// callers compose `TextDiffSegment`s or token strings as needed.
    enum Segment: Equatable, Sendable {
        case equal(String)
        case inserted(String)
        case deleted(String)
    }

    static func lcsSegments(source: [String], processed: [String]) -> [Segment] {
        let m = source.count
        let n = processed.count
        if m == 0 && n == 0 { return [] }
        if m == 0 { return [.inserted(processed.joined())] }
        if n == 0 { return [.deleted(source.joined())] }

        var table = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if source[i - 1] == processed[j - 1] {
                    table[i][j] = table[i - 1][j - 1] + 1
                } else {
                    table[i][j] = max(table[i - 1][j], table[i][j - 1])
                }
            }
        }

        var segments: [Segment] = []
        var i = m
        var j = n
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && source[i - 1] == processed[j - 1] {
                segments.append(.equal(source[i - 1]))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || table[i][j - 1] >= table[i - 1][j]) {
                segments.append(.inserted(processed[j - 1]))
                j -= 1
            } else if i > 0 {
                segments.append(.deleted(source[i - 1]))
                i -= 1
            }
        }
        return segments.reversed()
    }

    /// Token-level LCS ratio in `[0, 1]`:
    /// `round(lcs / max(sourceTokenCount, processedTokenCount))`.
    /// Both empty arrays report `1.0`. Exactly one empty side reports `0.0`.
    static func ratio(source: [String], processed: [String]) -> Double {
        let denominator = max(source.count, processed.count)
        guard denominator > 0 else { return 1.0 }
        guard !source.isEmpty, !processed.isEmpty else { return 0.0 }
        return Double(lcsLength(source, processed)) / Double(denominator)
    }

    private static func isASCIILetterOrDigit(_ scalar: Unicode.Scalar) -> Bool {
        // ASCII letters (a-z, A-Z) and digits (0-9) only. We intentionally do
        // NOT group extended Latin letters (é, ñ) so diacritic-sensitive edits
        // remain visible; the spec only requires English/digit runs to group.
        (scalar >= "a" && scalar <= "z") || (scalar >= "A" && scalar <= "Z") || (scalar >= "0" && scalar <= "9")
    }
}
