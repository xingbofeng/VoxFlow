import Foundation
import VoxFlowVoiceCorrection

/// Counts non-overlapping occurrences of hotwords in the final output text,
/// translating OpenLess `record_hits(text)` from
/// `/tmp/openless/openless-all/app/src-tauri/src/persistence/dictionary.rs`.
///
/// Hit counting SHALL only run on the final output text (after LLM + text
/// replacement), never on the raw ASR transcript. This is the spec requirement
/// from vocabulary-center: "命中统计 SHALL 以最终文本为准".
final class HotwordHitCounter {
    private static let logger = AppLogger.dictation

    private let repository: any CorrectionTargetRepository
    private let clock: any AppClock

    init(repository: any CorrectionTargetRepository, clock: any AppClock = SystemClock()) {
        self.repository = repository
        self.clock = clock
    }

    /// Scans `finalText` for each hotword and increments `hitCount` /
    /// updates `lastHitAt` for non-overlapping occurrences. Persists results.
    ///
    /// - Parameter finalText: The text that was actually output to the user
    ///   (after LLM refinement and text replacement), never the raw ASR text.
    /// - Returns: A summary of which hotwords were hit and how many times.
    @discardableResult
    func recordHits(in finalText: String) -> HotwordHitSummary {
        guard !finalText.isEmpty else {
            return .empty
        }

        let hotwords: [CorrectionTargetTerm]
        do {
            hotwords = try repository.listHotwords()
        } catch {
            Self.logger.error("hotword_hit_counter_list_failed error=\(error)")
            return .empty
        }
        guard !hotwords.isEmpty else {
            return .empty
        }

        let now = clock.now
        var hits: [HotwordHit] = []
        var updatedCount = 0

        for hotword in hotwords {
            let occurrences = Self.countNonOverlappingOccurrences(
                of: hotword.text,
                in: finalText,
                caseSensitive: false
            )
            guard occurrences > 0 else { continue }

            var updated = hotword
            updated.hitCount += occurrences
            updated.lastHitAt = now
            updated.updatedAt = now
            do {
                try repository.save(updated)
                updatedCount += 1
                hits.append(HotwordHit(term: hotword.text, count: occurrences))
            } catch {
                Self.logger.error("hotword_hit_counter_save_failed term=\(hotword.text) error=\(error)")
            }
        }

        Self.logger.info(
            "hotword_hit_counter_recorded total=\(hits.reduce(0) { $0 + $1.count }) " +
            "terms=\(hits.count) updated=\(updatedCount)"
        )

        return HotwordHitSummary(hits: hits, totalOccurrences: hits.reduce(0) { $0 + $1.count })
    }

    /// Counts non-overlapping occurrences of `needle` in `haystack`.
    ///
    /// For CJK hotwords and English hotwords alike, we use case-insensitive
    /// matching since ASR/LLM output casing may differ from the stored hotword.
    /// Diacritic-insensitive is NOT applied — we want exact character matches
    /// for proper nouns; only case is normalized.
    static func countNonOverlappingOccurrences(
        of needle: String,
        in haystack: String,
        caseSensitive: Bool = false
    ) -> Int {
        let trimmedNeedle = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNeedle.isEmpty else { return 0 }

        let searchHaystack: String
        let searchNeedle: String
        if caseSensitive {
            searchHaystack = haystack
            searchNeedle = trimmedNeedle
        } else {
            searchHaystack = haystack.lowercased()
            searchNeedle = trimmedNeedle.lowercased()
        }

        var count = 0
        var searchStart = searchHaystack.startIndex
        while searchStart < searchHaystack.endIndex,
              let range = searchHaystack.range(of: searchNeedle, range: searchStart..<searchHaystack.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }
}

struct HotwordHit: Equatable, Sendable {
    let term: String
    let count: Int
}

struct HotwordHitSummary: Equatable, Sendable {
    let hits: [HotwordHit]
    let totalOccurrences: Int

    static let empty = HotwordHitSummary(hits: [], totalOccurrences: 0)
}
