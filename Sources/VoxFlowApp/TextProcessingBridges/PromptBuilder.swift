import Foundation

struct TextRefinementRequest: Equatable {
    let text: String
    let systemPrompt: String
    let model: String?
    let temperature: Double?
}

struct PromptBuildResult: Equatable {
    let systemPrompt: String
    let llmProviderID: String?
    let styleID: String?
    let model: String?
    let temperature: Double?
}

struct PromptBuilder {
    static let conservativeSystemPrompt = """
        你是语音识别纠错助手。把中文、英文或中英混合口述整理成可直接使用的正文。
        只修明确的错字、同音误识别、语气填充词、无意义重复、断句和必要标点。
        保留事实、数字、专名、URL、命令、代码标识符、路径和用户意图，不要翻译、不要改写、不要添加信息，不要添加用户没有说过的信息、回答问题或总结。
        没有所选风格时只做保守纠错；有所选风格时，所选风格优先，但不得改变事实和约束。
        如果原文已经自然、准确、可直接使用，可以保持原文。
        例：小兔子乖乖，把门开开。
        只输出正文；只输出处理后的正文，不要标题、引号、解释或修改说明。
        """

    private let glossaryLimit: Int

    init(glossaryLimit: Int = 40) {
        self.glossaryLimit = glossaryLimit
    }

    func build(
        style: StyleProfileRecord?,
        glossaryTerms: [GlossaryTerm]
    ) -> PromptBuildResult {
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

        let enabledTerms = glossaryTerms
            .filter(\.enabled)
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.term.localizedCaseInsensitiveCompare(rhs.term) == .orderedAscending
                }
                return lhs.priority < rhs.priority
            }
            .prefix(glossaryLimit)

        if !enabledTerms.isEmpty {
            let lines = enabledTerms.map { term in
                if term.aliases.isEmpty {
                    return "- \(term.term)"
                }
                return "- \(term.term): \(term.aliases.joined(separator: ", "))"
            }
            sections.append(
                """
                用户词库：
                当口述内容明确匹配别名或常见识别错误时，优先使用以下标准写法；上下文不确定时不要强行替换。
                \(lines.joined(separator: "\n"))
                """
            )
        }

        return PromptBuildResult(
            systemPrompt: sections.joined(separator: "\n\n"),
            llmProviderID: enabledStyle?.llmProviderID,
            styleID: enabledStyle?.id,
            model: enabledStyle?.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? enabledStyle?.model
                : nil,
            temperature: enabledStyle?.temperature
        )
    }
}

protocol PromptAwareTextRefining: TextRefining {
    func refine(_ request: TextRefinementRequest) async throws -> String
}

protocol StreamingPromptAwareTextRefining: PromptAwareTextRefining {
    func refineStream(_ request: TextRefinementRequest) -> AsyncThrowingStream<String, Error>
}
