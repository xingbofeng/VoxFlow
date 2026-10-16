import Foundation
import VoxFlowVoiceCorrection

/// Persistence for post-edit learned corrections. Shared by the AX
/// observation coordinator (dictation inserted-text edits) and the Home
/// history manual-edit path so both learning sources produce the same rule +
/// evidence outcome.
///
/// Behaviors layered on top of a plain rule save:
/// - Repeated observation of the same pair within its scope, provider,
///   model, and language aggregates `observedCount` on the existing rule.
/// - A new replacement for an original the user has since corrected
///   differently supersedes (retires) the earlier automatic rule.
/// - Reverse evidence in the correction evidence store and feedback chains
///   against existing automatic rules block learning entirely.
/// - Evidence upsert is best-effort: a failure never blocks the rule save.
/// - Rule-save failures throw; callers own diagnostics and error surfaces.
@MainActor
struct PostEditLearningService {
    enum Status: Equatable {
        case learned
        case aggregated
        case blockedReverseEvidence
        case blockedFeedbackChain
        case skippedUnsupportedContext
    }

    struct LearnResult: Equatable {
        let status: Status
        /// A newly created rule that callers may offer to delete through undo.
        /// Aggregation leaves earlier learning intact and creates no undo item.
        let item: CorrectionObservationLearningItem?
    }

    private let ruleRepository: any CorrectionRuleRepository
    private let targetRepository: any CorrectionTargetRepository
    private let evidenceRepository: (any CorrectionEvidenceRepository)?
    private let snapshotProvider: CorrectionRuleSnapshotProvider

    init(
        ruleRepository: any CorrectionRuleRepository,
        targetRepository: any CorrectionTargetRepository,
        evidenceRepository: (any CorrectionEvidenceRepository)?,
        snapshotProvider: CorrectionRuleSnapshotProvider
    ) {
        self.ruleRepository = ruleRepository
        self.targetRepository = targetRepository
        self.evidenceRepository = evidenceRepository
        self.snapshotProvider = snapshotProvider
    }

    func learn(
        pair: LearnedCorrectionPair,
        context: CorrectionContext,
        appliesImmediately: Bool,
        now: Date
    ) throws -> LearnResult {
        guard context.mode == .dictation,
              context.isFinalTranscript,
              !context.isSecureField
        else {
            return LearnResult(status: .skippedUnsupportedContext, item: nil)
        }

        if (try? evidenceRepository?.hasReverseEvidence(
            original: pair.original,
            corrected: pair.replacement
        )) == true {
            return LearnResult(status: .blockedReverseEvidence, item: nil)
        }

        // History edits carry no bundle identifier for legacy entries; those
        // learn a global rule. The AX path always has a bundle identifier by
        // the time it reaches learning.
        let scope = context.bundleIdentifier.map { RuleScope.application(bundleIdentifier: $0) } ?? .global
        let existingRules = try ruleRepository.list()
        let matchingRules = existingRules.filter {
            $0.scope == scope &&
                $0.original.caseInsensitiveCompare(pair.original) == .orderedSame &&
                $0.providerID == context.providerID &&
                $0.modelID == context.modelID &&
                $0.language == context.language
        }
        // Active disabled/manual rules still occupy the storage uniqueness key.
        // Preserve the user's rule rather than re-enabling or replacing it.
        guard !matchingRules.contains(where: {
            $0.lifecycle == .active && (!$0.isEnabled || $0.source != .automaticLearning)
        }) else {
            return LearnResult(status: .skippedUnsupportedContext, item: nil)
        }
        let automaticRules = existingRules.filter {
            $0.source == .automaticLearning && $0.isEnabled &&
                ($0.lifecycle == .active || $0.lifecycle == .candidate)
        }
        // LearningPolicy.wouldCreateFeedbackChain checks existing automatic
        // rules whose replacement would become this pair's original —
        // learning A→B while B→A is already an automatic rule would create a
        // replacement ping-pong.
        if LearningPolicy().wouldCreateFeedbackChain(pair, existingRules: automaticRules.filter {
            $0.scope == scope &&
                optionalConstraint($0.providerID, matches: context.providerID) &&
                optionalConstraint($0.modelID, matches: context.modelID) &&
                optionalConstraint($0.language, matches: context.language)
        }) {
            return LearnResult(status: .blockedFeedbackChain, item: nil)
        }

        let outcome = try saveRule(
            pair: pair,
            scope: scope,
            context: context,
            matchingRules: matchingRules.filter {
                $0.source == .automaticLearning && $0.isEnabled &&
                    ($0.lifecycle == .active || $0.lifecycle == .candidate)
            },
            appliesImmediately: appliesImmediately,
            now: now
        )
        upsertEvidence(pair: pair, now: now)
        return outcome
    }

