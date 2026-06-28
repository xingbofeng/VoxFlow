import Foundation
import VoxFlowVoiceCorrection

/// Auto-learning service for LLM structured correction output.
///
/// Translates Light-Whisper's learning logic from
/// `/tmp/light-whisper/src-tauri/src/services/profile_service.rs`:
/// - `is_reasonable_hot_word`: filters unreasonable terms
/// - `upsert_correction`: filters and stores internal correction evidence
/// - `learn_from_structured`: learns homophone/term/pronoun, skips style
/// - `promote_vocab_to_hot_words`: promotes terms appearing N times to hotwords
///
/// Learning thresholds (from research-decisions.md §5):
/// - key_terms: 2nd appearance → enters auto-learning drawer
/// - key_terms: 3rd appearance → auto-promotes to hotword (unless blocklisted)
/// - corrections: stored as internal evidence only, not strong replacement
final class StructuredCorrectionLearningService {
    private static let logger = AppLogger.dictation

    /// key_terms appearance count to enter the auto-learning drawer.
    static let drawerThreshold = 2

    /// key_terms appearance count to auto-promote to hotword.
    static let promotionThreshold = 3

    /// Maximum term length for reasonable hot word.
    static let maxReasonableTermLength = 50

    /// Maximum ratio between original and corrected for a valid correction.
    static let maxCorrectionRatio = 3.0

    private let repository: any CorrectionTargetRepository
    private let termCounter: any KeyTermCounting
    private let evidenceRepository: (any CorrectionEvidenceRepository)?

    init(
        repository: any CorrectionTargetRepository,
        termCounter: any KeyTermCounting,
        evidenceRepository: (any CorrectionEvidenceRepository)? = nil
    ) {
        self.repository = repository
        self.termCounter = termCounter
        self.evidenceRepository = evidenceRepository
    }

    /// Processes a structured LLM correction output for learning.
    /// - Returns: A summary of what was learned, promoted, or filtered.
    func learn(from output: StructuredCorrectionOutput) -> LearningOutcome {
        var keyTermResults: [KeyTermLearningResult] = []
        var correctionResults: [CorrectionLearningResult] = []
        var promotedHotwords: [String] = []
        var drawerCandidates: [String] = []

        // Task 9.5: Learn key_terms
        for term in output.keyTerms {
            let result = processKeyTerm(term)
            keyTermResults.append(result)
            switch result.action {
            case .promotedToHotword:
                promotedHotwords.append(term)
            case .enteredDrawer:
                drawerCandidates.append(term)
            default:
                break
            }
        }

        // Task 9.3: Learn corrections (homophone/term/pronoun only, skip style)
        for correction in output.corrections {
            let result = processCorrection(correction)
            correctionResults.append(result)
        }

        Self.logger.info(
            "learning_outcome keyTerms=\(output.keyTerms.count) " +
            "promoted=\(promotedHotwords.count) drawer=\(drawerCandidates.count) " +
            "corrections=\(output.corrections.count) learned=\(correctionResults.filter { $0.action == .learned }.count)"
        )

        return LearningOutcome(
            keyTermResults: keyTermResults,
            correctionResults: correctionResults,
            promotedHotwords: promotedHotwords,
            drawerCandidates: drawerCandidates
        )
    }

    // MARK: - Task 9.1: is_reasonable_hot_word

    /// Determines if a term is reasonable to learn as a hotword.
    /// Translates Light-Whisper's `is_reasonable_hot_word`.
    static func isReasonableHotWord(_ term: String) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.count <= maxReasonableTermLength else { return false }

        // Skip single CJK characters
        if trimmed.count == 1, isCJK(trimmed) { return false }

        // Skip common filler words
        let fillers: Set<String> = ["嗯", "啊", "呃", "那个", "这个", "就是", "然后", "其实", "的话"]
        if fillers.contains(trimmed.lowercased()) { return false }

        // Skip action commands
        let actions: Set<String> = ["删除", "保存", "发送", "取消", "确认", "复制", "粘贴"]
        if actions.contains(trimmed.lowercased()) { return false }

        // Skip if it looks like a full sentence (contains sentence-ending punctuation)
        if trimmed.contains("。") || trimmed.contains("？") || trimmed.contains("！") {
            return false
        }

