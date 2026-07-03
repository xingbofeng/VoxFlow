import XCTest
@testable import VoxFlowApp

final class LLMProviderViewPresentationTests: XCTestCase {
    func testProviderActionIconsUseStandardSymbols() {
        XCTAssertEqual(LLMProviderActionIcon.edit, "square.and.pencil")
        XCTAssertEqual(LLMProviderActionIcon.testConnection, "antenna.radiowaves.left.and.right")
        XCTAssertEqual(LLMProviderActionIcon.delete, "trash")
    }

    func testProviderViewModesSeparateLLMAndAgentSections() {
        XCTAssertEqual(LLMProviderViewMode.llm.visibleSections, [.regularProviders])
        XCTAssertEqual(LLMProviderViewMode.agent.visibleSections, [.localAgentProviders])
        XCTAssertEqual(LLMProviderViewMode.combined.visibleSections, [.regularProviders, .localAgentProviders])
    }

    func testVoxFlowAgentCardUsesBuiltinPresentationInsteadOfExternalCLICopy() {
        let presentation = LocalAgentProviderCardPresentation(descriptor: AgentProviderRegistry.voxflowAgent)

        XCTAssertEqual(presentation.subtitleKey, "model.llm_provider.builtin_agent.subtitle")
        XCTAssertEqual(presentation.detectButtonKey, "model.llm_provider.builtin_agent.detect")
        XCTAssertEqual(presentation.configurationTitleKey, "model.llm_provider.builtin_agent.configuration_title")
        XCTAssertTrue(presentation.showsBuiltinBadge)
        XCTAssertTrue(presentation.usesDefaultLLMProvider)
    }

    func testExternalAgentCardStillUsesModelPickerPresentation() {
        let presentation = LocalAgentProviderCardPresentation(descriptor: AgentProviderRegistry.pi)

        XCTAssertEqual(presentation.subtitleKey, "model.llm_provider.local_agent.subtitle")
        XCTAssertEqual(presentation.detectButtonKey, "model.llm_provider.codex.detect")
        XCTAssertEqual(presentation.configurationTitleKey, "model.llm_provider.codex.model_section")
        XCTAssertFalse(presentation.showsBuiltinBadge)
        XCTAssertFalse(presentation.usesDefaultLLMProvider)
    }
}
