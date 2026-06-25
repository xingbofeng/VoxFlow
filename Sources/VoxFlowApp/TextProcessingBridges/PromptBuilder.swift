import Foundation
import VoxFlowContextBoost

enum TextRefinementPurpose: Equatable {
    case dictationCorrection
    case agentCompose
    case directTask
}

struct TextRefinementRequest: Equatable {
    let text: String
    let systemPrompt: String
    let model: String?
    let temperature: Double?

    init(
        text: String,
        systemPrompt: String,
        model: String?,
        temperature: Double?,
        purpose: TextRefinementPurpose = .dictationCorrection
    ) {
        self.text = text
        self.systemPrompt = systemPrompt
        self.model = model
        self.temperature = temperature
        self.purpose = purpose
    }

    let purpose: TextRefinementPurpose
}

struct PromptBuildResult: Equatable {
    let systemPrompt: String
    let llmProviderID: String?
    let styleID: String?
    let model: String?
    let temperature: Double?
}

struct PromptBuilder {
    private static let logger = AppLogger.dictation
    static let conservativeSystemPrompt = """
        你是语音识别纠错助手。把中文、英文或中英混合口述整理成可直接使用的正文。
        只做保守纠错：修正明确的错字、同音误识别、语气填充词、无意义重复、断句和必要标点。
        保留事实、数字、专名、URL、命令、代码标识符、路径、大小写、连字符和用户意图。
        不要翻译、不要改写、不要总结、不要回答问题、不要添加用户没有说过的信息。
        有所选风格时按风格处理，但不得改变事实和约束；原文已自然准确时保持原文。
        只输出处理后的正文，不要标题、引号、解释或修改说明。
        """

    func build(
        style: StyleProfileRecord?,
        temporaryHotwords: [TemporaryHotword] = []
    ) -> PromptBuildResult {
        Self.logger.debug(
            "PromptBuilder build start: styleProvided=\(style != nil), enabled=\(style?.enabled == true), hotwordCount=\(temporaryHotwords.count)"
        )
        var sections = [Self.conservativeSystemPrompt]
        let enabledStyle = style?.enabled == true ? style : nil

        if let enabledStyle {
            sections.append(
                """
                所选风格：
                \(enabledStyle.prompt)
                """
            )
        }

        if let contextSection = ContextBoostPromptSectionBuilder().build(hotwords: temporaryHotwords) {
            sections.append(contextSection)
        }

        let result = PromptBuildResult(
            systemPrompt: sections.joined(separator: "\n\n"),
            llmProviderID: enabledStyle?.llmProviderID,
            styleID: enabledStyle?.id,
            model: enabledStyle?.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? enabledStyle?.model
                : nil,
            temperature: enabledStyle?.temperature
        )
        Self.logger.debug(
            "PromptBuilder build completed: promptLength=\(result.systemPrompt.count), " +
            "styleID=\(result.styleID ?? "-"), model=\(result.model ?? "-"), temperature=\(String(describing: result.temperature))"
        )
        return result
    }
}

protocol PromptAwareTextRefining: TextRefining {
    func refine(_ request: TextRefinementRequest) async throws -> String
}

protocol StructuredLineTranslationSupporting {
    var supportsStructuredLineTranslation: Bool { get }
}

protocol StreamingPromptAwareTextRefining: PromptAwareTextRefining {
    func refineStream(_ request: TextRefinementRequest) -> AsyncThrowingStream<String, Error>
}
