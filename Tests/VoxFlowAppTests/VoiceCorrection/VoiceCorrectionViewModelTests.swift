import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

@MainActor
final class VoiceCorrectionViewModelTests: XCTestCase {
    func testDefaultSwitchesAreLoadedFromSettingsDefaults() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = VoiceCorrectionViewModel(
            environment: environment,
            targetProvider: StaticDictationTargetProvider(target: DictationTarget(bundleID: "com.example.Cursor", appName: "Cursor"))
        )

        XCTAssertTrue(viewModel.isEnabled)
        XCTAssertTrue(viewModel.autoLearningEnabled)
        XCTAssertTrue(viewModel.autoLearningAppliesImmediately)
        XCTAssertFalse(viewModel.shadowMode)
    }

    func testSwitchesPersistThroughSettingsRepository() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = VoiceCorrectionViewModel(environment: environment)

        viewModel.setEnabled(false)
        viewModel.setAutoLearningEnabled(false)
        viewModel.setAutoLearningAppliesImmediately(false)
        viewModel.setShadowMode(true)

        XCTAssertFalse(viewModel.isEnabled)
        XCTAssertFalse(viewModel.autoLearningEnabled)
        XCTAssertFalse(viewModel.autoLearningAppliesImmediately)
        XCTAssertTrue(viewModel.shadowMode)
        XCTAssertEqual(
            try environment.settingsRepository.value(forKey: VoiceCorrectionSettingsKey.shadowMode.rawValue),
            #"{"value":true}"#
        )
    }

    func testRuleOperationsRefreshLists() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = VoiceCorrectionViewModel(
            environment: environment,
            targetProvider: StaticDictationTargetProvider(target: DictationTarget(bundleID: "com.example.Cursor", appName: "Cursor"))
        )

        var draft = viewModel.draftForNewRule()
        draft.original = "q 问"
        draft.replacement = "Qwen"
        viewModel.saveRule(draft)

        XCTAssertEqual(viewModel.activeRules.map(\.original), ["q 问"])

        let saved = try XCTUnwrap(viewModel.activeRules.first)
        viewModel.disableRule(saved)

        XCTAssertTrue(viewModel.activeRules.isEmpty)
        XCTAssertEqual(viewModel.suspendedRules.map(\.original), ["q 问"])

        viewModel.deleteRule(try XCTUnwrap(viewModel.rules.first))
        XCTAssertTrue(viewModel.rules.isEmpty)
    }

    func testLoadIfNeededDoesNotReloadAlreadyLoadedRules() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.correctionRuleRepository.save(
            CorrectionRule(
                original: "initial",
                replacement: "Initial",
                updatedAt: Date(timeIntervalSince1970: 100)
            )
        )
        let viewModel = VoiceCorrectionViewModel(environment: environment)

        try environment.correctionRuleRepository.save(
            CorrectionRule(
                original: "later",
                replacement: "Later",
                updatedAt: Date(timeIntervalSince1970: 200)
            )
        )
        viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.rules.map(\.original), ["initial"])

        viewModel.load()

        XCTAssertEqual(viewModel.rules.map(\.original), ["later", "initial"])
    }

    func testCandidateCanBeAcceptedAndClearAllDeletesRules() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = VoiceCorrectionViewModel(environment: environment)
        let candidate = CorrectionRule(
            original: "queue win",
            replacement: "Qwen",
            lifecycle: .candidate,
            source: .automaticLearning,
            confidence: 0.40
        )
        try environment.correctionRuleRepository.save(candidate)
        viewModel.load()

        XCTAssertEqual(viewModel.candidateRules.count, 1)
        viewModel.acceptCandidate(try XCTUnwrap(viewModel.candidateRules.first))

        XCTAssertEqual(viewModel.candidateRules.count, 0)
        XCTAssertEqual(viewModel.activeRules.count, 1)
        XCTAssertEqual(viewModel.activeRules.first?.confidence, 0.90)

        viewModel.clearAllRules()
        XCTAssertTrue(viewModel.rules.isEmpty)
    }

    func testUndoRecentAutomaticLearningDeletesLatestAutomaticRule() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = VoiceCorrectionViewModel(environment: environment)
        let older = CorrectionRule(
            original: "older",
            replacement: "Older",
            source: .automaticLearning,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = CorrectionRule(
            original: "newer",
            replacement: "Newer",
            source: .automaticLearning,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        try environment.correctionRuleRepository.save(older)
        try environment.correctionRuleRepository.save(newer)
        viewModel.load()

        viewModel.undoRecentLearning()

        XCTAssertEqual(viewModel.rules.map(\.original), ["older"])
    }

    func testProcessorHonorsDisabledAndShadowModeSettings() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.correctionRuleRepository.save(
            CorrectionRule(original: "q 问", replacement: "Qwen")
        )
        let processor = VoiceCorrectionTextProcessor(
            snapshotProvider: environment.correctionSnapshotProvider,
            settingsRepository: environment.settingsRepository
        )
        let context = CorrectionContext(
            mode: .dictation,
            providerID: "test",
            modelID: nil,
            language: "zh-Hans",
            bundleIdentifier: "com.apple.TextEdit",
            isFinalTranscript: true,
            isSecureField: false
        )

        try VoiceCorrectionSettingsStore.setBool(.enabled, value: false, repository: environment.settingsRepository)
        XCTAssertEqual(processor.process("q 问", context: context).correctedText, "q 问")

        try VoiceCorrectionSettingsStore.setBool(.enabled, value: true, repository: environment.settingsRepository)
        try VoiceCorrectionSettingsStore.setBool(.shadowMode, value: true, repository: environment.settingsRepository)
        let shadowResult = processor.process("q 问", context: context)

        XCTAssertEqual(shadowResult.correctedText, "q 问")
        XCTAssertEqual(shadowResult.events.map(\.replacement), ["Qwen"])
    }
}
