import Foundation

/// Display mode for `TextComparisonView`.
///
/// - `.source`: show the original / raw / input text only.
/// - `.processed`: show the processed / final / output text only.
/// - `.comparison`: show inline diff highlighting with a similarity badge.
enum TextComparisonMode: String, CaseIterable, Sendable, Equatable {
    case source
    case processed
    case comparison
}

/// A single diff segment rendered inline inside `TextComparisonView`.
enum TextDiffSegment: Equatable, Sendable {
    case equal(String)
    case inserted(String)
    case deleted(String)

    var text: String {
        switch self {
        case .equal(let value), .inserted(let value), .deleted(let value):
            return value
        }
    }

    var isChanged: Bool {
        switch self {
        case .equal: return false
        case .inserted, .deleted: return true
        }
    }
}

/// Internal boundary that turns two strings into a list of diff segments.
///
/// The default implementation is a conservative token LCS diff (CJK characters
/// individually, ASCII letter/digit runs as a single token, punctuation and
/// whitespace each as their own token). The protocol lets us swap in a
/// third-party diff later without touching `TextComparisonView` callers.
protocol TextDiffEngine: Sendable {
    func segments(between source: String, and processed: String) -> [TextDiffSegment]
}

/// Pure presentation model backing `TextComparisonView`.
///
/// The model exposes the source/processed text, the diff segments, a rounded
/// similarity percentage, and a `defaultMode` so callers can pick a sensible
/// initial tab. It does not depend on SwiftUI or `L10n`; the view layer is
/// responsible for localizing labels and accessibility strings.
///
/// Similarity is computed as:
///
/// ```
/// similarityPercent = round(equalCharacterCount / max(source.count, processed.count) * 100)
/// ```
///
/// Both empty strings report 100%. Exactly one empty side reports 0%.
struct TextComparisonPresentation: Equatable, Sendable {
    let sourceText: String
    let processedText: String
    let segments: [TextDiffSegment]
    let similarityPercent: Int
    let isChanged: Bool

    init(source: String, processed: String, engine: TextDiffEngine = TokenLCSDiffEngine()) {
        self.sourceText = source
        self.processedText = processed
        let computedSegments = engine.segments(between: source, and: processed)
        self.segments = TokenLCSDiffEngine.coalesced(computedSegments)
        self.isChanged = Self.computeIsChanged(source: source, processed: processed, segments: self.segments)
        self.similarityPercent = Self.computeSimilarity(source: source, processed: processed, segments: self.segments)
    }

    var defaultMode: TextComparisonMode {
        isChanged ? .comparison : .processed
    }

    func displayText(for mode: TextComparisonMode) -> String {
        switch mode {
        case .source: return sourceText
        case .processed: return processedText
        case .comparison: return segments.map(\.text).joined()
        }
    }

    // MARK: - Internal helpers

    private static func computeIsChanged(source: String, processed: String, segments: [TextDiffSegment]) -> Bool {
        if source == processed { return false }
        return segments.contains { $0.isChanged }
    }

    private static func computeSimilarity(source: String, processed: String, segments: [TextDiffSegment]) -> Int {
        let sourceCount = source.count
        let processedCount = processed.count
        let denominator = max(sourceCount, processedCount)
        if denominator == 0 { return 100 }
        if sourceCount == 0 || processedCount == 0 { return 0 }

        let equalCount = segments.reduce(0) { partial, segment in
            switch segment {
            case .equal(let text): return partial + text.count
            case .inserted, .deleted: return partial
            }
        }
        let ratio = Double(equalCount) / Double(denominator)
        let rounded = (ratio * 100).rounded()
        let clamped = max(0, min(100, Int(rounded)))
        return clamped
    }
}

/// Minimal token LCS diff engine for the home transcript comparison.
///
/// Tokenization and the LCS table walk are delegated to the shared
/// `TokenLCSMatcher` backbone (per design.md §"使用 TextDiffing 作为优先 diff 轮子"
/// and `add-dictation-refinement-guard` ADR), so the home diff and the
/// refinement guard always agree on what a token is and how the LCS cell is
/// walked back. Adjacent segments of the same kind are coalesced so the UI
/// does not render a separate chip per character.
struct TokenLCSDiffEngine: TextDiffEngine {
    func segments(between source: String, and processed: String) -> [TextDiffSegment] {
        let sourceTokens = TokenLCSMatcher.tokenize(source)
        let processedTokens = TokenLCSMatcher.tokenize(processed)
        return TokenLCSDiffEngine.lcs(source: sourceTokens, processed: processedTokens)
    }

    static func coalesced(_ segments: [TextDiffSegment]) -> [TextDiffSegment] {
        var result: [TextDiffSegment] = []
        for segment in segments {
            guard let last = result.last else {
                result.append(segment)
                continue
            }
            switch (last, segment) {
            case (.equal(let a), .equal(let b)):
                result[result.count - 1] = .equal(a + b)
            case (.inserted(let a), .inserted(let b)):
                result[result.count - 1] = .inserted(a + b)
            case (.deleted(let a), .deleted(let b)):
                result[result.count - 1] = .deleted(a + b)
            default:
                result.append(segment)
            }
        }
        return result
    }

    // MARK: - LCS

    static func lcs(source: [String], processed: [String]) -> [TextDiffSegment] {
        TokenLCSMatcher.lcsSegments(source: source, processed: processed).map { segment in
            switch segment {
            case .equal(let text): return .equal(text)
            case .inserted(let text): return .inserted(text)
            case .deleted(let text): return .deleted(text)
            }
        }
    }
}
