import XCTest
@testable import VoxFlowApp
@testable import VoxFlowPromptKit

/// Regression tests confirming the PromptKit migration preserves the exact
/// rendered prompt content previously inlined in the business builders.
///
/// If any of these fail, the migration accidentally changed wording. Update
/// the snapshot only when an intentional prompt change lands (and bump the
/// template version).
final class PromptMigrationRegressionTests: XCTestCase {

    func testPromptBuilderConservativeSystemPromptMatchesMigrationBaseline() {
        let prompt = PromptBuilder(systemLanguage: "zh-Hans").build(style: nil).systemPrompt

        XCTAssertTrue(prompt.contains("You are a speech recognition correction assistant."))
        XCTAssertTrue(prompt.contains("System language: zh-Hans"))
        XCTAssertTrue(prompt.contains("Preserve the user's original language"))
        XCTAssertTrue(prompt.contains("Do not translate"))
        XCTAssertTrue(prompt.contains("Only output the corrected body text"))
    }

    func testPromptBuilderWithoutStyleProducesOnlyBasePrompt() {
        let result = PromptBuilder().build(style: nil, temporaryHotwords: [])
        XCTAssertEqual(result.systemPrompt, PromptBuilder.conservativeSystemPrompt)
        XCTAssertNil(result.styleID)
        XCTAssertNil(result.model)
        XCTAssertNil(result.temperature)
    }

    func testPromptBuilderWithEnabledStyleAppendsStyleSection() {
        let style = StyleProfileRecord(
            id: "test.style",
            name: "Test",
            category: "test",
            subtitle: nil,
            mode: "default",
            prompt: "do test things",
            sampleInput: nil,
            sampleOutput: nil,
            llmProviderID: nil,
            model: nil,
            temperature: 0.3,
            enabled: true,
            builtIn: false,
            isDefault: false,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let result = PromptBuilder().build(style: style, temporaryHotwords: [])
        XCTAssertTrue(result.systemPrompt.hasPrefix(PromptBuilder.conservativeSystemPrompt))
        XCTAssertTrue(result.systemPrompt.contains("Selected style:"))
        XCTAssertTrue(result.systemPrompt.contains("do test things"))
        XCTAssertEqual(result.styleID, "test.style")
        XCTAssertEqual(result.temperature, 0.3)
    }

    func testAgentPromptBuilderSystemPromptMatchesMigrationBaseline() {
        let expected = """
        You are a context-aware writing assistant. The user will dictate their intent and you will generate polished, usable text based on that intent and the provided context.
        System language: zh-Hans

        Rules:
        1. Execute the user's dictation intent faithfully. Do not add content the user did not ask for.
        2. Never fabricate facts, dates, names, or data. If context is insufficient, use conservative and general expressions.
        3. Output ONLY the final usable text — no explanations, no notes, no quotation marks, no markdown fences.
        4. Preserve the user's original language (Chinese/English) unless the dictation intent clearly asks for translation.
        5. When the user dictates code-related content (commands, variables, paths, API names, technical terms), preserve them exactly — do not translate or paraphrase English technical terminology into Chinese.
        6. Match the tone and register implied by the context (formal email, casual chat, technical documentation, etc.).
        """
        XCTAssertEqual(AgentPromptBuilder(systemLanguage: "zh-Hans").build(
            appName: nil,
            stylePrompt: nil,
            context: nil,
            userDictation: "hello"
        ).systemPrompt, expected)
    }

    func testStructuredCorrectionTemplatesMatchCatalogBodies() {
        XCTAssertEqual(
            StructuredCorrectionPromptBuilder.originalTemplate,
            StructuredCorrectionPromptCatalog.originalTemplate.body
        )
        XCTAssertEqual(
            StructuredCorrectionPromptBuilder.formalTemplate,
            StructuredCorrectionPromptCatalog.formalTemplate.body
        )
        XCTAssertEqual(
            StructuredCorrectionPromptBuilder.casualTemplate,
            StructuredCorrectionPromptCatalog.casualTemplate.body
        )
        XCTAssertEqual(
            StructuredCorrectionPromptBuilder.chatTemplate,
            StructuredCorrectionPromptCatalog.chatTemplate.body
        )
        XCTAssertEqual(
            StructuredCorrectionPromptBuilder.energeticTemplate,
            StructuredCorrectionPromptCatalog.energeticTemplate.body
        )
        XCTAssertEqual(
            StructuredCorrectionPromptBuilder.codingTemplate,
            StructuredCorrectionPromptCatalog.codingTemplate.body
        )
        XCTAssertEqual(
            StructuredCorrectionPromptBuilder.emailTemplate,
            StructuredCorrectionPromptCatalog.emailTemplate.body
        )
    }

    func testStructuredCorrectionPromptBuilderAssemblesProtocolAndContext() {
        let context = StructuredCorrectionPromptContext(
            rawText: "hello world",
            userTerms: ["foo"],
            knownCorrections: [],
            ocrTemporaryTerms: [],
            appContext: nil
        )
        let prompt = StructuredCorrectionPromptBuilder().build(style: .coding, context: context)
        XCTAssertTrue(prompt.contains(StructuredCorrectionPromptCatalog.codingTemplate.body))
        XCTAssertTrue(prompt.contains(StructuredCorrectionPromptCatalog.criticalProtocol))
        XCTAssertTrue(prompt.contains(StructuredCorrectionPromptCatalog.outputProtocol))
        XCTAssertTrue(prompt.contains("Current ASR text:"))
        XCTAssertTrue(prompt.contains("hello world"))
        XCTAssertTrue(prompt.contains("Reference data, not output:"))
        XCTAssertTrue(prompt.contains("user_terms: foo"))
    }
}
