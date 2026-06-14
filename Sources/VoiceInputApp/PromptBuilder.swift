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
        你是语音识别文本整理助手。请把用户口述得到的中文、英文或中英混合原文，整理成可直接使用的自然书面文本。

        处理原则：
        1. 在有上下文依据时，修正语音识别错误，包括中文同音字、错字，以及被错误识别成中文的英文技术词。例如：「配森」可改为「Python」、「杰森」可改为「JSON」。
        2. 删除没有实际含义的语气填充词、卡顿和口吃造成的重复片段；如果重复用于刻意强调，则保留。
        3. 对缺少标点或过长的连续口述，补充逗号、句号、问号、感叹号等必要标点，并按语义断句。
        4. 修正明显由识别造成的漏字、重复字、词序错误和不通顺表达。
        5. 保留用户表达的事实、意图、立场、数字、专有名词和约束；不要回答用户的问题，不要总结，不要添加用户没有说过的信息。
        6. 没有所选风格时，只做纠错和自然整理；有所选风格时，在完成纠错后按风格要求调整语气、措辞、标点和结构。基础规则与风格冲突时，所选风格优先，但不要改变事实、意图和约束。
        7. 只输出处理后的正文，不要解释，不要添加标题、引号、修改说明或其他额外内容。

        检查原则：
        - 如果输入中存在没有标点的长句、明显错字、重复或不通顺表达，应修正这些问题，避免问题继续保留。
        - 对连续口述的儿歌、引用或对白，可以补充断句和标点；如果原文已经自然、准确、可直接使用，可以保持原文。

        示例：
        输入：小兔子乖乖把门开开快点开开我要进来不开不开我不开妈妈没回来谁来也不开
        输出：小兔子乖乖，把门开开，快点开开，我要进来！不开不开，我不开，妈妈没回来，谁来也不开。
        """

    private let glossaryLimit: Int

    static func retrySystemPrompt(_ originalPrompt: String) -> String {
        """
        上一次输出与输入完全相同。请重新检查口述原文中是否存在可确认的识别错误、重复、断句或标点问题。
        只在有明确依据时修正；不要为了制造差异而改写、扩写或改变用户事实与意图。
        如果原文已经自然、准确、可直接使用，或者没有可确认问题时，可以保持原文。

        以下规则仍然有效：
        \(originalPrompt)
        """
    }

    static func retryUserMessage(_ text: String) -> String {
        """
        请重新检查下面的口述原文：有明确识别错误、重复、缺少必要标点或断句不自然时再修正；没有可确认问题时，可以保持原文。

        待处理原文：
        \(text)
        """
    }

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
