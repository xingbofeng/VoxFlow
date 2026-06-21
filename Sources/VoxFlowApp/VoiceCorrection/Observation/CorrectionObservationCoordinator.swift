import Foundation
import VoxFlowVoiceCorrection

@MainActor
final class CorrectionObservationCoordinator {
    private let tracker: FocusedTextObservationTracker
    private let clock: any CorrectionObservationClock
    private let repository: any CorrectionRuleRepository
    private let extractor: HighConfidenceCorrectionExtractor
    private let pollOffsets: [Duration]
    private let isAutoLearningEnabled: () -> Bool
    private let autoLearningAppliesImmediately: () -> Bool

    init(
        observer: any FocusedTextObserving,
        clock: any CorrectionObservationClock = ContinuousCorrectionObservationClock(),
        repository: any CorrectionRuleRepository,
        extractor: HighConfidenceCorrectionExtractor = HighConfidenceCorrectionExtractor(),
        pollOffsets: [Duration] = CorrectionObservationPollSchedule.defaultOffsets,
        isAutoLearningEnabled: @escaping () -> Bool,
        autoLearningAppliesImmediately: @escaping () -> Bool
    ) {
        self.tracker = FocusedTextObservationTracker(observer: observer)
        self.clock = clock
        self.repository = repository
        self.extractor = extractor
        self.pollOffsets = pollOffsets
        self.isAutoLearningEnabled = isAutoLearningEnabled
        self.autoLearningAppliesImmediately = autoLearningAppliesImmediately
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
              !insertedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let baseline = tracker.captureBaseline()
        else {
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
            let rule = CorrectionRule(
                original: pair.original,
                replacement: pair.replacement,
                matchPolicy: .boundary,
                scope: .application(bundleIdentifier: bundleIdentifier),
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
            try? repository.save(rule)
        }
    }
}