        return true
    }

    // MARK: - Task 9.2: upsert_correction filtering

    /// Validates a correction pair per Light-Whisper's `upsert_correction` strategy.
    static func isValidCorrection(original: String, corrected: String) -> Bool {
        let orig = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let corr = corrected.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty values
        guard !orig.isEmpty, !corr.isEmpty else { return false }
        // Same value
        guard orig != corr else { return false }
        // Too long
        guard orig.count <= 100, corr.count <= 100 else { return false }
        // Single CJK character
        if orig.count == 1, isCJK(orig) { return false }
        // Ratio too large
        let ratio = Double(corr.count) / Double(max(orig.count, 1))
        guard ratio <= maxCorrectionRatio && ratio >= 1.0 / maxCorrectionRatio else { return false }

        return true
    }

    // MARK: - Task 9.3: learn_from_structured (skip style)

    /// Processes a single correction from the structured output.
    private func processCorrection(_ correction: StructuredCorrection) -> CorrectionLearningResult {
        // Skip style corrections
        if correction.type == .style {
            return CorrectionLearningResult(
                correction: correction,
                action: .skippedStyle
            )
        }

        // Validate
        guard Self.isValidCorrection(original: correction.original, corrected: correction.corrected) else {
            return CorrectionLearningResult(
                correction: correction,
                action: .filtered
            )
        }

        if (try? evidenceRepository?.hasReverseEvidence(
            original: correction.original,
            corrected: correction.corrected
        )) == true {
            return CorrectionLearningResult(
                correction: correction,
                action: .filtered
            )
        }

        // Store as internal evidence only (not a strong replacement rule).
        if let evidenceRepository {
            do {
                let evidence = try evidenceRepository.upsert(correction)
                Self.logger.debug(
                    "learning_correction_stored original=\(correction.original) " +
                    "corrected=\(correction.corrected) type=\(correction.type.rawValue) " +
                    "count=\(evidence.occurrenceCount)"
                )
            } catch {
                Self.logger.error("learning_correction_store_failed error=\(error.localizedDescription)")
                return CorrectionLearningResult(
                    correction: correction,
                    action: .filtered
                )
            }
        } else {
            Self.logger.debug(
                "learning_correction_no_evidence_repository original=\(correction.original) " +
                "corrected=\(correction.corrected) type=\(correction.type.rawValue)"
            )
        }

        return CorrectionLearningResult(
            correction: correction,
            action: .learned
        )
    }

    // MARK: - Task 9.4/9.5: key_terms counting and promotion

    /// Processes a single key_term: increments counter, checks thresholds.
    private func processKeyTerm(_ term: String) -> KeyTermLearningResult {
        // Task 9.1: Check if reasonable
        guard Self.isReasonableHotWord(term) else {
            return KeyTermLearningResult(term: term, count: 0, action: .filtered)
        }

        // Increment counter
        let count = termCounter.increment(term)

        switch count {
        case Self.promotionThreshold...:
            // Task 9.5: Auto-promote to hotword
            // Task 9.7: Check blocklist — don't promote if blocklisted
            let hotword = CorrectionTargetTerm(
                text: term,
                lifecycle: .active,
                source: .automaticLearning
            )
            let saved = (try? repository.saveHotwordIfNotBlocklisted(hotword)) ?? false
            let action: KeyTermAction = saved ? .promotedToHotword : .blockedByBlocklist
            return KeyTermLearningResult(term: term, count: count, action: action)

        case Self.drawerThreshold:
            // Task 9.5: Enter auto-learning drawer
            return KeyTermLearningResult(term: term, count: count, action: .enteredDrawer)

        default:
            // Just counting
            return KeyTermLearningResult(term: term, count: count, action: .counting)
        }
    }

    // MARK: - Reverse chain detection (task 9.2)

    /// Checks if a correction is a reverse of an existing correction.
    /// E.g., if A->B exists, B->A should be skipped.
    static func isReverseChain(
        original: String,
        corrected: String,
        existing: [(original: String, corrected: String)]
    ) -> Bool {
        existing.contains { $0.original == corrected && $0.corrected == original }
    }

    // MARK: - Helpers

    private static func isCJK(_ value: String) -> Bool {
        guard let scalar = value.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F:
            return true
        default:
            return false
        }
    }
}

// MARK: - Supporting types

protocol KeyTermCounting {
    func increment(_ term: String) -> Int
    func count(for term: String) -> Int
    func reset()
}

/// In-memory key term counter for testing and simple use cases.
final class InMemoryKeyTermCounter: KeyTermCounting {
    private var counts: [String: Int] = [:]
    private let lock = NSLock()

    func increment(_ term: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let normalized = term.lowercased()
        counts[normalized, default: 0] += 1
        return counts[normalized]!
    }

    func count(for term: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[term.lowercased(), default: 0]
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        counts.removeAll()
    }
}

final class RepositoryBackedKeyTermCounter: KeyTermCounting {
    private static let logger = AppLogger.dictation

    private let repository: any CorrectionTargetRepository
    private let clock: any AppClock

    init(repository: any CorrectionTargetRepository, clock: any AppClock = SystemClock()) {
        self.repository = repository
        self.clock = clock
    }

    func increment(_ term: String) -> Int {
        do {
            guard let target = try repository.recordKeyTermObservation(term, now: clock.now) else {
                return 0
            }
            return target.observedCount
        } catch {
            Self.logger.error("key_term_counter_increment_failed term=\(term) error=\(error.localizedDescription)")
            return 0
        }
    }

    func count(for term: String) -> Int {
        do {
            return try repository.listLearningCandidates(limit: 200)
                .first { $0.normalizedText == CorrectionTargetTerm.normalize(term) }?
                .observedCount ?? 0
        } catch {
            Self.logger.error("key_term_counter_count_failed term=\(term) error=\(error.localizedDescription)")
            return 0
        }
    }

    func reset() {
        Self.logger.debug("key_term_counter_reset_ignored repository_backed=true")
    }
}

struct LearningOutcome: Equatable, Sendable {
    let keyTermResults: [KeyTermLearningResult]
    let correctionResults: [CorrectionLearningResult]
    let promotedHotwords: [String]
    let drawerCandidates: [String]
}

struct KeyTermLearningResult: Equatable, Sendable {
    let term: String
    let count: Int
    let action: KeyTermAction
}

enum KeyTermAction: String, Equatable, Sendable {
    case counting
    case enteredDrawer
    case promotedToHotword
    case blockedByBlocklist
    case filtered
}

struct CorrectionLearningResult: Equatable, Sendable {
    let correction: StructuredCorrection
    let action: CorrectionLearningAction
}

enum CorrectionLearningAction: String, Equatable, Sendable {
    case learned
    case skippedStyle
    case filtered
}
