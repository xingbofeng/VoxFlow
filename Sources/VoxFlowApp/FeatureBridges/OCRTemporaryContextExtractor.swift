import Foundation

/// Extracts temporary terms from OCR context for the current session only.
///
/// Per spec (ocr-temporary-context):
/// - Maximum 5 terms extracted
/// - Terms only participate in this session's LLM prompt and supported ASR context
/// - Terms are NEVER written to the hotword table or auto-learning queue
/// - Secure field disables OCR context entirely
struct OCRTemporaryContextExtractor {
    /// Maximum number of temporary terms to extract.
    static let maxTerms = 5

    /// Extracts up to 5 temporary terms from OCR text.
    /// Terms are deduplicated, filtered for reasonable length, and pruned.
    static func extractTerms(
        from ocrText: String,
        secureField: Bool = false
    ) -> OCRTemporaryTerms {
        guard !secureField else {
            return OCRTemporaryTerms(terms: [], charCount: 0, skippedReason: "secure_field")
        }

        let trimmed = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return OCRTemporaryTerms(terms: [], charCount: 0, skippedReason: nil)
        }

        // Extract candidate terms: words/phrases separated by whitespace, punctuation, or newlines
        let candidates = extractCandidates(from: trimmed)

        // Deduplicate by normalized form
        var seen = Set<String>()
        let deduplicated = candidates.filter { candidate in
            let normalized = candidate.lowercased()
            return seen.insert(normalized).inserted
        }

        // Filter: reasonable length (2-50 chars), not a common word
        let filtered = deduplicated.filter { term in
            let length = term.count
            guard length >= 2, length <= 50 else { return false }
            // Skip pure numbers
            guard term.allSatisfy({ !$0.isNumber }) == false || term.contains(where: { $0.isLetter }) else { return false }
            return true
        }

        // Prune to max 5
        let pruned = Array(filtered.prefix(Self.maxTerms))

        return OCRTemporaryTerms(
            terms: pruned,
            charCount: trimmed.count,
            skippedReason: nil
        )
    }

    /// Extracts candidate terms from OCR text by splitting on common separators.
    private static func extractCandidates(from text: String) -> [String] {
        // Split on whitespace, newlines, and common CJK/Latin punctuation
        let separators: CharacterSet = .whitespacesAndNewlines
            .union(.punctuationCharacters)
        // Also split on CJK punctuation that may not be in .punctuationCharacters
        let cjkSeparators: Set<Character> = ["、", "，", "。", "：", "；", "「", "」", "『", "』", "（", "）", "【", "】"]

        var candidates: [String] = []
        for line in text.components(separatedBy: .newlines) {
            // Split by separators
            let parts = line.components(separatedBy: separators)
            for part in parts {
                // Further split by CJK separators
                var subParts = [part]
                for sep in cjkSeparators {
                    subParts = subParts.flatMap { $0.components(separatedBy: String(sep)) }
                }
                for subPart in subParts {
                    let trimmed = subPart.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        candidates.append(trimmed)
                    }
                }
            }
        }
        return candidates
    }
}

/// Temporary OCR terms for the current session.
struct OCRTemporaryTerms: Equatable, Sendable {
    let terms: [String]
    let charCount: Int
    let skippedReason: String?

    var isSkipped: Bool {
        skippedReason != nil
    }
}
