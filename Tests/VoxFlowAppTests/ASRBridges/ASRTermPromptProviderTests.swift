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
            for: .groqWhisper,
            bundleIdentifier: "com.mitchellh.ghostty"
        )

        XCTAssertEqual(prompt, "tokenhub, VoxFlow")
    }

    func testQwen3ReceivesPromptContext() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(text: "tokenhub")
        )
        let provider = CorrectionTargetASRTermPromptProvider(
            repository: environment.correctionTargetRepository
        )

        XCTAssertEqual(provider.prompt(for: .qwen3, bundleIdentifier: nil), "tokenhub")
    }

    func testAppleSpeechReceivesPromptForContextualStringsBridge() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(text: "VoxFlow")
        )
        let provider = CorrectionTargetASRTermPromptProvider(
            repository: environment.correctionTargetRepository
        )

        XCTAssertEqual(provider.prompt(for: .apple, bundleIdentifier: nil), "VoxFlow")
    }

    func testTencentCloudReceivesWeightedHotwordList() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(text: "VoxFlow")
        )
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(text: "ContextBoost")
        )
        let provider = CorrectionTargetASRTermPromptProvider(
            repository: environment.correctionTargetRepository
        )

        XCTAssertEqual(
            provider.prompt(for: .tencentCloud, bundleIdentifier: nil),
            "ContextBoost|11,VoxFlow|10"
        )
    }

    func testNvidiaNemotronReceivesWordBoostingPhrases() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(text: "VoxFlow")
        )
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(text: "ContextBoost")
        )
        let provider = CorrectionTargetASRTermPromptProvider(
            repository: environment.correctionTargetRepository
        )

        XCTAssertEqual(
            provider.prompt(for: .nvidiaNemotron, bundleIdentifier: nil),
            "ContextBoost, VoxFlow"
        )
    }

    func testUnsupportedProviderReceivesNoPrompt() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(text: "tokenhub")
        )
        let provider = CorrectionTargetASRTermPromptProvider(
            repository: environment.correctionTargetRepository
        )

        XCTAssertNil(provider.prompt(for: .funASR, bundleIdentifier: nil))
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
            CorrectionTargetTerm(text: String(repeating: "a", count: 90), updatedAt: Date(timeIntervalSince1970: 3))
        )
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(text: String(repeating: "b", count: 90), updatedAt: Date(timeIntervalSince1970: 2))
        )
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(text: String(repeating: "c", count: 90), updatedAt: Date(timeIntervalSince1970: 1))
        )
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(text: String(repeating: "d", count: 90), updatedAt: Date(timeIntervalSince1970: 0))
        )
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(text: String(repeating: "e", count: 90), updatedAt: Date(timeIntervalSince1970: -1))
        )
        try environment.correctionTargetRepository.save(
            CorrectionTargetTerm(text: String(repeating: "f", count: 90), updatedAt: Date(timeIntervalSince1970: -2))
        )
        let provider = CorrectionTargetASRTermPromptProvider(
            repository: environment.correctionTargetRepository
        )

        XCTAssertEqual(
            provider.prompt(for: .groqWhisper, bundleIdentifier: nil),
            [
                String(repeating: "a", count: 90),
                String(repeating: "b", count: 90),
                String(repeating: "c", count: 90),
                String(repeating: "d", count: 90),
                String(repeating: "e", count: 90),
                String(repeating: "f", count: 90),
            ].joined(separator: ", ")
        )
    }

    func testProviderCapabilitiesDefinePromptBudgets() {
        XCTAssertEqual(ASRHotwordCapabilityMatrix.capability(for: .whisper).supportMode, .unsupported)
        XCTAssertEqual(ASRHotwordCapabilityMatrix.capability(for: .groqWhisper).maxBudget, 224)
    }
}
