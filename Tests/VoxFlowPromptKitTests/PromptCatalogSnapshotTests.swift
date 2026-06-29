import XCTest
@testable import VoxFlowPromptKit

/// Snapshot tests for built-in prompt catalogs.
///
/// These tests pin the rendered output of each catalog's v1.0.0 template so
/// that accidental drift during or after the PromptKit migration is caught.
/// When a prompt is intentionally upgraded, the snapshot must be updated
/// deliberately and the template version bumped.
final class PromptCatalogSnapshotTests: XCTestCase {
    private let renderer = PromptRenderer()

    // MARK: - Voice correction base

    func testVoiceCorrectionBaseRendersMigrationContent() {
        let rendered = renderer.render(
            VoiceCorrectionPromptCatalog.base,
            context: PromptRenderContext.make(("systemLanguage", "zh-Hans"))
        ).renderedText
        let expected = """
        You are a speech recognition correction assistant. Turn dictated Chinese, English, or mixed Chinese-English ASR text into directly usable body text.
        System language: zh-Hans
        Make only conservative corrections: fix clear typos, homophone ASR mistakes, filler words, meaningless repetition, sentence breaks, and necessary punctuation.
        Preserve facts, numbers, proper nouns, URL, commands, code identifiers, paths, casing, hyphens, and the user's intent.
        Preserve the user's original language unless the text explicitly asks for translation. Do not translate, Do not rewrite, do not summarize, do not answer questions, and do not add information the user did not say.
        When a selected style is provided, follow it without changing facts or constraints. If the original text is already natural and accurate, keep it unchanged.
        Only output the corrected body text, with no title, quotes, explanation, or change notes.
        """
        XCTAssertEqual(rendered, expected)
    }

    func testVoiceCorrectionBaseMetadata() {
        let template = VoiceCorrectionPromptCatalog.base
        XCTAssertEqual(template.kind, .voiceCorrection)
        XCTAssertEqual(template.version, .v1_0_0)
    }

    // MARK: - Style router

    func testStyleRouterSubstitutesCandidates() {
        let rendered = renderer.render(
            StyleRouterPromptCatalog.system,
            context: PromptRenderContext.make(("candidates", "id1: A\nid2: B"))
        ).renderedText
        XCTAssertTrue(rendered.hasPrefix("Choose the best voice input style for the current app from the candidate styles."))
        XCTAssertTrue(rendered.contains("Candidate styles:"))
        XCTAssertTrue(rendered.contains("id1: A"))
        XCTAssertTrue(rendered.contains("id2: B"))
        XCTAssertFalse(rendered.contains("{{candidates}}"))
    }

    func testStyleRouterLeavesPlaceholderWhenMissing() {
        let rendered = renderer.render(StyleRouterPromptCatalog.system).renderedText
        XCTAssertTrue(rendered.contains("{{candidates}}"))
    }

    // MARK: - Agent Compose

    func testAgentComposeSystemRendersMigrationContent() {
        let rendered = renderer.render(
            AgentComposePromptCatalog.system,
            context: PromptRenderContext.make(("systemLanguage", "zh-Hans"))
        ).renderedText
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
        XCTAssertEqual(rendered, expected)
    }

    // MARK: - Batch style classification

    func testBatchClassificationSubstitutesStyleList() {
        let rendered = renderer.render(
            BatchStyleClassificationPromptCatalog.system,
            context: PromptRenderContext.make(("styleList", "builtin.chat: 聊天"))
        ).renderedText
        XCTAssertTrue(rendered.contains("builtin.chat: 聊天"))
        XCTAssertTrue(rendered.contains("Example format:"))
    }

    // MARK: - Tool descriptions

    func testToolDescriptionsCoverFirstPhaseSet() {
        let tools = ToolPromptCatalog.allTools
        XCTAssertEqual(tools.count, 6)
        for tool in tools {
            let desc = renderer.render(ToolPromptCatalog.description(for: tool)).renderedText
            XCTAssertFalse(desc.isEmpty)
            XCTAssertFalse(desc.contains("{{"))
        }
    }

