import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

@MainActor
final class CorrectionObservationCoordinatorTests: XCTestCase {
    func testPollsUntilThirtySecondsAndCreatesActiveAppScopedRule() async throws {
        let observer = FakeFocusedTextObserver()
        observer.captureResult = observation(value: "use q 问 today")
        observer.recaptureResults = (1...29).map { _ in observation(value: "use q 问 today") }
            + [observation(value: "use Qwen today")]
        let clock = FakeCorrectionObservationClock()
        let repository = CapturingCorrectionRuleRepository()
        let targetRepository = CapturingCorrectionTargetRepository()
        let coordinator = makeCoordinator(
            observer: observer,
            clock: clock,
            repository: repository,
            targetRepository: targetRepository,
            pollOffsets: CorrectionObservationPollSchedule.defaultOffsets,
            appliesImmediately: true
        )

        await coordinator.observeInsertedText(
            "q 问",
            context: context(),
            appliedEvents: []
        )

        let sleeps = await clock.recordedSleeps()
        XCTAssertEqual(sleeps, [.milliseconds(150)] + Array(repeating: .seconds(1), count: 30))
        let saved = try XCTUnwrap(repository.savedRules.first)
        XCTAssertEqual(saved.original, "q 问")
        XCTAssertEqual(saved.replacement, "Qwen")
        XCTAssertEqual(saved.lifecycle, .active)
        XCTAssertEqual(saved.scope, .application(bundleIdentifier: "com.cursor.Cursor"))
        XCTAssertEqual(saved.source, .automaticLearning)
        let target = try XCTUnwrap(targetRepository.savedTargets.first)
        XCTAssertEqual(target.text, "Qwen")
        XCTAssertEqual(target.scope, .application(bundleIdentifier: "com.cursor.Cursor"))
        XCTAssertEqual(saved.targetID, target.id)
    }

    func testAutomaticLearningReusesExistingTargetTerm() async throws {
        let observer = FakeFocusedTextObserver()
        observer.captureResult = observation(value: "use q 问 today")
        observer.recaptureResults = [
            observation(value: "use q 问 today"),
            observation(value: "use q 问 today"),
            observation(value: "use Qwen today"),
        ]
        let repository = CapturingCorrectionRuleRepository()
        let existingTarget = CorrectionTargetTerm(
            text: "Qwen",
            scope: .application(bundleIdentifier: "com.cursor.Cursor"),
            lifecycle: .active,
            source: .manual
        )
        let targetRepository = CapturingCorrectionTargetRepository(initialTargets: [existingTarget])
        let coordinator = makeCoordinator(
            observer: observer,
            repository: repository,
            targetRepository: targetRepository
        )

        await coordinator.observeInsertedText(
            "q 问",
            context: context(),
            appliedEvents: []
        )

        XCTAssertEqual(repository.savedRules.first?.targetID, existingTarget.id)
        XCTAssertEqual(targetRepository.createdTargetCount, 0)
    }

    func testAutoLearningDisabledDoesNotStartObservation() async {
        let observer = FakeFocusedTextObserver()
        let repository = CapturingCorrectionRuleRepository()
        let coordinator = makeCoordinator(
            observer: observer,
            repository: repository,
            autoLearningEnabled: false
        )

        await coordinator.observeInsertedText(
            "q 问",
            context: context(),
            appliedEvents: []
        )

        XCTAssertEqual(observer.captureCallCount, 0)
        XCTAssertTrue(repository.savedRules.isEmpty)
    }

    func testSecureFieldDoesNotCaptureOrLearn() async {
        let observer = FakeFocusedTextObserver()
        observer.captureResult = observation(value: "投康 Hub")
        let repository = CapturingCorrectionRuleRepository()
        var diagnostics: [CorrectionObservationDiagnostic] = []
        let coordinator = makeCoordinator(
            observer: observer,
            repository: repository,
            onDiagnostic: { diagnostics.append($0) }
        )

        await coordinator.observeInsertedText(
            "投康 Hub",
            context: CorrectionContext(
                mode: .dictation,
                providerID: "apple",
                modelID: nil,
                language: "zh-Hans",
                bundleIdentifier: "com.apple.TextEdit",
                isFinalTranscript: true,
                isSecureField: true
            ),
            appliedEvents: []
        )

        XCTAssertEqual(observer.captureCallCount, 0)
        XCTAssertTrue(repository.savedRules.isEmpty)
        XCTAssertEqual(diagnostics.last?.reason, .unsupportedContext)
    }

