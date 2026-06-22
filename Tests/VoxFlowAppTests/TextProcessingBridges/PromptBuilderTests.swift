import XCTest
import VoxFlowContextBoost
@testable import VoxFlowApp

final class PromptBuilderTests: XCTestCase {
    func testConservativePromptStaysShortForFastCorrection() {
        XCTAssertLessThan(PromptBuilder.conservativeSystemPrompt.count, 450)
        XCTAssertTrue(PromptBuilder.conservativeSystemPrompt.contains("只输出正文"))
        XCTAssertTrue(PromptBuilder.conservativeSystemPrompt.contains("不要添加信息"))
    }

    func testBuildIncludesStylePrompt() throws {
        let style = try XCTUnwrap(BuiltInStyleCatalog.profile(id: "builtin.coding"))
        let prompt = PromptBuilder().build(style: style)

        XCTAssertEqual(prompt.styleID, "builtin.coding")
        XCTAssertNil(prompt.model)
        XCTAssertEqual(prompt.temperature, style.temperature)
        XCTAssertNil(prompt.llmProviderID)
        XCTAssertTrue(prompt.systemPrompt.contains(style.prompt))
        XCTAssertTrue(prompt.systemPrompt.contains("所选风格优先"))
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

        let prompt = PromptBuilder().build(style: customStyle)

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
        let result = PromptBuilder().build(style: style)

        XCTAssertFalse(result.systemPrompt.contains("You are"))
        XCTAssertFalse(result.systemPrompt.contains("Selected style"))
        XCTAssertFalse(result.systemPrompt.contains("必须执行以下任务"))
        XCTAssertFalse(result.systemPrompt.contains("强制检查"))
        XCTAssertFalse(result.systemPrompt.contains("输出不得与输入完全相同"))
        XCTAssertTrue(result.systemPrompt.contains("如果原文已经自然、准确、可直接使用，可以保持原文"))
        XCTAssertFalse(result.systemPrompt.contains("小兔子乖乖"))
        XCTAssertTrue(result.systemPrompt.contains("所选风格优先"))
        XCTAssertEqual(result.temperature, 0.6)
    }

    func testConservativePromptPreservesTechnicalTokensWithoutTranslationOrRewrite() {
        let prompt = PromptBuilder.conservativeSystemPrompt

        XCTAssertTrue(prompt.contains("URL"))
        XCTAssertTrue(prompt.contains("命令"))
        XCTAssertTrue(prompt.contains("代码标识符"))
        XCTAssertTrue(prompt.contains("不要翻译"))
        XCTAssertTrue(prompt.contains("不要改写"))
    }

    func testBuildIncludesTemporaryContextHotwordsWithoutOCRRawText() {
        let prompt = PromptBuilder().build(
            style: nil,
            temporaryHotwords: [
                temporaryHotword("Qwen3-ASR"),
                temporaryHotword("Project Apollo"),
            ]
        )

        XCTAssertTrue(prompt.systemPrompt.contains("临时屏幕上下文词"))
        XCTAssertTrue(prompt.systemPrompt.contains("- Qwen3-ASR"))
        XCTAssertTrue(prompt.systemPrompt.contains("- Project Apollo"))
        XCTAssertTrue(prompt.systemPrompt.contains("不要添加上下文里有但用户没有说的信息"))
        XCTAssertFalse(prompt.systemPrompt.contains("完整 OCR 文本"))
    }

    private func temporaryHotword(_ text: String) -> TemporaryHotword {
        TemporaryHotword(
            text: text,
            normalizedText: text.lowercased(),
            score: 5,
            source: .ocrKeyphrase,
            evidence: [HotwordEvidence(reason: "test", weight: 5)],
            expiresAt: Date(timeIntervalSince1970: 1_800_000_120)
        )
    }
}
