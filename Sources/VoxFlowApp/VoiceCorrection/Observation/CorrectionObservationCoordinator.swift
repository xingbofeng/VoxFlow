import Foundation
import VoxFlowVoiceCorrection

@MainActor
protocol CorrectionObservationScheduling: AnyObject {
    func scheduleObservation(
        insertedText: String,
        context: CorrectionContext,
        appliedEvents: [CorrectionEvent]
    )
}

@MainActor
final class CorrectionObservationScheduler: CorrectionObservationScheduling {
    private let coordinator: CorrectionObservationCoordinator
    private var currentTask: Task<Void, Never>?

    init(coordinator: CorrectionObservationCoordinator) {
        self.coordinator = coordinator
    }

    func scheduleObservation(
        insertedText: String,
        context: CorrectionContext,
        appliedEvents: [CorrectionEvent]
    ) {
        currentTask?.cancel()
        currentTask = Task { @MainActor [coordinator] in
            await coordinator.observeInsertedText(
                insertedText,
                context: context,
                appliedEvents: appliedEvents
            )
        }
    }
}

struct CorrectionObservationLearningEvent: Equatable, Sendable {
    let original: String
    let replacement: String
    let lifecycle: RuleLifecycle
    let scope: RuleScope
    let ruleID: UUID
    let targetID: UUID

    var message: String {
        switch lifecycle {
        case .active:
            return "已自动学习：\(original) → \(replacement)"
        case .candidate:
            return "已发现修正：\(original) → \(replacement)，待确认"
        case .suspended, .retired:
            return "已记录修正：\(original) → \(replacement)"
        }
    }
}

extension Notification.Name {
    static let correctionObservationLearningEvent = Notification.Name("VoxFlow.CorrectionObservationLearningEvent")
}

struct CorrectionObservationDiagnostic: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case disabled
        case unsupportedContext
        case emptyInsertedText
        case baselineMissingInsertedText
        case recaptureLostFocus
        case noUserEditObserved
        case noHighConfidenceCorrection
        case saveFailed
    }

    let reason: Reason
    let insertedText: String
    let bundleIdentifier: String?
}

@MainActor
final class CorrectionObservationCoordinator {
    private let tracker: FocusedTextObservationTracker
    private let clock: any CorrectionObservationClock
    private let repository: any CorrectionRuleRepository
    private let targetRepository: any CorrectionTargetRepository
    private let extractor: HighConfidenceCorrectionExtractor
    private let pollOffsets: [Duration]
    private let baselineCaptureDelays: [Duration]
    private let commitObserver: (any CorrectionObservationCommitObserving)?
    private let isAutoLearningEnabled: () -> Bool
    private let autoLearningAppliesImmediately: () -> Bool
    private let onLearningEvent: (CorrectionObservationLearningEvent) -> Void
    private let onDiagnostic: (CorrectionObservationDiagnostic) -> Void
    private let onSaveFailure: (Error) -> Void
    private var pendingCommitSignal: CorrectionObservationCommitSignal?

    init(
        observer: any FocusedTextObserving,
        clock: any CorrectionObservationClock = ContinuousCorrectionObservationClock(),
        repository: any CorrectionRuleRepository,
        targetRepository: any CorrectionTargetRepository,
        extractor: HighConfidenceCorrectionExtractor = HighConfidenceCorrectionExtractor(),
        pollOffsets: [Duration] = CorrectionObservationPollSchedule.defaultOffsets,
        baselineCaptureDelays: [Duration] = [.milliseconds(150), .milliseconds(150), .milliseconds(200)],
        commitObserver: (any CorrectionObservationCommitObserving)? = nil,
        isAutoLearningEnabled: @escaping () -> Bool,
        autoLearningAppliesImmediately: @escaping () -> Bool,
        onLearningEvent: @escaping (CorrectionObservationLearningEvent) -> Void = { _ in },
        onDiagnostic: @escaping (CorrectionObservationDiagnostic) -> Void = { _ in },
        onSaveFailure: @escaping (Error) -> Void = {
            AppLogger.general.warning("Voice correction auto-learning save failed: \($0.localizedDescription)")
        }
    ) {
        self.tracker = FocusedTextObservationTracker(observer: observer)
        self.clock = clock
        self.repository = repository
        self.targetRepository = targetRepository
        self.extractor = extractor
        self.pollOffsets = pollOffsets
        self.baselineCaptureDelays = baselineCaptureDelays
        self.commitObserver = commitObserver
        self.isAutoLearningEnabled = isAutoLearningEnabled
        self.autoLearningAppliesImmediately = autoLearningAppliesImmediately
        self.onLearningEvent = onLearningEvent
        self.onDiagnostic = onDiagnostic
        self.onSaveFailure = onSaveFailure
    }

    func observeInsertedText(
        _ insertedText: String,
        context: CorrectionContext,
        appliedEvents: [CorrectionEvent]
    ) async {
        guard isAutoLearningEnabled() else {
            reportDiagnostic(.disabled, insertedText: insertedText, context: context)
            return
        }
        guard context.mode == .dictation,
              context.isFinalTranscript,
              !context.isSecureField,
              let bundleIdentifier = context.bundleIdentifier
        else {
            reportDiagnostic(.unsupportedContext, insertedText: insertedText, context: context)
            return
        }
        guard !insertedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            reportDiagnostic(.emptyInsertedText, insertedText: insertedText, context: context)
            return
        }
        guard let baseline = await captureSettledBaseline(containing: insertedText) else {
            reportDiagnostic(.baselineMissingInsertedText, insertedText: insertedText, context: context)
            return
        }