    func testDirectApplyDisabledCreatesCandidateRule() async throws {
        let observer = FakeFocusedTextObserver()
        observer.captureResult = observation(value: "use q 问 today")
        observer.recaptureResults = [
            observation(value: "use q 问 today"),
            observation(value: "use q 问 today"),
            observation(value: "use Qwen today"),
        ]
        let repository = CapturingCorrectionRuleRepository()
        let coordinator = makeCoordinator(
            observer: observer,
            repository: repository,
            appliesImmediately: false
        )

        await coordinator.observeInsertedText(
            "q 问",
            context: context(),
            appliedEvents: []
        )

        XCTAssertEqual(try XCTUnwrap(repository.savedRules.first).lifecycle, .candidate)
    }

    func testAppliedCorrectionOverlapGuardPreventsFeedbackLoop() async {
        let observer = FakeFocusedTextObserver()
        observer.captureResult = observation(value: "use q 问 today")
        observer.recaptureResults = [
            observation(value: "use q 问 today"),
            observation(value: "use q 问 today"),
            observation(value: "use Qwen today"),
        ]
        let repository = CapturingCorrectionRuleRepository()
        let coordinator = makeCoordinator(observer: observer, repository: repository)

        await coordinator.observeInsertedText(
            "q 问",
            context: context(),
            appliedEvents: [
                CorrectionEvent(
                    ruleID: UUID(),
                    original: "q 问",
                    replacement: "Qwen",
                    range: CorrectionTextRange(location: 4, length: 3),
                    scope: .application(bundleIdentifier: "com.cursor.Cursor"),
                    source: .manual
                ),
            ]
        )

        XCTAssertTrue(repository.savedRules.isEmpty)
    }

    func testWaitsForInsertedTextBeforeCapturingBaseline() async throws {
        let observer = FakeFocusedTextObserver()
        observer.captureResults = [
            observation(value: "use today"),
            observation(value: "use q 问 today"),
        ]
        observer.recaptureResults = [
            observation(value: "use q 问 today"),
            observation(value: "use q 问 today"),
            observation(value: "use Qwen today"),
        ]
        let clock = FakeCorrectionObservationClock()
        let repository = CapturingCorrectionRuleRepository()
        let coordinator = makeCoordinator(
            observer: observer,
            clock: clock,
            repository: repository
        )

        await coordinator.observeInsertedText(
            "q 问",
            context: context(),
            appliedEvents: []
        )

        XCTAssertEqual(observer.captureCallCount, 2)
        XCTAssertEqual(try XCTUnwrap(repository.savedRules.first).replacement, "Qwen")
    }

    func testSaveFailureIsReportedForDiagnostics() async {
        let observer = FakeFocusedTextObserver()
        observer.captureResult = observation(value: "use q 问 today")
        observer.recaptureResults = [
            observation(value: "use q 问 today"),
            observation(value: "use q 问 today"),
            observation(value: "use Qwen today"),
        ]
        let repository = ThrowingCorrectionRuleRepository()
        var reportedErrors: [String] = []
        let coordinator = makeCoordinator(
            observer: observer,
            repository: repository,
            onSaveFailure: { reportedErrors.append($0.localizedDescription) }
        )

        await coordinator.observeInsertedText(
            "q 问",
            context: context(),
            appliedEvents: []
        )

        XCTAssertEqual(reportedErrors, [TestRepositoryError.saveFailed.localizedDescription])
    }

    func testReturnSignalCommitsLatestHighConfidenceCorrectionBeforeThirtySecondWindowEnds() async throws {
        let observer = FakeFocusedTextObserver()
        observer.captureResult = observation(value: "投康 Hub works")
        observer.recaptureResults = [
            observation(value: "tokenhub works"),
            observation(value: "tokenhub works"),
            observation(value: "tokenhub works"),
        ]
        let commitObserver = FakeCorrectionObservationCommitObserver()
        observer.onRecapture = {
            commitObserver.emit(.returnKey)
        }
        let clock = FakeCorrectionObservationClock()
        let repository = CapturingCorrectionRuleRepository()
        let coordinator = makeCoordinator(
            observer: observer,
            clock: clock,
            repository: repository,
            pollOffsets: [.seconds(1), .seconds(2), .seconds(3)],
            commitObserver: commitObserver
        )

        await coordinator.observeInsertedText(
            "投康 Hub",
            context: context(),
            appliedEvents: []
        )

        let saved = try XCTUnwrap(repository.savedRules.first)
        XCTAssertEqual(saved.original, "投康 Hub")
        XCTAssertEqual(saved.replacement, "tokenhub")
        XCTAssertEqual(saved.lifecycle, .active)
        let sleeps = await clock.recordedSleeps()
        XCTAssertEqual(sleeps, [.milliseconds(150), .seconds(1)])
        XCTAssertTrue(commitObserver.didStart)
        XCTAssertTrue(commitObserver.didStop)
    }

