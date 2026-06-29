import Foundation
import XCTest
import VoxFlowPromptKit
@testable import VoxFlowApp

/// Snapshot tests for StructuredCorrectionPromptBuilder — verifies each
/// of the 7 styles contains the key constraints from prompt-templates.md.
///
/// Covers tasks 7.1-7.14 from redesign-vocabulary-hotwords-learning.
final class StructuredCorrectionPromptBuilderTests: XCTestCase {
    private let builder = StructuredCorrectionPromptBuilder()

    private func makeContext() -> StructuredCorrectionPromptContext {
        StructuredCorrectionPromptContext(
            rawText: "跟陈瑞过一下 PR",
            userTerms: ["陈睿"],
            knownCorrections: [
                .init(original: "陈瑞", corrected: "陈睿")
            ],
            ocrTemporaryTerms: ["Ghostty"],
            appContext: "Ghostty terminal"
        )
    }

    // MARK: - Task 7.11: Unified output schema

    func testAllStylesIncludePolishedCorrectionsKeyTermsSchema() {
        for style in StructuredCorrectionStyle.allCases {
            let prompt = builder.build(style: style, context: makeContext())
            XCTAssertTrue(prompt.contains("polished"), "Style \(style.rawValue) missing 'polished'")
            XCTAssertTrue(prompt.contains("corrections"), "Style \(style.rawValue) missing 'corrections'")
            XCTAssertTrue(prompt.contains("key_terms"), "Style \(style.rawValue) missing 'key_terms'")
            XCTAssertTrue(prompt.contains("homophone"), "Style \(style.rawValue) missing 'homophone' type")
            XCTAssertTrue(prompt.contains("term"), "Style \(style.rawValue) missing 'term' type")
        }
    }

    // MARK: - Task 7.4: Non-interactive principle

    func testAllStylesIncludeNonInteractivePrinciple() {
        for style in StructuredCorrectionStyle.allCases {
            let prompt = builder.build(style: style, context: makeContext())
            XCTAssertTrue(
                prompt.contains("不回答") || prompt.contains("严禁回答") || prompt.contains("不要回答"),
                "Style \(style.rawValue) missing non-interactive 'no answer' principle"
            )
            XCTAssertTrue(
                prompt.contains("不执行") || prompt.contains("严禁执行") || prompt.contains("不要执行"),
                "Style \(style.rawValue) missing non-interactive 'no execute' principle"
            )
        }
    }

    // MARK: - Task 7.2: known_corrections not unconditional

    func testPromptStatesKnownCorrectionsAreNotUnconditional() {
        let prompt = builder.build(style: .default, context: makeContext())
        XCTAssertTrue(prompt.contains("known_corrections"))
        XCTAssertTrue(prompt.contains("not unconditional replacement rules"))
        XCTAssertTrue(prompt.contains("current context"))
    }

    // MARK: - Task 7.3: app_context only affects format

    func testPromptStatesAppContextOnlyAffectsFormat() {
        let prompt = builder.build(style: .default, context: makeContext())
        XCTAssertTrue(prompt.contains("app_context"))
        XCTAssertTrue(prompt.contains("format") || prompt.contains("style"))
    }

    // MARK: - Task 7.12: Context injection

    func testPromptInjectsUserTerms() {
        let prompt = builder.build(style: .default, context: makeContext())
        XCTAssertTrue(prompt.contains("陈睿"))
        XCTAssertTrue(prompt.contains("user_terms"))
    }

    func testPromptInjectsKnownCorrections() {
        let prompt = builder.build(style: .default, context: makeContext())
        XCTAssertTrue(prompt.contains("陈瑞 -> 陈睿"))
    }

    func testPromptInjectsOCRTemporaryTerms() {
        let prompt = builder.build(style: .default, context: makeContext())
        XCTAssertTrue(prompt.contains("Ghostty"))
        XCTAssertTrue(prompt.contains("OCR temporary terms"))
        XCTAssertTrue(prompt.contains("do not learn"))
    }

    func testPromptInjectsAppContext() {
        let prompt = builder.build(style: .default, context: makeContext())
        XCTAssertTrue(prompt.contains("app_context"))
        XCTAssertTrue(prompt.contains("Ghostty terminal"))
    }

    func testPromptInjectsRawText() {
        let prompt = builder.build(style: .default, context: makeContext())
        XCTAssertTrue(prompt.contains("跟陈瑞过一下 PR"))
    }

    func testDefaultTemplateContainsKeyConstraints() {
        let prompt = builder.build(style: .default, context: makeContext())
        XCTAssertTrue(prompt.contains("非交互原则"))
        XCTAssertTrue(prompt.contains("多语言保留"))
        XCTAssertTrue(prompt.contains("智能列表"))
        XCTAssertTrue(prompt.contains("数字转换"))
        XCTAssertTrue(prompt.contains("口头标点"))
    }