        pendingCommitSignal = nil
        commitObserver?.onSignal = { [weak self] signal in
            self?.pendingCommitSignal = signal
        }
        commitObserver?.start()
        defer {
            commitObserver?.stop()
            commitObserver?.onSignal = nil
            pendingCommitSignal = nil
        }

        var elapsed: Duration = .zero
        var finalObservation: FocusedTextObservation?
        var latestPairs: [LearnedCorrectionPair] = []
        for offset in pollOffsets {
            let sleepDuration = offset > elapsed ? offset - elapsed : .zero
            await clock.sleep(for: sleepDuration)
            elapsed = offset

            if let pendingCommitSignal {
                if pendingCommitSignal != .activeApplicationChanged,
                   let observation = tracker.recapture(matching: baseline) {
                    finalObservation = observation
                    let pairs = learnedPairs(
                        insertedText: insertedText,
                        baseline: baseline,
                        observation: observation,
                        appliedEvents: appliedEvents
                    )
                    if !pairs.isEmpty {
                        latestPairs = pairs
                    }
                }
                break
            }

            guard !Task.isCancelled else {
                return
            }
            guard let observation = tracker.recapture(matching: baseline) else {
                reportDiagnostic(.recaptureLostFocus, insertedText: insertedText, context: context)
                return
            }
            finalObservation = observation
            let pairs = learnedPairs(
                insertedText: insertedText,
                baseline: baseline,
                observation: observation,
                appliedEvents: appliedEvents
            )
            if !pairs.isEmpty {
                latestPairs = pairs
            }
            if pendingCommitSignal != nil {
                break
            }
        }

        let pairs: [LearnedCorrectionPair]
        if pendingCommitSignal != nil {
            pairs = latestPairs
        } else if let finalObservation {
            pairs = learnedPairs(
                insertedText: insertedText,
                baseline: baseline,
                observation: finalObservation,
                appliedEvents: appliedEvents
            )
        } else {
            pairs = []
        }
        guard !pairs.isEmpty else {
            if let finalObservation,
               finalObservation.value != baseline.value {
                reportDiagnostic(.noHighConfidenceCorrection, insertedText: insertedText, context: context)
            } else {
                reportDiagnostic(.noUserEditObserved, insertedText: insertedText, context: context)
            }
            return
        }

        for pair in pairs {
            let activeImmediately = autoLearningAppliesImmediately()
            let now = Date()
            do {
                let scope = RuleScope.application(bundleIdentifier: bundleIdentifier)
                let target = try targetTerm(
                    text: pair.replacement,
                    scope: scope,
                    activeImmediately: activeImmediately,
                    now: now
                )
                let rule = CorrectionRule(
                    targetID: target.id,
                    original: pair.original,
                    replacement: target.text,
                    matchPolicy: .boundary,
                    scope: scope,
                    lifecycle: activeImmediately ? .active : .candidate,
                    source: .automaticLearning,
                    confidence: activeImmediately ? 0.90 : 0.40,
                    observedCount: 1,
                    providerID: context.providerID,
                    modelID: context.modelID,
                    language: context.language,
                    createdAt: now,
                    updatedAt: now
                )
                try repository.save(rule)
                onLearningEvent(
                    CorrectionObservationLearningEvent(
                        original: pair.original,
                        replacement: target.text,
                        lifecycle: rule.lifecycle,
                        scope: rule.scope,
                        ruleID: rule.id,
                        targetID: target.id
                    )
                )
            } catch {
                reportDiagnostic(.saveFailed, insertedText: insertedText, context: context)
                onSaveFailure(error)
            }
        }
    }

    private func reportDiagnostic(
        _ reason: CorrectionObservationDiagnostic.Reason,
        insertedText: String,
        context: CorrectionContext
    ) {
        onDiagnostic(
            CorrectionObservationDiagnostic(
                reason: reason,
                insertedText: insertedText,
                bundleIdentifier: context.bundleIdentifier
            )
        )
    }

    private func learnedPairs(
        insertedText: String,
        baseline: FocusedTextObservation,
        observation: FocusedTextObservation,
        appliedEvents: [CorrectionEvent]
    ) -> [LearnedCorrectionPair] {
        guard observation.value != baseline.value else {
            return []
        }
        return extractor.extract(
            insertedText: insertedText,
            baselineText: baseline.value,
            editedText: observation.value,
            appliedCorrectionRanges: appliedEvents.map(\.range)
        )
    }

    private func captureSettledBaseline(containing insertedText: String) async -> FocusedTextObservation? {
        for delay in baselineCaptureDelays {
            await clock.sleep(for: delay)
            guard !Task.isCancelled else { return nil }
            guard let baseline = tracker.captureBaseline(),
                  baseline.value.contains(insertedText)
            else {
                continue
            }
            return baseline
        }
        return nil
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
