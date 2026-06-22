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

@MainActor
final class CorrectionObservationCoordinator {
    private let tracker: FocusedTextObservationTracker
    private let clock: any CorrectionObservationClock
    private let repository: any CorrectionRuleRepository
    private let targetRepository: any CorrectionTargetRepository
    private let extractor: HighConfidenceCorrectionExtractor
    private let pollOffsets: [Duration]
    private let baselineCaptureDelays: [Duration]
    private let isAutoLearningEnabled: () -> Bool
    private let autoLearningAppliesImmediately: () -> Bool
    private let onSaveFailure: (Error) -> Void

    init(
        observer: any FocusedTextObserving,
        clock: any CorrectionObservationClock = ContinuousCorrectionObservationClock(),
        repository: any CorrectionRuleRepository,
        targetRepository: any CorrectionTargetRepository,
        extractor: HighConfidenceCorrectionExtractor = HighConfidenceCorrectionExtractor(),
        pollOffsets: [Duration] = CorrectionObservationPollSchedule.defaultOffsets,
        baselineCaptureDelays: [Duration] = [.milliseconds(150), .milliseconds(150), .milliseconds(200)],
        isAutoLearningEnabled: @escaping () -> Bool,
        autoLearningAppliesImmediately: @escaping () -> Bool,
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
        self.isAutoLearningEnabled = isAutoLearningEnabled
        self.autoLearningAppliesImmediately = autoLearningAppliesImmediately
        self.onSaveFailure = onSaveFailure
    }

    func observeInsertedText(
        _ insertedText: String,
        context: CorrectionContext,
        appliedEvents: [CorrectionEvent]
    ) async {
        guard isAutoLearningEnabled(),
              context.mode == .dictation,
              context.isFinalTranscript,
              !context.isSecureField,
              let bundleIdentifier = context.bundleIdentifier,
              !insertedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }
        guard let baseline = await captureSettledBaseline(containing: insertedText) else {
            return
        }

        var elapsed: Duration = .zero
        var finalObservation: FocusedTextObservation?
        for offset in pollOffsets {
            let sleepDuration = offset > elapsed ? offset - elapsed : .zero
            await clock.sleep(for: sleepDuration)
            elapsed = offset

            guard !Task.isCancelled,
                  let observation = tracker.recapture(matching: baseline)
            else {
                return
            }
            finalObservation = observation
        }

        guard let finalObservation,
              finalObservation.value != baseline.value
        else {
            return
        }

        let pairs = extractor.extract(
            insertedText: insertedText,
            baselineText: baseline.value,
            editedText: finalObservation.value,
            appliedCorrectionRanges: appliedEvents.map(\.range)
        )
        guard !pairs.isEmpty else {
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
            } catch {
                onSaveFailure(error)
            }
        }
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