    func testReturnSignalRecapturesEditMadeAfterPreviousPollBeforeCommitting() async throws {
        let observer = FakeFocusedTextObserver()
        observer.captureResult = observation(value: "投康 Hub works")
        observer.recaptureResults = [observation(value: "tokenhub works")]
        let commitObserver = FakeCorrectionObservationCommitObserver()
        let clock = SignalingCorrectionObservationClock { duration in
            guard duration == .seconds(1) else { return }
            await commitObserver.emit(.returnKey)
        }
        let repository = CapturingCorrectionRuleRepository()
        let coordinator = makeCoordinator(
            observer: observer,
            clock: clock,
            repository: repository,
            pollOffsets: [.seconds(1), .seconds(2)],
            commitObserver: commitObserver
        )

        await coordinator.observeInsertedText(
            "投康 Hub",
            context: context(),
            appliedEvents: []
        )

        let saved = try XCTUnwrap(repository.savedRules.first)
        XCTAssertEqual(saved.original, "投康 Hub")
        XCTAssertEqual(saved.replacement, "tokenhub")
        XCTAssertEqual(observer.recaptureBaselines.count, 1)
    }

    func testActiveApplicationChangedCommitsLatestSuggestionBeforeFocusIsLost() async throws {
        let observer = FakeFocusedTextObserver()
        observer.captureResult = observation(value: "投康 Hub works")
        observer.recaptureResults = [
            observation(value: "tokenhub works"),
            observation(value: "tokenhub works"),
        ]
        let commitObserver = FakeCorrectionObservationCommitObserver()
        observer.onRecapture = {
            commitObserver.emit(.activeApplicationChanged)
        }
        let repository = CapturingCorrectionRuleRepository()
        let coordinator = makeCoordinator(
            observer: observer,
            repository: repository,
            pollOffsets: [.seconds(1), .seconds(2)],
            commitObserver: commitObserver
        )

        await coordinator.observeInsertedText(
            "投康 Hub",
            context: context(),
            appliedEvents: []
        )

        XCTAssertEqual(repository.savedRules.first?.original, "投康 Hub")
        XCTAssertEqual(repository.savedRules.first?.replacement, "tokenhub")
    }

    func testSaveSuccessReportsUserVisibleLearningEvent() async throws {
        let observer = FakeFocusedTextObserver()
        observer.captureResult = observation(value: "投康 Hub works")
        observer.recaptureResults = [observation(value: "tokenhub works")]
        let repository = CapturingCorrectionRuleRepository()
        var events: [CorrectionObservationLearningEvent] = []
        let coordinator = makeCoordinator(
            observer: observer,
            repository: repository,
            pollOffsets: [.seconds(1)],
            onLearningEvent: { events.append($0) }
        )

        await coordinator.observeInsertedText(
            "投康 Hub",
            context: context(),
            appliedEvents: []
        )

        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.original, "投康 Hub")
        XCTAssertEqual(event.replacement, "tokenhub")
        XCTAssertEqual(event.lifecycle, .active)
        XCTAssertEqual(event.message, "已自动学习：投康 Hub → tokenhub")
    }

    func testBaselineCaptureFailureReportsDiagnostic() async {
        let observer = FakeFocusedTextObserver()
        observer.captureResults = [nil, nil, nil]
        var diagnostics: [CorrectionObservationDiagnostic] = []
        let coordinator = makeCoordinator(
            observer: observer,
            repository: CapturingCorrectionRuleRepository(),
            onDiagnostic: { diagnostics.append($0) }
        )

        await coordinator.observeInsertedText(
            "投康 Hub",
            context: context(),
            appliedEvents: []
        )

        XCTAssertEqual(diagnostics.last?.reason, .baselineMissingInsertedText)
        XCTAssertEqual(diagnostics.last?.insertedText, "投康 Hub")
        XCTAssertEqual(diagnostics.last?.bundleIdentifier, "com.cursor.Cursor")
    }

    private func makeCoordinator(
        observer: FakeFocusedTextObserver,
        clock: any CorrectionObservationClock = FakeCorrectionObservationClock(),
        repository: any CorrectionRuleRepository,
        targetRepository: any CorrectionTargetRepository = CapturingCorrectionTargetRepository(),
        pollOffsets: [Duration] = [.seconds(1), .seconds(2), .seconds(3)],
        commitObserver: (any CorrectionObservationCommitObserving)? = nil,
        autoLearningEnabled: Bool = true,
        appliesImmediately: Bool = true,
        onLearningEvent: @escaping (CorrectionObservationLearningEvent) -> Void = { _ in },
        onDiagnostic: @escaping (CorrectionObservationDiagnostic) -> Void = { _ in },
        onSaveFailure: @escaping (Error) -> Void = { _ in }
    ) -> CorrectionObservationCoordinator {
        CorrectionObservationCoordinator(
            observer: observer,
            clock: clock,
            repository: repository,
            targetRepository: targetRepository,
            pollOffsets: pollOffsets,
            commitObserver: commitObserver,
            isAutoLearningEnabled: { autoLearningEnabled },
            autoLearningAppliesImmediately: { appliesImmediately },
            onLearningEvent: onLearningEvent,
            onDiagnostic: onDiagnostic,
            onSaveFailure: onSaveFailure
        )
    }

    private func context() -> CorrectionContext {
        CorrectionContext(
            mode: .dictation,
            providerID: "apple",
            modelID: nil,
            language: "en",
            bundleIdentifier: "com.cursor.Cursor",
            isFinalTranscript: true,
            isSecureField: false
        )
    }

    private func observation(value: String) -> FocusedTextObservation {
        FocusedTextObservation(
            elementIdentity: "focused-editor",
            value: value,
            selectedRange: CorrectionTextRange(location: value.utf16.count, length: 0),
            bundleIdentifier: "com.cursor.Cursor",
            isSecureField: false
        )
    }
}