    private func saveRule(
        pair: LearnedCorrectionPair,
        scope: RuleScope,
        context: CorrectionContext,
        matchingRules: [CorrectionRule],
        appliesImmediately: Bool,
        now: Date
    ) throws -> LearnResult {
        if var existing = matchingRules.first(where: {
            $0.replacement.caseInsensitiveCompare(pair.replacement) == .orderedSame
        }) {
            existing.observedCount += 1
            existing.updatedAt = now
            try ruleRepository.save(existing)
            return LearnResult(status: .aggregated, item: nil)
        }
        // Retire all competing automatic rules in this exact context; retired
        // history and rules for other providers/models/languages remain intact.
        for var existing in matchingRules {
            existing.lifecycle = .retired
            existing.updatedAt = now
            try ruleRepository.save(existing)
        }

        let target = try targetTerm(
            text: pair.replacement,
            scope: scope,
            activeImmediately: appliesImmediately,
            now: now
        )
        let rule = CorrectionRule(
            targetID: target.id,
            original: pair.original,
            replacement: target.text,
            matchPolicy: .boundary,
            scope: scope,
            lifecycle: appliesImmediately ? .active : .candidate,
            source: .automaticLearning,
            confidence: appliesImmediately ? 0.90 : 0.40,
            observedCount: 1,
            providerID: context.providerID,
            modelID: context.modelID,
            language: context.language,
            createdAt: now,
            updatedAt: now
        )
        try ruleRepository.save(rule)
        _ = snapshotProvider.refresh()
        return LearnResult(status: .learned, item: CorrectionObservationLearningItem(rule: rule, targetID: target.id))
    }

    private func optionalConstraint(_ required: String?, matches actual: String?) -> Bool {
        guard let required else { return true }
        return required.caseInsensitiveCompare(actual ?? "") == .orderedSame
    }

    private func upsertEvidence(pair: LearnedCorrectionPair, now: Date) {
        guard let evidenceRepository else { return }
        do {
            _ = try evidenceRepository.upsert(
                StructuredCorrection(
                    original: pair.original,
                    corrected: pair.replacement,
                    type: .homophone
                )
            )
        } catch {
            // Evidence is auxiliary context for future LLM prompts; a failed
            // upsert must never discard the saved rule.
            AppLogger.general.warning(
                "post_edit_learning_evidence_upsert_failed \(error.localizedDescription)"
            )
        }
    }

    private func targetTerm(
        text: String,
        scope: RuleScope,
        activeImmediately: Bool,
        now: Date
    ) throws -> CorrectionTargetTerm {
        let normalizedText = CorrectionTargetTerm.normalize(text)
        if var existing = try targetRepository.list().first(where: {
            $0.normalizedText.caseInsensitiveCompare(normalizedText) == .orderedSame &&
                $0.scope == scope
        }) {
            existing.observedCount += 1
            existing.updatedAt = now
            try targetRepository.save(existing)
            return existing
        }

        let target = CorrectionTargetTerm(
            text: text,
            normalizedText: normalizedText,
            scope: scope,
            lifecycle: activeImmediately ? .active : .candidate,
            source: .automaticLearning,
            observedCount: 1,
            createdAt: now,
            updatedAt: now
        )
        try targetRepository.save(target)
        return target
    }
}
