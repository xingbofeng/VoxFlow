import Foundation

enum BuiltInStyleCatalog {
    static let legacyPrompts: [String: Set<String>] = [
        "builtin.original": [
            "不改写用户内容。仅在明显识别错误时做最小修正，不能扩写、总结或改变语气。",
            "你正在处理语音识别得到的原文。保持用户原有措辞、语气、句序和信息密度，只修正能够从上下文明确判断的同音字、技术名词、断句与标点错误。不要润色，不要改写，不要补充用户没有表达的事实，不要删除犹豫词或重复内容。无法确定时保留原样。输出只能包含修正后的正文，不要解释修改过程，不要添加标题、引号或前后说明。",
            """
            ## 原文风格

            **用途**：保留语音识别原始内容，仅修正明确的识别错误。适合记录、备忘和需要保留原话的场景。

            **规则**：
            - 保持用户原有措辞、语气、句序和信息密度
            - 只修正能够从上下文明确判断的同音字、技术名词、断句与标点错误
            - 不润色，不改写，不补充用户没有表达的事实
            - 不删除语气填充词或重复内容
            - 无法确定时保留原样

            **与 LLM 纠错的关系**：LLM 纠错仍会执行，但此风格要求它只做最小必要修正。

            **不会改写的情况**：表达不够优雅但含义明确时，不会主动优化措辞。

            输出只包含修正后的正文，不要添加任何解释、标题、引号或额外内容。
            """,
        ],
        "builtin.formal": [
            "在不添加事实的前提下，把明显口语化但不改变含义的表达调整为正式书面语。",
            "将口述内容整理成清晰、克制、专业的正式书面语，适合汇报、方案和文档。允许修正明显识别错误、补全必要标点、合并无意义的口头停顿，并在不改变含义的前提下调整语序。必须保留全部事实、数字、专有名词和结论。不要添加新观点，不要夸大语气，不要替用户作判断，也不要生成未要求的标题或列表。输出仅包含整理后的正文，不要解释。",
            """
            ## 正式风格

            **用途**：将口述内容整理成正式书面语，适合汇报、方案、文档和商务沟通。

            **规则**：
            - 允许修正明显识别错误、补全必要标点、合并无意义的语气填充词
            - 在不改变含义的前提下调整语序，使表达更清晰克制
            - 必须保留全部事实、数字、专有名词和结论
            - 不添加新观点，不夸大语气，不替用户做判断
            - 不生成未要求的标题或列表

            **与 LLM 纠错的关系**：LLM 纠错会先修正识别错误，此风格再让表达更适合正式场景。

            **不会改写的情况**：事实、数字、结论和主观立场不会被美化或弱化。

            输出只包含修正后的正文，不要添加任何解释、标题、引号或额外内容。
            """,
        ],
        "builtin.casual": [
            "保持轻松自然的口吻，只修正明显识别错误和不顺的标点。",
            "将语音内容整理成自然、友好、像真人聊天的日常表达。保留用户原本的态度和信息，只修正明显的识别错误、断句和不自然的标点；可以去掉完全无意义的口头停顿，但不要把句子改成正式公文。不要擅自增加表情、称呼、承诺或事实，不要过度热情，不要改变用户的立场。输出只包含可直接发送的正文，不要附加解释、标题或引号。",
            """
            ## 日常风格

            **用途**：整理成自然、友好的日常表达，适合聊天、即时消息和团队内部沟通。

            **规则**：
            - 保留用户原本的态度和信息
            - 只修正明显的识别错误、断句和不自然的标点
            - 可以去掉完全无意义的语气填充词，但不把句子改成正式公文
            - 不擅自增加表情、称呼、承诺或事实
            - 不过度热情，不改变用户的立场

            **与 LLM 纠错的关系**：LLM 纠错负责修正识别错误，此风格只让表达更自然。

            **不会改写的情况**：用户原本的情绪、语气和立场不会被替换成更礼貌或更正式的表达。

            输出只包含修正后的正文，不要添加任何解释、标题、引号或额外内容。
            """,
        ],
        "builtin.energetic": [
            "在不添加新信息的前提下，让语气更积极简洁。不要夸张，不要替用户发挥。",
            "在完整保留原意和事实的前提下，让表达更积极、明快、有行动感。修正语音识别错误和标点，适度压缩拖沓口头语，让重点更直接；可以使用少量自然的感叹语气，但不得影响专业性。不要添加用户未说出的计划、承诺、数据或评价，不要使用夸张口号，不要连续使用感叹号，也不要替用户发挥。输出仅为可直接使用的正文，不要解释。",
            """
            ## 元气风格

            **用途**：让表达更积极、明快、有行动感，适合团队激励、进展更新和目标驱动场景。

            **规则**：
            - 在完整保留原意和事实的前提下，让语气更积极明快
            - 修正语音识别错误和标点，适度压缩拖沓口头语
            - 可以使用少量自然的感叹语气，但不得影响专业性
            - 不添加用户未说出的计划、承诺、数据或评价
            - 不使用夸张口号，不连续使用感叹号，不替用户发挥

            **与 LLM 纠错的关系**：LLM 纠错负责修正识别错误，此风格在此基础上让语气更有活力。

            **不会改写的情况**：涉及具体数据、截止日期和负面评价的内容不会被美化。

            输出只包含修正后的正文，不要添加任何解释、标题、引号或额外内容。
            """,
            """
            ## 元气风格

            **用途**：让表达更积极、明快、有行动感，适合团队激励、进展更新和目标驱动场景。

            **规则**：
            - 在完整保留原意和事实的前提下，让语气更积极明快
            - 修正语音识别错误和标点，适度压缩拖沓口头语
            - 可以使用少量自然的感叹语气，但不得影响专业性
            - 是否使用 emoji、使用哪些 emoji 以及使用数量，由 AI 根据语境自行判断；需要时自然使用，不需要时不添加
            - 不添加用户未说出的计划、承诺、数据或评价
            - 不使用夸张口号，不连续使用感叹号或堆叠 emoji，不替用户发挥

            **与 LLM 纠错的关系**：LLM 纠错负责修正识别错误，此风格在此基础上让语气更有活力。

            **不会改写的情况**：涉及具体数据、截止日期和负面评价的内容不会被美化。

            输出只包含修正后的正文，不要添加任何解释、标题、引号或额外内容。
            """,
            """
            ## 元气风格

            **用途**：让表达更积极、明快、有行动感，适合团队激励、进展更新和目标驱动场景。

            **规则**：
            - 在完整保留原意和事实的前提下，让语气更积极明快
            - 修正语音识别错误和标点，适度压缩拖沓口头语
            - 可以使用少量自然的感叹语气，但不得影响专业性
            - 可以使用 0-2 个与语境匹配的自然 emoji（如 ✨、💪、🎉），但不是每次都必须添加
            - 不添加用户未说出的计划、承诺、数据或评价
            - 不使用夸张口号，不连续使用感叹号或堆叠 emoji，不替用户发挥

            **与 LLM 纠错的关系**：LLM 纠错负责修正识别错误，此风格在此基础上让语气更有活力。

            **不会改写的情况**：涉及具体数据、截止日期和负面评价的内容不会被美化。

            输出只包含修正后的正文，不要添加任何解释、标题、引号或额外内容。
            """,
        ],
        "builtin.coding": [
            "优先修正技术术语、大小写、代码相关英文和中英混排识别错误。不要解释代码。",
            "按技术沟通场景处理语音识别文本。优先修正编程语言、框架、命令、API、文件名、变量名和中英混排中的同音误识别，并保留正确的大小写、连字符、路径和代码符号。除非上下文明确，不要猜测具体实现，不要生成代码，不要回答技术问题，不要改变原有需求或结论。保留用户的段落结构。输出只能是修正后的原文，不要解释术语，也不要使用 Markdown 代码围栏。",
            """
            ## 编程风格

            **用途**：针对技术沟通场景优化识别结果，适合代码讨论、技术评审、架构讨论和 bug 描述。

            **规则**：
            - 优先修正编程语言、框架、命令、API、文件名、变量名和中英混排中的同音误识别
            - 保留正确的大小写、连字符、路径和代码符号
            - 保留用户的段落结构
            - 除非上下文明确，不猜测具体实现，不生成代码
            - 不回答技术问题，不改变原有需求或结论
            - 不使用 Markdown 代码围栏，不解释术语

            **与 LLM 纠错的关系**：LLM 纠错负责修正识别错误，此风格进一步保护技术术语和代码语境。

            **不会改写的情况**：不会把问题改成答案，也不会补全用户没有说出的实现方案。

            输出只包含修正后的正文，不要添加任何解释、标题、引号或额外内容。
            """,
        ],
        "builtin.email": [
            "把口述内容整理为清晰、礼貌、简短的邮件或工作消息。不得添加用户没有说的信息。",
            "将口述内容整理成清晰、礼貌、简洁的邮件或工作消息正文。修正识别错误、口头停顿和标点，并按自然顺序组织背景、请求与时间要求。保持用户原有称呼、事实、日期、数字和承诺；未口述称呼或落款时不要自行添加。不要虚构礼貌套话，不要扩大请求范围，不要替用户作决定。输出只包含可直接发送的正文，不要添加主题、解释、引号或 Markdown 标记。",
            """
            ## 邮件风格

            **用途**：将口述内容整理成清晰、礼貌、简洁的邮件或工作消息，适合正式邮件、客户沟通和工作协作。

            **规则**：
            - 修正识别错误、口头停顿和标点
            - 按自然顺序组织背景、请求与时间要求
            - 保持用户原有称呼、事实、日期、数字和承诺
            - 未口述称呼或落款时不自行添加
            - 不虚构礼貌套话，不扩大请求范围，不替用户做决定
            - 不添加主题行、落款或 Markdown 标记

            **与 LLM 纠错的关系**：LLM 纠错负责修正识别错误，此风格在此基础上整理邮件语气。

            **不会改写的情况**：不会替用户添加寒暄、道歉、承诺或结论。

            输出只包含修正后的正文，不要添加任何解释、标题、引号或额外内容。
            """,
        ],
        "builtin.chat": [
            "整理成适合聊天和即时消息的自然表达，保持简短直接。",
            "将语音内容整理成适合聊天和即时消息的自然表达。修正识别错误和标点，去掉口头停顿，保持简短直接、便于快速阅读；语气自然友好，不刻意正式也不过度热情。是否使用 emoji 由 AI 根据语境自行判断，需要时自然使用，不需要时不添加。不添加用户未说出的内容，不夸大语气。输出只包含可直接发送的正文，不要解释。",
            """
            ## 聊天风格

            **用途**：将语音内容整理成适合聊天和即时消息的自然表达，适合微信、飞书、Slack 等通讯工具。

            **规则**：
            - 修正识别错误和标点，去掉口头停顿，保持简短直接
            - 语气自然友好，便于快速阅读和回复
            - 不刻意正式，也不过度热情
            - 是否使用 emoji、使用哪些 emoji 以及使用数量，由 AI 根据语境自行判断；需要时自然使用，不需要时不添加
            - 不添加用户未说出的内容、承诺或评价
            - 不夸大语气，不连续使用感叹号或堆叠 emoji

            **与 LLM 纠错的关系**：LLM 纠错负责修正识别错误，此风格让结果更适合即时消息。

            **不会改写的情况**：不会替用户添加亲昵称呼、表情或额外情绪。

            输出只包含修正后的正文，不要添加任何解释、标题、引号或额外内容。
            """,
        ],
    ]

