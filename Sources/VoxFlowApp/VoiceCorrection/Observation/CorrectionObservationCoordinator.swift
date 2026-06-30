import Foundation
import VoxFlowVoiceCorrection

@MainActor
protocol CorrectionObservationScheduling: AnyObject {
    func scheduleObservation(
        insertedText: String,
        context: CorrectionContext,
        appliedEvents: [CorrectionEvent],
        baseline: FocusedTextObservation?,
        targetProcessID: Int?
    )
    func captureBaselineForObservation(targetProcessID: Int?) -> FocusedTextObservation?
    func recaptureBaselineForObservation(matching baseline: FocusedTextObservation) -> FocusedTextObservation?
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
        appliedEvents: [CorrectionEvent],
        baseline: FocusedTextObservation? = nil,
        targetProcessID: Int? = nil
    ) {
        let scheduledBaseline: FocusedTextObservation? =
            if let baseline, baseline.value.contains(insertedText) {
                baseline
            } else {
                coordinator.captureBaselineForObservation(targetProcessID: targetProcessID)
                    .flatMap { $0.value.contains(insertedText) ? $0 : nil }
            }
        currentTask?.cancel()
        currentTask = Task { @MainActor [coordinator] in
            await coordinator.observeInsertedText(
                insertedText,
                context: context,
                appliedEvents: appliedEvents,
                baseline: scheduledBaseline,
                targetProcessID: targetProcessID
            )
        }
    }

    func captureBaselineForObservation(targetProcessID: Int?) -> FocusedTextObservation? {
        coordinator.captureBaselineForObservation(targetProcessID: targetProcessID)
    }

    func recaptureBaselineForObservation(matching baseline: FocusedTextObservation) -> FocusedTextObservation? {
        coordinator.recaptureBaselineForObservation(matching: baseline)
    }
}

struct CorrectionObservationLearningItem: Equatable, Sendable {
    let original: String
    let replacement: String
    let lifecycle: RuleLifecycle
    let scope: RuleScope
    let ruleID: UUID
    let targetID: UUID

    init(
        original: String,
        replacement: String,
        lifecycle: RuleLifecycle,
        scope: RuleScope,
        ruleID: UUID,
        targetID: UUID
    ) {
        self.original = original
        self.replacement = replacement
        self.lifecycle = lifecycle
        self.scope = scope
        self.ruleID = ruleID
        self.targetID = targetID
    }

    init(rule: CorrectionRule, targetID: UUID) {
        self.init(
            original: rule.original,
            replacement: rule.replacement,
            lifecycle: rule.lifecycle,
            scope: rule.scope,
            ruleID: rule.id,
            targetID: targetID
        )
    }
}

struct CorrectionObservationLearningEvent: Equatable, Sendable {
    let items: [CorrectionObservationLearningItem]

    init(items: [CorrectionObservationLearningItem]) {
        self.items = items
    }

    init(
        original: String,
        replacement: String,
        lifecycle: RuleLifecycle,
        scope: RuleScope,
        ruleID: UUID,
        targetID: UUID
    ) {
        items = [
            CorrectionObservationLearningItem(
                original: original,
                replacement: replacement,
                lifecycle: lifecycle,
                scope: scope,
                ruleID: ruleID,
                targetID: targetID
            ),
        ]
    }

    var original: String { items.first?.original ?? "" }
    var replacement: String { items.first?.replacement ?? "" }
    var lifecycle: RuleLifecycle { items.first?.lifecycle ?? .candidate }
    var scope: RuleScope { items.first?.scope ?? .global }
    var ruleID: UUID? { items.first?.ruleID }
    var targetID: UUID? { items.first?.targetID }

    var message: String {
        guard items.count == 1, let item = items.first else {
            return L10n.format("correction.feedback.learning_batch_format", comment: "", items.count)
        }
        switch item.lifecycle {
        case .active:
            return L10n.format("correction.feedback.auto_learning_active_format", comment: "",
                item.original,
                item.replacement
            )
        case .candidate:
            return L10n.format("correction.feedback.auto_learning_pending_format", comment: "",
                item.original,
                item.replacement
            )
        case .suspended, .retired:
            return L10n.format("correction.feedback.auto_learning_recorded_format", comment: "",
                item.original,
                item.replacement
            )
        }
    }
}

