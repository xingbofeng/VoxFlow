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

    func testTargetRowsGroupAliasesByReplacement() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.correctionRuleRepository.save(
            CorrectionRule(original: "q 问", replacement: "Qwen", appliedCount: 2)
        )
        try environment.correctionRuleRepository.save(
            CorrectionRule(original: "queue win", replacement: "Qwen", appliedCount: 3)
        )
        try environment.correctionRuleRepository.save(
            CorrectionRule(original: "vox flow", replacement: "VoxFlow", appliedCount: 1)
        )

        let viewModel = VoiceCorrectionViewModel(environment: environment)

        XCTAssertEqual(viewModel.targetRows.map(\.targetText), ["Qwen", "VoxFlow"])
        XCTAssertEqual(viewModel.targetRows.first?.aliasPreview, "q 问、queue win")
        XCTAssertEqual(viewModel.targetRows.first?.correctionCountText, "5 次")
    }

    func testSearchAliasKeepsOwningTargetRowVisible() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.correctionRuleRepository.save(
            CorrectionRule(original: "q 问", replacement: "Qwen")
        )
        try environment.correctionRuleRepository.save(
            CorrectionRule(original: "vox flow", replacement: "VoxFlow")
        )
        let viewModel = VoiceCorrectionViewModel(environment: environment)

        viewModel.searchText = "q 问"

        XCTAssertEqual(viewModel.filteredTargetRows.map(\.targetText), ["Qwen"])
    }

    func testSelectedTargetExposesAliases() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.correctionRuleRepository.save(
            CorrectionRule(original: "q 问", replacement: "Qwen")
        )
        try environment.correctionRuleRepository.save(
            CorrectionRule(original: "Q问", replacement: "Qwen")
        )
        let viewModel = VoiceCorrectionViewModel(environment: environment)

        viewModel.selectTarget(viewModel.targetRows[0])

        XCTAssertEqual(viewModel.selectedTarget?.targetText, "Qwen")
        XCTAssertEqual(viewModel.selectedTargetAliases.map(\.original), ["q 问", "Q问"])
    }

    func testCreateTargetSavesAliasesAsRules() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = VoiceCorrectionViewModel(environment: environment)

        viewModel.createTarget(text: "Qwen", aliasesText: "q 问\nQ问\nqueue win")

        XCTAssertEqual(try environment.correctionTargetRepository.list().map(\.text), ["Qwen"])
        XCTAssertEqual(try environment.correctionRuleRepository.list().map(\.replacement), ["Qwen", "Qwen", "Qwen"])
        XCTAssertEqual(viewModel.targetRows.first?.targetText, "Qwen")
        XCTAssertEqual(Set(try XCTUnwrap(viewModel.targetRows.first?.aliases.map(\.original))), Set(["q 问", "Q问", "queue win"]))
    }

    func testCandidateTargetsAreHiddenFromPrimaryTargetList() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(
                text: "Qwen",
                lifecycle: .candidate,
                source: .automaticLearning
            )
        )
        let viewModel = VoiceCorrectionViewModel(environment: environment)

        XCTAssertEqual(viewModel.targetRows.map(\.targetText), ["Qwen"])
        XCTAssertTrue(viewModel.filteredTargetRows.isEmpty)
        XCTAssertEqual(viewModel.visibleTargetCount, 0)
        XCTAssertEqual(viewModel.visibleAliasCount, 0)
    }

    func testAddAliasesToSelectedTarget() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = VoiceCorrectionViewModel(environment: environment)
        viewModel.createTarget(text: "Qwen", aliasesText: "q 问")
        let target = try XCTUnwrap(viewModel.selectedTarget)

        viewModel.addAliases(to: target, aliasesText: "Q问\nqueue win")

        XCTAssertEqual(Set(viewModel.selectedTargetAliases.map(\.original)), Set(["q 问", "Q问", "queue win"]))
        XCTAssertEqual(viewModel.selectedTargetAliases.map(\.targetID), [target.id, target.id, target.id])
    }

    func testDuplicateAliasShowsConflictWithoutOverwriting() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = VoiceCorrectionViewModel(environment: environment)
        viewModel.createTarget(text: "Qwen", aliasesText: "q 问")
        let target = try XCTUnwrap(viewModel.selectedTarget)

        viewModel.addAliases(to: target, aliasesText: "q 问")

        XCTAssertEqual(viewModel.selectedTargetAliases.map(\.original), ["q 问"])
        XCTAssertEqual(viewModel.lastError, "误听写法已存在")
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

    func testUndoRecentLearningDeletesAutoCreatedEmptyTarget() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let target = CorrectionTargetTerm(
            text: "Qwen",
            scope: .application(bundleIdentifier: "com.cursor.Cursor"),
            lifecycle: .active,
            source: .automaticLearning
        )
        try environment.correctionTargetRepository.save(target)
        try environment.correctionRuleRepository.save(
            CorrectionRule(
                targetID: target.id,
                original: "q 问",
                replacement: "Qwen",
                scope: target.scope,
                source: .automaticLearning
            )
        )
        let viewModel = VoiceCorrectionViewModel(environment: environment)

        viewModel.undoRecentLearning()

        XCTAssertTrue(try environment.correctionRuleRepository.list().isEmpty)
        XCTAssertTrue(try environment.correctionTargetRepository.list().isEmpty)
    }

    func testUndoRecentLearningKeepsExistingTargetWithOtherAliases() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let target = CorrectionTargetTerm(text: "Qwen", source: .manual)
        try environment.correctionTargetRepository.save(target)
        try environment.correctionRuleRepository.save(
            CorrectionRule(
                targetID: target.id,
                original: "q 问",
                replacement: "Qwen",
                source: .automaticLearning
            )
        )
        try environment.correctionRuleRepository.save(
            CorrectionRule(
                targetID: target.id,
                original: "queue win",
                replacement: "Qwen",
                source: .manual
            )
        )
        let viewModel = VoiceCorrectionViewModel(environment: environment)

        viewModel.undoRecentLearning()

        XCTAssertEqual(try environment.correctionTargetRepository.list().map(\.text), ["Qwen"])
        XCTAssertEqual(try environment.correctionRuleRepository.list().map(\.original), ["queue win"])
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
