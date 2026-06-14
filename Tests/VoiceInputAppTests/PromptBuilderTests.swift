import XCTest
@testable import VoiceInputApp

final class PromptBuilderTests: XCTestCase {
    func testBuildIncludesStylePromptAndEnabledGlossaryTerms() throws {
        let style = try XCTUnwrap(BuiltInStyleCatalog.profile(id: "builtin.coding"))
        let prompt = PromptBuilder().build(
            style: style,
            glossaryTerms: [
                glossaryTerm(term: "Python", aliases: ["配森", "派森"], enabled: true, priority: 1),
                glossaryTerm(term: "Go", aliases: ["够"], enabled: false, priority: 2),
            ]
        )

        XCTAssertEqual(prompt.styleID, "builtin.coding")
        XCTAssertNil(prompt.model)
        XCTAssertEqual(prompt.temperature, style.temperature)
        XCTAssertNil(prompt.llmProviderID)
        XCTAssertTrue(prompt.systemPrompt.contains(style.prompt))
        XCTAssertTrue(prompt.systemPrompt.contains("所选风格优先"))
        XCTAssertTrue(prompt.systemPrompt.contains("Python"))
        XCTAssertTrue(prompt.systemPrompt.contains("配森"))
        XCTAssertFalse(prompt.systemPrompt.contains("Go"))
    }

    func testBuildUsesEnabledStyleModelAndTemperatureOverrides() throws {
        let style = try XCTUnwrap(BuiltInStyleCatalog.profile(id: "builtin.energetic"))
        let customStyle = StyleProfileRecord(
            id: style.id,
            name: style.name,
            category: style.category,
            subtitle: style.subtitle,
            mode: style.mode,
            prompt: style.prompt,
            sampleInput: style.sampleInput,
            sampleOutput: style.sampleOutput,
            llmProviderID: "style-provider",
            model: "style-model",
            temperature: 0.2,
            enabled: true,
            builtIn: style.builtIn,
            isDefault: false,
            createdAt: style.createdAt,
            updatedAt: style.updatedAt
        )

        let prompt = PromptBuilder().build(style: customStyle, glossaryTerms: [])

        XCTAssertEqual(prompt.llmProviderID, "style-provider")
        XCTAssertEqual(prompt.model, "style-model")
        XCTAssertEqual(prompt.temperature, 0.2)
    }

    func testBuiltInPromptsContainCompleteOutputConstraints() throws {
        for style in BuiltInStyleCatalog.profiles(now: Date()) {
            XCTAssertGreaterThan(style.prompt.count, 100, style.id)
            XCTAssertTrue(style.prompt.contains("输出"), style.id)
            XCTAssertTrue(style.prompt.contains("不要"), style.id)
        }
    }

    func testEnergeticStyleLetsAIDecideEmojiUsage() throws {
        let style = try XCTUnwrap(BuiltInStyleCatalog.profile(id: "builtin.energetic"))

        XCTAssertTrue(style.prompt.localizedCaseInsensitiveContains("emoji"))
        XCTAssertTrue(style.prompt.contains("根据语境自行判断"))
        XCTAssertFalse(style.prompt.contains("0-2"))
        XCTAssertTrue(try XCTUnwrap(style.sampleOutput).contains("✨"))
    }

    func testChinesePromptRequiresReadableTransformationAndStylePriority() throws {
        let style = try XCTUnwrap(BuiltInStyleCatalog.profile(id: "builtin.energetic"))
        let result = PromptBuilder().build(style: style, glossaryTerms: [])

        XCTAssertFalse(result.systemPrompt.contains("You are"))
        XCTAssertFalse(result.systemPrompt.contains("Selected style"))
        XCTAssertFalse(result.systemPrompt.contains("必须执行以下任务"))
        XCTAssertFalse(result.systemPrompt.contains("强制检查"))
        XCTAssertFalse(result.systemPrompt.contains("输出不得与输入完全相同"))
        XCTAssertTrue(result.systemPrompt.contains("如果原文已经自然、准确、可直接使用，可以保持原文"))
        XCTAssertTrue(result.systemPrompt.contains("小兔子乖乖，把门开开"))
        XCTAssertTrue(result.systemPrompt.contains("所选风格优先"))
        XCTAssertEqual(result.temperature, 0.6)
    }

    func testRetryPromptDoesNotForceUnnecessaryRewrite() {
        let systemPrompt = PromptBuilder.retrySystemPrompt("原始规则")
        let userMessage = PromptBuilder.retryUserMessage("这是原文。")
        let combined = systemPrompt + "\n" + userMessage

        XCTAssertFalse(combined.contains("必须真正执行文本整理"))
        XCTAssertFalse(combined.contains("不能再次原样返回"))
        XCTAssertFalse(combined.contains("请务必修改"))
        XCTAssertFalse(combined.contains("不要逐字照抄"))
        XCTAssertTrue(combined.contains("不要为了制造差异而改写"))
        XCTAssertTrue(combined.contains("没有可确认问题时，可以保持原文"))
    }

    private func glossaryTerm(
        term: String,
        aliases: [String],
        enabled: Bool,
        priority: Int
    ) -> GlossaryTerm {
        GlossaryTerm(
            id: UUID().uuidString,
            term: term,
            aliases: aliases,
            category: "coding",
            enabled: enabled,
            priority: priority,
            notes: nil,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}
