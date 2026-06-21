import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

@MainActor
final class CorrectionObservationCoordinatorTests: XCTestCase {
    func testPollsAtTwoFiveAndTenSecondsAndCreatesActiveAppScopedRule() async throws {
        let observer = FakeFocusedTextObserver()
        observer.captureResult = observation(value: "use q 问 today")
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
            repository: repository,
            appliesImmediately: true
        )

        await coordinator.observeInsertedText(
            "q 问",
            context: context(),
            appliedEvents: []
        )

        let sleeps = await clock.recordedSleeps()
        XCTAssertEqual(sleeps, [.seconds(2), .seconds(3), .seconds(5)])
        let saved = try XCTUnwrap(repository.savedRules.first)
        XCTAssertEqual(saved.original, "q 问")
        XCTAssertEqual(saved.replacement, "Qwen")
        XCTAssertEqual(saved.lifecycle, .active)
        XCTAssertEqual(saved.scope, .application(bundleIdentifier: "com.cursor.Cursor"))
        XCTAssertEqual(saved.source, .automaticLearning)
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

    private func makeCoordinator(
        observer: FakeFocusedTextObserver,
        clock: FakeCorrectionObservationClock = FakeCorrectionObservationClock(),
        repository: CapturingCorrectionRuleRepository,
        autoLearningEnabled: Bool = true,
        appliesImmediately: Bool = true
    ) -> CorrectionObservationCoordinator {
        CorrectionObservationCoordinator(
            observer: observer,
            clock: clock,
            repository: repository,
            isAutoLearningEnabled: { autoLearningEnabled },
            autoLearningAppliesImmediately: { appliesImmediately }
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
