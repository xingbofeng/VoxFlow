import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

@MainActor
final class VoiceCorrectionE2ETests: XCTestCase {
    func testDictationFinalRunsLLMThenCorrectionThenInsertion() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.correctionRuleRepository.save(
            CorrectionRule(original: "q 问", replacement: "Qwen")
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: E2ERefiner(result: .success("please use q 问")),
            voiceCorrectionProcessor: VoiceCorrectionTextProcessor(
                snapshotProvider: environment.correctionSnapshotProvider,
                settingsRepository: environment.settingsRepository
            )
        )
        let insertion = E2EFakeTextInsertion()

        let result = await pipeline.process(
            "please use queue win",
            target: nil,
            correctionContext: context(mode: .dictation)
        )
        await insertion.insert(result.finalText)

        XCTAssertEqual(result.rawText, "please use queue win")
        XCTAssertEqual(result.finalText, "please use Qwen")
        XCTAssertEqual(result.correctionEvents.map(\.replacement), ["Qwen"])
        XCTAssertEqual(insertion.insertedTexts, ["please use Qwen"])
    }

    func testCommandModeDoesNotRunCorrectionBeforeInsertion() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.correctionRuleRepository.save(
            CorrectionRule(original: "q 问", replacement: "Qwen")
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: E2ERefiner(isEnabled: false, result: .success("unused")),
            voiceCorrectionProcessor: VoiceCorrectionTextProcessor(
                snapshotProvider: environment.correctionSnapshotProvider,
                settingsRepository: environment.settingsRepository
            )
        )
        let insertion = E2EFakeTextInsertion()

        let result = await pipeline.process(
            "q 问",
            target: nil,
            correctionContext: context(mode: .command)
        )
        await insertion.insert(result.finalText)

        XCTAssertEqual(result.finalText, "q 问")
        XCTAssertTrue(result.correctionEvents.isEmpty)
        XCTAssertEqual(insertion.insertedTexts, ["q 问"])
    }

    func testLLMFailureStillRunsCorrection() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.correctionRuleRepository.save(
            CorrectionRule(original: "q 问", replacement: "Qwen")
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: E2ERefiner(result: .failure(E2EError.expected)),
            voiceCorrectionProcessor: VoiceCorrectionTextProcessor(
                snapshotProvider: environment.correctionSnapshotProvider,
                settingsRepository: environment.settingsRepository
            )
        )

        let result = await pipeline.process(
            "q 问",
            target: nil,
            correctionContext: context(mode: .dictation)
        )

        XCTAssertEqual(result.finalText, "Qwen")
        XCTAssertTrue(result.warnings.contains("llm_refinement_failed"))
        XCTAssertEqual(result.correctionEvents.map(\.replacement), ["Qwen"])
    }

    func testManualRuleMatchesASRTokenWhenWhitespaceIsMissing() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.correctionRuleRepository.save(
            CorrectionRule(original: "q 问", replacement: "Qwen")
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: E2ERefiner(isEnabled: false, result: .success("unused")),
            voiceCorrectionProcessor: VoiceCorrectionTextProcessor(
                snapshotProvider: environment.correctionSnapshotProvider,
                settingsRepository: environment.settingsRepository
            )
        )

        let result = await pipeline.process(
            "Q问。",
            target: nil,
            correctionContext: context(mode: .dictation)
        )

        XCTAssertEqual(result.finalText, "Qwen。")
        XCTAssertEqual(result.correctionEvents.map(\.original), ["Q问"])
        XCTAssertEqual(result.correctionEvents.map(\.replacement), ["Qwen"])
    }

    func testObservationE2ELearnsActiveRuleAfterTwoFiveTenSecondPolling() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let observer = FakeFocusedTextObserver()
        observer.captureResult = observation(value: "use q 问 today")
        observer.recaptureResults = [
            observation(value: "use q 问 today"),
            observation(value: "use q 问 today"),
            observation(value: "use Qwen today"),
        ]
        let clock = FakeCorrectionObservationClock()
        let coordinator = CorrectionObservationCoordinator(
            observer: observer,
            clock: clock,
            repository: environment.correctionRuleRepository,
            targetRepository: environment.correctionTargetRepository,
            pollOffsets: [.seconds(2), .seconds(3), .seconds(5)],
            isAutoLearningEnabled: { true },
            autoLearningAppliesImmediately: { true }
        )

        await coordinator.observeInsertedText(
            "q 问",
            context: context(mode: .dictation),
            appliedEvents: []
        )

        let sleeps = await clock.recordedSleeps()
        XCTAssertEqual(sleeps, [.seconds(2), .seconds(1), .seconds(2)])
        let learned = try XCTUnwrap(try environment.correctionRuleRepository.list().first)
        XCTAssertEqual(learned.original, "q 问")
        XCTAssertEqual(learned.replacement, "Qwen")
        XCTAssertEqual(learned.lifecycle, .active)
        XCTAssertEqual(learned.scope, .application(bundleIdentifier: "com.cursor.Cursor"))
    }

    func testAutomaticLearningLearnsTokenhubCorrectionAfterManualEdit() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let observer = FakeFocusedTextObserver()
        observer.captureResult = observation(value: "投康 Hub is ready")
        observer.recaptureResults = [observation(value: "tokenhub is ready")]
        let coordinator = CorrectionObservationCoordinator(
            observer: observer,
            clock: FakeCorrectionObservationClock(),
            repository: environment.correctionRuleRepository,
            targetRepository: environment.correctionTargetRepository,
            pollOffsets: [.seconds(1)],
            isAutoLearningEnabled: { true },
            autoLearningAppliesImmediately: { true }
        )

        await coordinator.observeInsertedText(
            "投康 Hub",
            context: context(mode: .dictation),
            appliedEvents: []
        )

        let rules = try environment.correctionRuleRepository.list()
        XCTAssertTrue(rules.contains { rule in
            rule.original == "投康 Hub" &&
                rule.replacement == "tokenhub" &&
                rule.scope == .application(bundleIdentifier: "com.cursor.Cursor") &&
                rule.lifecycle == .active
        })

        let repeatedResult = VoiceCorrectionTextProcessor(
            snapshotProvider: environment.correctionSnapshotProvider,
            settingsRepository: environment.settingsRepository
        ).process(
            "投康 Hub",
            context: context(mode: .dictation)
        )
        XCTAssertEqual(repeatedResult.correctedText, "tokenhub")
    }

    func testObservationE2ECancelsWhenFocusChangesAndCanCreateCandidate() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let focusChangedObserver = FakeFocusedTextObserver()
        focusChangedObserver.captureResult = observation(value: "use q 问 today")
        focusChangedObserver.recaptureResult = FocusedTextObservation(
            elementIdentity: "other-editor",
            value: "use Qwen today",
            selectedRange: CorrectionTextRange(location: 14, length: 0),
            bundleIdentifier: "com.cursor.Cursor",
            isSecureField: false
        )
        let cancelledCoordinator = CorrectionObservationCoordinator(
            observer: focusChangedObserver,
            clock: FakeCorrectionObservationClock(),
            repository: environment.correctionRuleRepository,
            targetRepository: environment.correctionTargetRepository,
            isAutoLearningEnabled: { true },
            autoLearningAppliesImmediately: { true }
        )

        await cancelledCoordinator.observeInsertedText(
            "q 问",
            context: context(mode: .dictation),
            appliedEvents: []
        )
        XCTAssertTrue(try environment.correctionRuleRepository.list().isEmpty)

        let candidateObserver = FakeFocusedTextObserver()
        candidateObserver.captureResult = observation(value: "use queue win today")
        candidateObserver.recaptureResults = [
            observation(value: "use queue win today"),
            observation(value: "use queue win today"),
            observation(value: "use Qwen today"),
        ]
        let candidateCoordinator = CorrectionObservationCoordinator(
            observer: candidateObserver,
            clock: FakeCorrectionObservationClock(),
            repository: environment.correctionRuleRepository,
            targetRepository: environment.correctionTargetRepository,
            pollOffsets: [.seconds(2), .seconds(3), .seconds(5)],
            isAutoLearningEnabled: { true },
            autoLearningAppliesImmediately: { false }
        )

        await candidateCoordinator.observeInsertedText(
            "queue win",
            context: context(mode: .dictation),
            appliedEvents: []
        )

        let candidate = try XCTUnwrap(try environment.correctionRuleRepository.list().first)
        XCTAssertEqual(candidate.lifecycle, .candidate)
        XCTAssertEqual(candidate.original, "queue win")
        XCTAssertEqual(candidate.replacement, "Qwen")
    }

    private func context(mode: CorrectionInputMode) -> CorrectionContext {
        CorrectionContext(
            mode: mode,
            providerID: "apple",
            modelID: nil,
            language: "zh-Hans",
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

private final class E2EFakeTextInsertion {
    private(set) var insertedTexts: [String] = []

    func insert(_ text: String) async {
        insertedTexts.append(text)
    }
}

private final class E2ERefiner: TextRefining, @unchecked Sendable {
    let isEnabled: Bool
    let isConfigured = true
    let result: Result<String, Error>

    init(isEnabled: Bool = true, result: Result<String, Error>) {
        self.isEnabled = isEnabled
        self.result = result
    }

    func refine(_ text: String) async throws -> String {
        try result.get()
    }
}

private enum E2EError: Error {
    case expected
}