    func testEnergeticTemplateContainsKeyConstraints() {
        let prompt = builder.build(style: .energetic, context: makeContext())
        XCTAssertTrue(prompt.contains("Emoji"))
        XCTAssertTrue(prompt.contains("非交互原则"))
        XCTAssertTrue(prompt.contains("智能列表"))
    }

    func testEmailTemplateContainsKeyConstraints() {
        let prompt = builder.build(style: .email, context: makeContext())
        XCTAssertTrue(prompt.contains("非交互原则"))
        XCTAssertTrue(prompt.contains("多语言保留"))
        XCTAssertTrue(prompt.contains("智能列表"))
    }

    func testCodingTemplateContainsKeyConstraints() {
        let prompt = builder.build(style: .coding, context: makeContext())
        XCTAssertTrue(prompt.contains("Vibe Coding"))
        XCTAssertTrue(prompt.contains("camelCase"))
        XCTAssertTrue(prompt.contains("snake_case"))
        XCTAssertTrue(prompt.contains("反引号"))
    }

    func testFormalTemplateContainsKeyConstraints() {
        let prompt = builder.build(style: .formal, context: makeContext())
        XCTAssertTrue(prompt.contains("归纳总结"))
        XCTAssertTrue(prompt.contains("摘要"))
        XCTAssertTrue(prompt.contains("行动项"))
    }

    func testNonFixedTemplatesUseFullPromptStructure() {
        for style in [StructuredCorrectionStyle.original, .casual, .chat] {
            let prompt = builder.build(style: style, context: makeContext())
            XCTAssertTrue(prompt.contains("# Role"), "Style \(style.rawValue) missing Role section")
            XCTAssertTrue(prompt.contains("# Critical Protocol"), "Style \(style.rawValue) missing Critical Protocol")
            XCTAssertTrue(prompt.contains("# Guidelines & Rules"), "Style \(style.rawValue) missing Guidelines")
            XCTAssertTrue(prompt.contains("## 2. 结构与排版"), "Style \(style.rawValue) missing structure rules")
            XCTAssertTrue(prompt.contains("## 3. 命名与格式规范"), "Style \(style.rawValue) missing naming rules")
            XCTAssertTrue(prompt.contains("## 4. 数字转换"), "Style \(style.rawValue) missing number conversion")
            XCTAssertTrue(prompt.contains("## 5. 口头标点处理"), "Style \(style.rawValue) missing verbal punctuation")
            XCTAssertTrue(prompt.contains("# Workflow"), "Style \(style.rawValue) missing workflow")
            XCTAssertTrue(prompt.contains("# Examples"), "Style \(style.rawValue) missing examples")
            XCTAssertTrue(prompt.contains("这个 user profile"), "Style \(style.rawValue) missing non-answer example")
        }
    }

    // MARK: - Task 7.9: Original style minimal cleaning

    func testOriginalStyleEmphasizesMinimalChanges() {
        let prompt = builder.build(style: .original, context: makeContext())
        XCTAssertTrue(prompt.contains("最小") || prompt.contains("尽量保留"))
        XCTAssertTrue(prompt.contains("不润色") || prompt.contains("不改写"))
    }

    // MARK: - Task 75: No answer/execute wording

    func testNoStyleContainsAnswerPhrasing() {
        for style in StructuredCorrectionStyle.allCases {
            let prompt = builder.build(style: style, context: makeContext())
            // The prompt should contain "不回答" (don't answer), not "回答" (answer) as instruction
            // Check that "严禁回答" or "不回答" exists, and not bare "请回答"
            XCTAssertFalse(prompt.contains("请回答"), "Style \(style.rawValue) contains '请回答' — should not instruct model to answer")
        }
    }

    // MARK: - Task 76: Style differences don't change non-interactive principle

    func testAllStylesMaintainCorrectionOnlyPrinciple() {
        for style in StructuredCorrectionStyle.allCases {
            let prompt = builder.build(style: style, context: makeContext())
            // Every style must have the output protocol requiring structured JSON
            XCTAssertTrue(prompt.contains("JSON"), "Style \(style.rawValue) missing JSON output requirement")
        }
    }

    // MARK: - Empty context

    func testPromptWithEmptyContext() {
        let context = StructuredCorrectionPromptContext(
            rawText: "测试文本",
            userTerms: [],
            knownCorrections: [],
            ocrTemporaryTerms: [],
            appContext: nil
        )
        let prompt = builder.build(style: .default, context: context)
        XCTAssertTrue(prompt.contains("测试文本"))
        // The critical protocol mentions user_terms/known_corrections as rules,
        // but the actual context section should not inject empty values.
        // Check that the context section doesn't have the "## user_terms" header
        // when there are no terms to inject.
        let contextSection = prompt.components(separatedBy: "## Text to correct").last ?? ""
        XCTAssertFalse(contextSection.contains("## user_terms"))
        XCTAssertFalse(contextSection.contains("## known_corrections"))
        XCTAssertFalse(contextSection.contains("## OCR temporary terms"))
        XCTAssertFalse(contextSection.contains("## app_context"))
    }
}
