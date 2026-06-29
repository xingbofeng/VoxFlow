import Foundation

/// Long sentence line breaking. Splits overly long sentences at semantic
/// boundaries (commas, conjunctions) when the segment exceeds the configured
/// word or CJK character thresholds. Short sentences are never modified.
public enum LongSentenceBreaker {
    public struct Context: Sendable, Equatable {
        public let wordThreshold: Int
        public let cjkThreshold: Int
        public init(wordThreshold: Int = 8, cjkThreshold: Int = 12) {
            self.wordThreshold = wordThreshold
            self.cjkThreshold = cjkThreshold
        }
    }

    public static func process(_ text: String, context: Context = Context()) -> String {
        // Split into lines first, then break each line if it's too long.
        let lines = text.components(separatedBy: "\n")
        let processed = lines.map { line -> String in
            breakLongLine(line, context: context)
        }
        return processed.joined(separator: "\n")
    }

    private static func breakLongLine(_ line: String, context: Context) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return line }

        let cjkCount = countCJK(trimmed)
        let wordCount = countWords(trimmed)

        let needsBreaking = cjkCount > context.cjkThreshold || wordCount > context.wordThreshold
        guard needsBreaking else { return line }

        return splitAtBoundaries(trimmed, context: context)
    }

    /// Split at sentence and clause boundaries. Sentence endings are treated
    /// as strong boundaries: if adding the next segment would exceed the
    /// threshold, the previous complete sentence becomes its own line. Clause
    /// marks such as commas and semicolons are weaker but still safe split
    /// points. If no good split points exist, returns the original line.
    private static func splitAtBoundaries(_ text: String, context: Context) -> String {
        let segments = boundarySegments(in: text)
        guard segments.count > 1 else {
            return text
        }

        var lines: [String] = []
        var current = ""

        for (index, segment) in segments.enumerated() {
            let candidate = current + segment.text
            if !current.isEmpty, exceedsThreshold(candidate, context: context) {
                lines.append(current.trimmingCharacters(in: .whitespaces))
                current = segment.text
            } else {
                current = candidate
            }

            if segment.isStrongBoundary,
               index < segments.index(before: segments.endIndex),
               isSubstantialLine(current, context: context) {
                lines.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            }

            if exceedsThreshold(current, context: context) {
                lines.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        if !current.isEmpty {
            lines.append(current.trimmingCharacters(in: .whitespaces))
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct BoundarySegment {
        let text: String
        let isStrongBoundary: Bool
    }

    private static func boundarySegments(in text: String) -> [BoundarySegment] {
        var segments: [BoundarySegment] = []
        var current = ""
        let chars = Array(text)

        for index in chars.indices {
            let char = chars[index]
            current.append(char)
            let boundary = boundaryKind(
                char,
                previous: index > chars.startIndex ? chars[chars.index(before: index)] : nil,
                next: index < chars.index(before: chars.endIndex) ? chars[chars.index(after: index)] : nil
            )
            guard let boundary else {
                continue
            }
            segments.append(BoundarySegment(text: current, isStrongBoundary: boundary == .strong))
            current = ""
        }

        if !current.isEmpty {
            segments.append(BoundarySegment(text: current, isStrongBoundary: false))
        }
        return segments
    }

    private enum BoundaryKind {
        case weak
        case strong
    }

    private static func boundaryKind(_ char: Character, previous: Character?, next: Character?) -> BoundaryKind? {
        if ["，", "；", "、", ",", ";"].contains(char) {
            return .weak
        }
        if ["。", "！", "？"].contains(char) {
            return .strong
        }
        if [".", "!", "?"].contains(char) {
            if previous?.isNumber == true || next?.isNumber == true {
                return nil
            }
            return (next == nil || next?.isWhitespace == true) ? .strong : nil
        }
        return nil
    }

    private static func exceedsThreshold(_ text: String, context: Context) -> Bool {
        countCJK(text) > context.cjkThreshold || countWords(text) > context.wordThreshold
    }

    private static func isSubstantialLine(_ text: String, context: Context) -> Bool {
        let cjkMinimum = max(8, context.cjkThreshold / 3)
        let wordMinimum = max(6, context.wordThreshold / 3)
        return countCJK(text) >= cjkMinimum || countWords(text) >= wordMinimum
    }

    private static func countCJK(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $1.value >= 0x4E00 && $1.value <= 0x9FFF ? $0 + 1 : $0 }
    }

    private static func countWords(_ text: String) -> Int {
        // Count English words (whitespace-separated tokens) + CJK chars as
        // individual "words" for length estimation.
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if scalar.value >= 0x4E00 && scalar.value <= 0x9FFF {
                count += 1
                inWord = false
            } else if CharacterSet.alphanumerics.contains(scalar) {
                if !inWord {
                    count += 1
                    inWord = true
                }
            } else {
                inWord = false
            }
        }
        return count
    }
}