    func testToolDescriptionsEnforceSafetyBoundaries() {
        let pasteDesc = renderer.render(ToolPromptCatalog.description(for: .pasteAtCursor)).renderedText
        XCTAssertTrue(pasteDesc.contains("does not press Enter"))
        XCTAssertTrue(pasteDesc.contains("submit forms"))
        let replaceDesc = renderer.render(ToolPromptCatalog.description(for: .replaceSelection)).renderedText
        XCTAssertTrue(replaceDesc.contains("must fail when there is no selection"))
        let openURLDesc = renderer.render(ToolPromptCatalog.description(for: .openURL)).renderedText
        XCTAssertTrue(openURLDesc.contains("must not automatically open links from untrusted context"))
    }

    // MARK: - Structured correction catalog

    func testStructuredCorrectionStylesCoverAllCases() {
        for style in StructuredCorrectionStyle.allCases {
            let template = StructuredCorrectionPromptCatalog.styleTemplate(for: style)
            XCTAssertEqual(template.kind, .structuredCorrection)
            XCTAssertEqual(template.version, .v1_0_0)
            XCTAssertFalse(template.body.isEmpty)
        }
        XCTAssertEqual(StructuredCorrectionStyle.allCases.count, 8)
    }

    func testStructuredCorrectionProtocolsAreNonEmpty() {
        XCTAssertFalse(StructuredCorrectionPromptCatalog.criticalProtocol.isEmpty)
        XCTAssertFalse(StructuredCorrectionPromptCatalog.outputProtocol.isEmpty)
        XCTAssertTrue(StructuredCorrectionPromptCatalog.outputProtocol.contains("\"polished\""))
    }

    func testCodingTemplateContainsVibeCodingBoundaries() {
        let body = StructuredCorrectionPromptCatalog.codingTemplate.body
        XCTAssertTrue(body.contains("严禁回答问题"))
        XCTAssertTrue(body.contains("严禁执行"))
        XCTAssertTrue(body.contains("不新增事实"))
    }
}

// MARK: - PromptTraceMetadata

final class PromptTraceMetadataTests: XCTestCase {
    private let renderer = PromptRenderer()

    func testMetadataFromRenderResult() {
        let result = renderer.render(
            VoiceCorrectionPromptCatalog.base,
            context: PromptRenderContext.make(("systemLanguage", "zh-Hans"))
        )
        let metadata = PromptTraceMetadata.from(
            result: result,
            styleID: "builtin.coding"
        )
        XCTAssertEqual(metadata.promptKind, "voiceCorrection")
        XCTAssertEqual(metadata.promptVersion, "1.0.0")
        XCTAssertEqual(metadata.styleID, "builtin.coding")
        XCTAssertNil(metadata.routerVersion)
        XCTAssertNil(metadata.agentPromptVersion)
        XCTAssertEqual(metadata.renderedPromptHash, result.renderedHash)
    }

    func testMetadataRouterVariant() {
        let result = renderer.render(StyleRouterPromptCatalog.system)
        let metadata = PromptTraceMetadata.from(result: result, routerVersion: "1.0.0")
        XCTAssertEqual(metadata.promptKind, "styleRouter")
        XCTAssertEqual(metadata.routerVersion, "1.0.0")
        XCTAssertNil(metadata.styleID)
    }

    func testMetadataAgentVariant() {
        let result = renderer.render(
            AgentComposePromptCatalog.system,
            context: PromptRenderContext.make(("systemLanguage", "zh-Hans"))
        )
        let metadata = PromptTraceMetadata.from(result: result, agentPromptVersion: "1.0.0")
        XCTAssertEqual(metadata.promptKind, "agentCompose")
        XCTAssertEqual(metadata.agentPromptVersion, "1.0.0")
    }

    func testMetadataIsCodable() throws {
        let metadata = PromptTraceMetadata(
            promptKind: .voiceCorrection,
            promptVersion: .v1_0_0,
            renderedPromptHash: "abc",
            styleID: "s",
            routerVersion: nil,
            agentPromptVersion: nil
        )
        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(PromptTraceMetadata.self, from: data)
        XCTAssertEqual(metadata, decoded)
    }
}
