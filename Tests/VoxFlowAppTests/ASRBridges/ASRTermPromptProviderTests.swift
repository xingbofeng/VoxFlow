import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

@MainActor
final class ASRTermPromptProviderTests: XCTestCase {
    func testPromptUsesActiveGlobalAndMatchingApplicationTargetsWithinProviderBudget() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(text: " VoxFlow ", scope: .global)
        )
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(
                text: "tokenhub",
                scope: .application(bundleIdentifier: "com.mitchellh.ghostty")
            )
        )
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(
                text: "CursorOnly",
                scope: .application(bundleIdentifier: "com.cursor.Cursor")
            )
        )
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(text: "Disabled", lifecycle: .suspended)
        )
        let provider = CorrectionTargetASRTermPromptProvider(
            repository: environment.correctionTargetRepository
        )

        let prompt = provider.prompt(
            for: .whisper,
            bundleIdentifier: "com.mitchellh.ghostty"
        )

        XCTAssertEqual(prompt, "tokenhub, VoxFlow")
    }

    func testUnsupportedProviderReceivesNoPrompt() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(text: "tokenhub")
        )
        let provider = CorrectionTargetASRTermPromptProvider(
            repository: environment.correctionTargetRepository
        )

        XCTAssertNil(provider.prompt(for: .qwen3, bundleIdentifier: nil))
    }

    func testDisabledVoiceCorrectionReceivesNoPrompt() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(text: "tokenhub")
        )
        let provider = CorrectionTargetASRTermPromptProvider(
            repository: environment.correctionTargetRepository,
            isEnabled: { false }
        )

        XCTAssertNil(provider.prompt(for: .whisper, bundleIdentifier: nil))
    }

    func testPromptStopsBeforeExceedingProviderCharacterBudget() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(text: "1234567890", updatedAt: Date(timeIntervalSince1970: 3))
        )
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(text: "abcdefghij", updatedAt: Date(timeIntervalSince1970: 2))
        )
        let provider = CorrectionTargetASRTermPromptProvider(
            repository: environment.correctionTargetRepository,
            budgets: [.whisper: 15]
        )

        XCTAssertEqual(provider.prompt(for: .whisper, bundleIdentifier: nil), "1234567890")
    }

    func testDefaultBudgetsMatchProviderCapabilities() {
        XCTAssertEqual(CorrectionTargetASRTermPromptProvider.defaultBudgets[.whisper], 500)
        XCTAssertEqual(CorrectionTargetASRTermPromptProvider.defaultBudgets[.groqWhisper], 600)
    }
}