    static func shouldUpgradeLegacyPrompt(_ prompt: String, profileID: String) -> Bool {
        if legacyPrompts[profileID]?.contains(prompt) == true {
            return true
        }
        guard let heading = legacyHeading(for: profileID) else {
            return false
        }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("## \(heading)")
            && trimmed.contains("**用途**")
            && trimmed.contains("**规则**")
            && trimmed.contains("**与 LLM 纠错的关系**")
            && trimmed.contains("输出只包含")
            && !trimmed.contains("# Critical Protocol")
    }

    private static func legacyHeading(for profileID: String) -> String? {
        switch profileID {
        case "builtin.original": return "原文风格"
        case "builtin.formal": return "正式风格"
        case "builtin.casual": return "日常风格"
        case "builtin.energetic": return "元气风格"
        case "builtin.coding": return "编程风格"
        case "builtin.email": return "邮件风格"
        case "builtin.chat": return "聊天风格"
        default: return nil
        }
    }

    static func profile(id: String, now: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> StyleProfileRecord? {
        profiles(now: now).first { $0.id == id }
    }

    static func profiles(now: Date) -> [StyleProfileRecord] {
        [
            profile(
                id: "builtin.original",
                name: L10n.localize("style.profile.original.name", comment: ""),
                category: L10n.localize("style.profile.original.category", comment: ""),
                subtitle: L10n.localize("style.profile.original.subtitle", comment: ""),
                mode: "raw",
                prompt: StructuredCorrectionPromptBuilder.originalTemplate,
                sampleInput: "今天同步一下项目进展",
                sampleOutput: "今天同步一下项目进展",
                temperature: 0.0,
                isDefault: true,
                now: now
            ),
            profile(
                id: "builtin.formal",
                name: L10n.localize("style.profile.formal.name", comment: ""),
                category: L10n.localize("style.profile.formal.category", comment: ""),
                subtitle: L10n.localize("style.profile.formal.subtitle", comment: ""),
                mode: "formal",
                prompt: StructuredCorrectionPromptBuilder.formalTemplate,
                sampleInput: "这个方案大概能跑",
                sampleOutput: "这个方案基本可行",
                temperature: 0.1,
                isDefault: false,
                now: now
            ),
            profile(
                id: "builtin.casual",
                name: L10n.localize("style.profile.casual.name", comment: ""),
                category: L10n.localize("style.profile.casual.category", comment: ""),
                subtitle: L10n.localize("style.profile.casual.subtitle", comment: ""),
                mode: "casual",
                prompt: StructuredCorrectionPromptBuilder.casualTemplate,
                sampleInput: "等会儿我把链接发你",
                sampleOutput: "等会儿我把链接发你",
                temperature: 0.1,
                isDefault: false,
                now: now
            ),
            profile(
                id: "builtin.chat",
                name: L10n.localize("style.profile.chat.name", comment: ""),
                category: L10n.localize("style.profile.chat.category", comment: ""),
                subtitle: L10n.localize("style.profile.chat.subtitle", comment: ""),
                mode: "chat",
                prompt: StructuredCorrectionPromptBuilder.chatTemplate,
                sampleInput: "等会儿我把链接发你",
                sampleOutput: "等会儿把链接发你 👌",
                temperature: 0.4,
                isDefault: false,
                now: now
            ),
            profile(
                id: "builtin.energetic",
                name: L10n.localize("style.profile.energetic.name", comment: ""),
                category: L10n.localize("style.profile.energetic.category", comment: ""),
                subtitle: L10n.localize("style.profile.energetic.subtitle", comment: ""),
                mode: "energetic",
                prompt: StructuredCorrectionPromptBuilder.energeticTemplate,
                sampleInput: "我们今天继续推进",
                sampleOutput: "今天继续推进，一起加油！✨",
                temperature: 0.6,
                isDefault: false,
                now: now
            ),
            profile(
                id: "builtin.coding",
                name: L10n.localize("style.profile.coding.name", comment: ""),
                category: L10n.localize("style.profile.coding.category", comment: ""),
                subtitle: L10n.localize("style.profile.coding.subtitle", comment: ""),
                mode: "coding",
                prompt: StructuredCorrectionPromptBuilder.codingTemplate,
                sampleInput: "配森",
                sampleOutput: "Python",
                temperature: 0.0,
                isDefault: false,
                now: now
            ),
            profile(
                id: "builtin.email",
                name: L10n.localize("style.profile.email.name", comment: ""),
                category: L10n.localize("style.profile.email.category", comment: ""),
                subtitle: L10n.localize("style.profile.email.subtitle", comment: ""),
                mode: "email",
                prompt: StructuredCorrectionPromptBuilder.emailTemplate,
                sampleInput: "麻烦你明天之前给我反馈",
                sampleOutput: "麻烦你明天之前给我反馈。",
                temperature: 0.1,
                isDefault: false,
                now: now
            ),
        ]
    }

    private static func profile(
        id: String,
        name: String,
        category: String,
        subtitle: String,
        mode: String,
        prompt: String,
        sampleInput: String,
        sampleOutput: String,
        temperature: Double,
        isDefault: Bool,
        now: Date
    ) -> StyleProfileRecord {
        StyleProfileRecord(
            id: id,
            name: name,
            category: category,
            subtitle: subtitle,
            mode: mode,
            prompt: prompt,
            sampleInput: sampleInput,
            sampleOutput: sampleOutput,
            llmProviderID: nil,
            model: nil,
            temperature: temperature,
            enabled: true,
            builtIn: true,
            isDefault: isDefault,
            createdAt: now,
            updatedAt: now
        )
    }
}

enum BuiltInStyleSeeder {
    static func seed(styleRepository: any StyleRepository, clock: any AppClock) throws {
        let now = clock.now
        let currentDefault = try styleRepository.defaultProfile()

        for profile in BuiltInStyleCatalog.profiles(now: now) {
            guard let existing = try styleRepository.profile(id: profile.id) else {
                var seeded = profile
                if currentDefault != nil && profile.isDefault {
                    seeded = profile.withDefault(false)
                }
                try styleRepository.save(seeded)
                continue
            }

            if existing.builtIn,
               BuiltInStyleCatalog.shouldUpgradeLegacyPrompt(existing.prompt, profileID: profile.id) {
                try styleRepository.save(profile.upgradingLegacyPrompt(from: existing, updatedAt: now))
            }
        }
    }
}

private extension StyleProfileRecord {
    func withDefault(_ value: Bool) -> StyleProfileRecord {
        StyleProfileRecord(
            id: id,
            name: name,
            category: category,
            subtitle: subtitle,
            mode: mode,
            prompt: prompt,
            sampleInput: sampleInput,
            sampleOutput: sampleOutput,
            llmProviderID: llmProviderID,
            model: model,
            temperature: temperature,
            enabled: enabled,
            builtIn: builtIn,
            isDefault: value,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func upgradingLegacyPrompt(from existing: StyleProfileRecord, updatedAt: Date) -> StyleProfileRecord {
        StyleProfileRecord(
            id: id,
            name: name,
            category: category,
            subtitle: subtitle,
            mode: mode,
            prompt: prompt,
            sampleInput: sampleInput,
            sampleOutput: sampleOutput,
            llmProviderID: existing.llmProviderID,
            model: existing.model,
            temperature: temperature,
            enabled: existing.enabled,
            builtIn: builtIn,
            isDefault: existing.isDefault,
            createdAt: existing.createdAt,
            updatedAt: updatedAt
        )
    }
}