@MainActor
private final class FakeCorrectionObservationCommitObserver: CorrectionObservationCommitObserving {
    var onSignal: ((CorrectionObservationCommitSignal) -> Void)?
    private(set) var didStart = false
    private(set) var didStop = false

    func start() {
        didStart = true
    }

    func stop() {
        didStop = true
    }

    func emit(_ signal: CorrectionObservationCommitSignal) {
        onSignal?(signal)
    }
}

private actor SignalingCorrectionObservationClock: CorrectionObservationClock {
    private let onSleep: @Sendable (Duration) async -> Void

    init(onSleep: @escaping @Sendable (Duration) async -> Void) {
        self.onSleep = onSleep
    }

    func sleep(for duration: Duration) async {
        await onSleep(duration)
    }
}

private final class CapturingCorrectionRuleRepository: CorrectionRuleRepository {
    private(set) var savedRules: [CorrectionRule] = []

    func list() throws -> [CorrectionRule] {
        savedRules
    }

    func save(_ rule: CorrectionRule) throws {
        savedRules.append(rule)
    }

    func rule(id: UUID) throws -> CorrectionRule? {
        savedRules.first { $0.id == id }
    }

    func setEnabled(_ isEnabled: Bool, id: UUID, updatedAt: Date) throws {}

    func delete(id: UUID) throws {}

    func clearAll() throws {
        savedRules.removeAll()
    }
}

private final class CapturingCorrectionTargetRepository: CorrectionTargetRepository {
    private var targets: [CorrectionTargetTerm]
    private let initialTargetIDs: Set<UUID>
    private(set) var savedTargets: [CorrectionTargetTerm] = []

    init(initialTargets: [CorrectionTargetTerm] = []) {
        self.targets = initialTargets
        self.initialTargetIDs = Set(initialTargets.map(\.id))
    }

    var createdTargetCount: Int {
        savedTargets.filter { !initialTargetIDs.contains($0.id) }.count
    }

    func save(_ target: CorrectionTargetTerm) throws {
        savedTargets.append(target)
        if let index = targets.firstIndex(where: { $0.id == target.id }) {
            targets[index] = target
        } else {
            targets.append(target)
        }
    }

    func target(id: UUID) throws -> CorrectionTargetTerm? {
        targets.first { $0.id == id }
    }

    func list() throws -> [CorrectionTargetTerm] {
        targets
    }

    func delete(id: UUID) throws {
        targets.removeAll { $0.id == id }
    }
}

private final class ThrowingCorrectionRuleRepository: CorrectionRuleRepository {
    func list() throws -> [CorrectionRule] {
        []
    }

    func save(_ rule: CorrectionRule) throws {
        throw TestRepositoryError.saveFailed
    }

    func rule(id: UUID) throws -> CorrectionRule? {
        nil
    }

    func setEnabled(_ isEnabled: Bool, id: UUID, updatedAt: Date) throws {}

    func delete(id: UUID) throws {}

    func clearAll() throws {}
}

private enum TestRepositoryError: LocalizedError {
    case saveFailed

    var errorDescription: String? {
        "save failed"
    }
}