extension Notification.Name {
    static let correctionObservationLearningEvent = Notification.Name("VoxFlow.CorrectionObservationLearningEvent")
    static let correctionVocabularyDidChange = Notification.Name("VoxFlow.CorrectionVocabularyDidChange")
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

private final class CorrectionObservationWakeCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var generation = 0

    func wait(for duration: Duration, clock: any CorrectionObservationClock) async {
        guard duration > .zero, !Task.isCancelled else { return }

        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                let waitID = self.startWait(continuation)
                let task = Task { [weak self] in
                    await clock.sleep(for: duration)
                    self?.resume(waitID: waitID)
                }
                self.storeSleepTask(task, waitID: waitID)
            }
        }, onCancel: {
            resume()
        })
    }

    func wake() {
        resume()
    }

    private func startWait(_ continuation: CheckedContinuation<Void, Never>) -> Int {
        lock.lock()
        generation += 1
        let waitID = generation
        self.continuation = continuation
        let oldTask = sleepTask
        sleepTask = nil
        lock.unlock()
        oldTask?.cancel()
        return waitID
    }

    private func storeSleepTask(_ task: Task<Void, Never>, waitID: Int) {
        lock.lock()
        guard waitID == generation, continuation != nil else {
            lock.unlock()
            task.cancel()
            return
        }
        sleepTask = task
        lock.unlock()
    }

    private func resume(waitID: Int? = nil) {
        lock.lock()
        if let waitID, waitID != generation {
            lock.unlock()
            return
        }
        generation += 1
        let task = sleepTask
        sleepTask = nil
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        task?.cancel()
        continuation?.resume()
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
        appliedEvents: [CorrectionEvent],
        baseline providedBaseline: FocusedTextObservation? = nil,
        targetProcessID: Int? = nil
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
        let baseline: FocusedTextObservation?
        if let providedBaseline, providedBaseline.value.contains(insertedText) {
            baseline = providedBaseline
        } else if let immediateBaseline = captureBaselineForObservation(targetProcessID: targetProcessID),
                  immediateBaseline.value.contains(insertedText) {
            baseline = immediateBaseline
        } else {
            baseline = await captureSettledBaseline(containing: insertedText, targetProcessID: targetProcessID)
        }
        guard let baseline else {
            reportDiagnostic(.baselineMissingInsertedText, insertedText: insertedText, context: context)
            return
        }

        pendingCommitSignal = nil
        let wakeCoordinator = CorrectionObservationWakeCoordinator()
        commitObserver?.onSignal = { [weak self, wakeCoordinator] signal in
            self?.pendingCommitSignal = signal
            wakeCoordinator.wake()
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
            if pendingCommitSignal == nil {
                await wakeCoordinator.wait(for: sleepDuration, clock: clock)
            }
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
            } else {
                latestPairs = []
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

        var learnedItems: [CorrectionObservationLearningItem] = []
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
                learnedItems.append(CorrectionObservationLearningItem(rule: rule, targetID: target.id))
            } catch {
                reportDiagnostic(.saveFailed, insertedText: insertedText, context: context)
                onSaveFailure(error)
            }
        }
        if !learnedItems.isEmpty {
            onLearningEvent(CorrectionObservationLearningEvent(items: learnedItems))
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

    private func captureSettledBaseline(
        containing insertedText: String,
        targetProcessID: Int?
    ) async -> FocusedTextObservation? {
        for delay in baselineCaptureDelays {
            await clock.sleep(for: delay)
            guard !Task.isCancelled else { return nil }
            guard let baseline = captureBaselineForObservation(targetProcessID: targetProcessID),
                  baseline.value.contains(insertedText) else {
                continue
            }
            return baseline
        }
        return nil
    }

    func captureBaselineForObservation(targetProcessID: Int?) -> FocusedTextObservation? {
        tracker.captureBaseline(targetProcessID: targetProcessID)
    }

    func recaptureBaselineForObservation(matching baseline: FocusedTextObservation) -> FocusedTextObservation? {
        tracker.recapture(matching: baseline)
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
