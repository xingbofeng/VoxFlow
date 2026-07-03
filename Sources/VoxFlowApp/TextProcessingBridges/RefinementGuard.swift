import Foundation
import StringMetric

/// Structured, persistence-safe trace for one ordinary-dictation refinement
/// guard evaluation. Persisted via `TextProcessingTrace.refinementGuard`.
///
/// The trace NEVER carries full user text, prompt, or LLM response — only the
/// decision, a stable reason code, numeric similarity (when evaluated), the
/// baseline source, and the chosen fallback source. This keeps the home detail
/// explanatory without leaking raw content.
struct RefinementGuardTrace: Equatable, Codable, Sendable {
    enum Decision: String, Codable, Sendable, Equatable {
        case accepted
        case rejected
    }

    /// Where the similarity baseline came from. Today only the pre-LLM
    /// deterministic text is used; kept as an enum so future baselines stay
    /// readable in diagnostics.
    enum Baseline: String, Codable, Sendable, Equatable {
        case preLLMDeterministic = "pre_llm_deterministic"
    }

    /// Which text the pipeline fell back to when the guard rejects.
    enum Fallback: String, Codable, Sendable, Equatable {
        case preLLMDeterministic = "pre_llm_deterministic"
        case asrRaw = "asr_raw"
    }

    let decision: Decision
    /// Stable reason code on rejection (`empty_output`,
    /// `normalized_similarity_low`). `nil` when accepted.
    var reason: String?
    /// Normalized StringMetric similarity in `[0, 1]`. `nil` when similarity was
    /// not evaluated because an earlier hard reject fired.
    var similarity: Double?
    let baseline: Baseline
    var fallback: Fallback?
    /// Legacy trace field retained for older persisted records.
    /// New guard evaluations keep this empty.
    var protectedTokenKinds: [String]
    /// Legacy trace field retained for older persisted records. New guard
    /// evaluations always run similarity and keep this `false`.
    var shortTextBypassed: Bool

    init(
        decision: Decision,
        reason: String? = nil,
        similarity: Double? = nil,
        baseline: Baseline,
        fallback: Fallback? = nil,
        protectedTokenKinds: [String] = [],
        shortTextBypassed: Bool = false
    ) {
        self.decision = decision
        self.reason = reason
        self.similarity = similarity
        self.baseline = baseline
        self.fallback = fallback
        self.protectedTokenKinds = protectedTokenKinds
        self.shortTextBypassed = shortTextBypassed
    }
}

/// Conservative thresholds for the refinement guard. Fixed defaults keep the
/// guard predictable, testable, and free of user-tuning foot-guns; the values
/// are exposed as a struct so tests can pin them and future tuning can land
/// in one place.
struct RefinementGuardSettings: Sendable, Equatable {
    /// `normalized_similarity_low` fires when similarity is strictly below this
    /// floor.
    let similarityFloor: Double
    /// Very short transcripts have little context, so partial overlap is less
    /// trustworthy. They use a slightly stricter floor without adding another
    /// rule family.
    let shortTextSimilarityFloor: Double
    let shortTextCharacterLimit: Int

    static let defaults = RefinementGuardSettings(
        similarityFloor: 0.72,
        shortTextSimilarityFloor: 0.85,
        shortTextCharacterLimit: 8
    )
}

/// Local post-LLM insurance for ordinary dictation.
///
/// The guard inspects an LLM refinement candidate against the pre-LLM
/// deterministic text (similarity baseline). It hard-rejects empty outputs or
/// outputs whose normalized Jaro-Winkler similarity falls below the floor. The
/// guard never calls a second LLM and never changes the prompt/response
/// protocol.
///
/// Similarity is provided by the open-source `StringMetric` package. The guard
/// applies a small normalization layer (punctuation, whitespace, casing, emoji,
/// and Style Output Format-allowed light formatting) before scoring.
struct ConservativeRefinementGuard: Sendable {
    enum Decision: Equatable, Sendable {
        case accept
        case reject(String)
    }

    /// Richer outcome carrying the structured trace alongside the decision.
    struct Outcome: Equatable, Sendable {
        let decision: Decision
        let trace: RefinementGuardTrace
    }

    let settings: RefinementGuardSettings

    init(settings: RefinementGuardSettings = .defaults) {
        self.settings = settings
    }

