import Foundation

/// Removes pure filler words while preserving discourse markers with semantic
/// value. Conservative: only a small, curated set of pure fillers is removed.
///
/// Filler list (spec: `refactor-deterministic-text-processing`):
/// - CJK: `嗯`, `呃`, `唔`, `额`
/// - Latin: `um`, `uh`, `hmm`, `er`, `uhm`, `umm`, `uhh`, `erm`
///
/// Discourse markers like `啊`, `哦`, `哎`, `其实`, `然后`, `那个`, `这个` are
/// intentionally NOT in this list — they carry tone/meaning and must be
/// preserved.
public enum FillerWordFilter {
    /// Pure fillers that carry no semantic content. These are safe to remove.
    public static let pureFillers: Set<String> = [
        "嗯", "呃", "唔", "额",
        "um", "uh", "hmm", "er", "uhm", "umm", "uhh", "erm",
    ]

    /// Context: whether the current text is in a coding/identifier context.
    /// When true, Latin filler filtering is skipped to avoid mangling code
    /// tokens that happen to match a filler (e.g. a variable named `um`).
    /// CJK fillers are still removed because they never appear in code
    /// identifiers.
    public struct Context: Sendable, Equatable {
        public let isCodingContext: Bool
        public init(isCodingContext: Bool = false) {
            self.isCodingContext = isCodingContext
        }
    }

    /// Punctuation and pause marks that may appear adjacent to a filler.
    /// When a filler is removed, an immediately following pause mark is
    /// also removed to avoid leaving an orphaned separator.
    private static let adjacentPunctuationClass = "[，。！？,.!?；;：:、]"

    public static func process(_ text: String, context: Context = Context()) -> String {
        let cjkFillers = pureFillers.filter { $0.first?.isASCII == false }
        let latinFillers = pureFillers.filter { $0.first?.isASCII == true }

        // Run CJK filler removal in a loop until stable, so that consecutive
        // fillers (e.g. "嗯呃我觉得") are all removed, not just the first.
        var result = text
        var changed = true
        while changed {
            changed = false
            for filler in cjkFillers {
                let before = result
                result = removeCJKFillerWithAdjacentPunctuation(filler, from: result)
                if result != before {
                    changed = true
                }
            }
        }
        if !context.isCodingContext {
            for filler in latinFillers {
                result = removeLatinFiller(filler, from: result)
            }
        }
        result = collapseWhitespace(result)
        return result
    }

    /// Remove a CJK filler wherever it appears, along with an immediately
    /// following pause mark or whitespace. This handles patterns like
    /// `呃，我觉得` → `我觉得` and `嗯好的` → `好的`.
    private static func removeCJKFillerWithAdjacentPunctuation(_ filler: String, from text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: filler)
        // Match the filler optionally followed by a pause mark and optional
        // whitespace. The trailing punctuation cleanup prevents leaving
        // orphaned separators like `，我觉得` after removing `呃`.
        let pattern = "\(escaped)(?:\(adjacentPunctuationClass)\\s?)?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    /// Remove a Latin filler that appears as a standalone word (surrounded by
    /// word boundaries). Uses \b to avoid removing substrings inside words.
    /// Also consumes an immediately following pause mark and whitespace.
    private static func removeLatinFiller(_ filler: String, from text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: filler)
        // Match the filler as a standalone word, optionally followed by a
        // pause mark and/or whitespace (which we collapse later).
        let pattern = "\\b\(escaped)\\b\(adjacentPunctuationClass)?\\s?"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private static func collapseWhitespace(_ text: String) -> String {
        let pattern = "\\s{2,}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