    /// Evaluates a refinement candidate.
    ///
    /// - Parameters:
    ///   - asrRaw: ASR raw transcript; used as a protected-token source and
    ///     as the last-resort fallback when the guard rejects.
    ///   - preLLMDeterministic: deterministic pre-LLM text; the similarity
    ///     baseline and the preferred fallback when the guard rejects.
    ///   - refined: the candidate LLM refinement output (already
///     structured-parsed and trimmed).
    ///   - temporaryHotwords: context-boost hotwords that may legitimately
    ///     appear in the refined text.
    func evaluate(
        asrRaw: String,
        preLLMDeterministic: String,
        refined: String,
        temporaryHotwords: [String]
    ) -> Outcome {
        let baseline = preLLMDeterministic.trimmingCharacters(in: .whitespacesAndNewlines)
        let refinedTrimmed = refined.trimmingCharacters(in: .whitespacesAndNewlines)
        let deterministicFallbackAvailable = !baseline.isEmpty
        let fallback: RefinementGuardTrace.Fallback = deterministicFallbackAvailable
            ? .preLLMDeterministic
            : .asrRaw

        // 1. Empty output.
        guard !refinedTrimmed.isEmpty else {
            return reject(
                reason: "empty_output",
                similarity: nil,
                shortTextBypassed: false,
                fallback: fallback
            )
        }

        // 2. Normalized Jaro-Winkler similarity.
        let similarity = Self.similarity(
            baseline: baseline,
            refined: refinedTrimmed
        )
        let similarityFloor = Self.normalized(baseline).count <= settings.shortTextCharacterLimit
            ? settings.shortTextSimilarityFloor
            : settings.similarityFloor
        if similarity < similarityFloor {
            return reject(
                reason: "normalized_similarity_low",
                similarity: similarity,
                shortTextBypassed: false,
                fallback: fallback
            )
        }

        return accept(
            similarity: similarity,
            shortTextBypassed: false
        )
    }

    // MARK: - Convenience

    /// Legacy decision-only entry retained for tests/diagnostics that don't
    /// need the structured trace. The pipeline uses `evaluate`.
    func validate(
        asrRaw: String,
        preLLMDeterministic: String,
        refined: String,
        temporaryHotwords: [String]
    ) -> Decision {
        evaluate(
            asrRaw: asrRaw,
            preLLMDeterministic: preLLMDeterministic,
            refined: refined,
            temporaryHotwords: temporaryHotwords
        ).decision
    }

    // MARK: - Outcome builders

    private func reject(
        reason: String,
        similarity: Double?,
        shortTextBypassed: Bool,
        fallback: RefinementGuardTrace.Fallback
    ) -> Outcome {
        let trace = RefinementGuardTrace(
            decision: .rejected,
            reason: reason,
            similarity: similarity,
            baseline: .preLLMDeterministic,
            fallback: fallback,
            protectedTokenKinds: [],
            shortTextBypassed: shortTextBypassed
        )
        return Outcome(decision: .reject(reason), trace: trace)
    }

    private func accept(
        similarity: Double?,
        shortTextBypassed: Bool
    ) -> Outcome {
        let trace = RefinementGuardTrace(
            decision: .accepted,
            reason: nil,
            similarity: similarity,
            baseline: .preLLMDeterministic,
            fallback: nil,
            protectedTokenKinds: [],
            shortTextBypassed: shortTextBypassed
        )
        return Outcome(decision: .accept, trace: trace)
    }

    // MARK: - Normalization

    static func similarity(baseline: String, refined: String) -> Double {
        let normalizedBaseline = normalized(baseline)
        let normalizedRefined = normalized(refined)
        return normalizedBaseline.distanceJaroWinkler(between: normalizedRefined)
    }

    /// Guard-only normalization. Drops punctuation, whitespace, casing, emoji,
    /// and Style Output Format-allowed light formatting (markdown bold/italic,
    /// heading markers, backtick code spans' wrapping backticks) before the
    /// shared tokenizer scores similarity. Kept separate from the home diff
    /// normalization so the home comparison still shows the edits.
    static func normalized(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            // Lowercase ASCII.
            if scalar >= "A" && scalar <= "Z" {
                out.unicodeScalars.append(UnicodeScalar(UInt8(scalar.value - 0x41 + 0x61)))
                continue
            }
            // Skip whitespace.
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { continue }
            // Skip common CJK / ASCII punctuation.
            if isPunctuation(scalar) { continue }
            // Skip emoji.
            if isEmoji(scalar) { continue }
            out.unicodeScalars.append(scalar)
        }
        // Strip Style Output Format light formatting markers. We remove the
        // wrapping characters but keep the inner text so the content is still
        // scored (e.g. `**bold**` -> `bold`, `# heading` -> `heading`).
        out = out
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "##", with: "")
            .replacingOccurrences(of: "#", with: "")
        return out
    }

    private static func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        // ASCII punctuation.
        if scalar >= "!" && scalar <= "~" {
            let isPunct: Bool = switch scalar {
            case "\"", "'", "(", ")", "[", "]", "{", "}", "<", ">",
                 "!", "?", ".", ",", ";", ":",
                 "-", "_", "+", "=", "|", "\\", "/", "*", "&", "^", "%", "$", "@", "`", "~":
                true
            default: false
            }
            if isPunct { return true }
        }
        // CJK punctuation ranges.
        let v = scalar.value
        if (0x3000...0x303F).contains(v) || (0xFF00...0xFFEF).contains(v) {
            return true
        }
        return false
    }

    private static func isEmoji(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        // Emoji-presentation and symbol blocks. We intentionally keep this
        // coarse; guard similarity cares only that emoji shouldn't move the
        // score, not about precise coverage.
        return (0x1F000...0x1FAFF).contains(v)
            || (0x2600...0x27BF).contains(v)
            || (0x1F1E6...0x1F1FF).contains(v)
    }

}
