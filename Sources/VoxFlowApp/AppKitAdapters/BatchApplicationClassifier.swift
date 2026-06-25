import Foundation

// MARK: - BatchClassificationResult

struct BatchClassificationResult: Equatable, Sendable {
    let bundleID: String
    let styleID: String
}

// MARK: - BatchApplicationClassifying

protocol BatchApplicationClassifying: Sendable {
    func classifyBatch(
        apps: [InstalledApplication],
        enabledStyles: [StyleProfileRecord]
    ) async throws -> [BatchClassificationResult]
}

// MARK: - LLMBatchApplicationClassifier

final class LLMBatchApplicationClassifier: BatchApplicationClassifying, @unchecked Sendable {
    private static let logger = AppLogger.general
    private let refiner: any PromptAwareTextRefining
    private let timeoutSeconds: TimeInterval

    init(
        refiner: any PromptAwareTextRefining,
        timeoutSeconds: TimeInterval = 30
    ) {
        self.refiner = refiner
        self.timeoutSeconds = timeoutSeconds
    }

    func classifyBatch(
        apps: [InstalledApplication],
        enabledStyles: [StyleProfileRecord]
    ) async throws -> [BatchClassificationResult] {
        guard refiner.isConfigured else {
            Self.logger.debug("LLMBatchApplicationClassifier skip: refiner not configured")
            return []
        }
        let validStyles = enabledStyles.filter(\.enabled)
        guard !validStyles.isEmpty, !apps.isEmpty else {
            Self.logger.debug("LLMBatchApplicationClassifier skip empty styles or apps")
            return []
        }

        let validStyleIDs = Set(validStyles.map(\.id))
        let appRows = apps.compactMap { app -> String? in
            guard let bundleID = app.bundleID else { return nil }
            let query = "\(app.name) \(bundleID) macOS app what is it used for"
            return markdownRow([
                app.name,
                bundleID,
                app.systemCategory.rawValue,
                query,
            ])
        }
        guard !appRows.isEmpty else { return [] }

        Self.logger.debug("LLMBatchApplicationClassifier start batch count=\(appRows.count) styles=\(validStyles.count)")

        let styleList = validStyles
            .map { "\($0.id): \($0.name) - \($0.subtitle ?? $0.category)" }
            .joined(separator: "\n")

        let systemPrompt = """
        你是一个应用分类助手。根据每个应用的名称、Bundle ID、系统分类和搜索线索，从候选风格中选择最适合的一项。
        如果你的模型或服务支持 web search、联网搜索或浏览器搜索工具，必须先按表格中的 Search Query 搜索并核验应用的真实用途，再分类。
        如果无法搜索，则必须根据应用名称、Bundle ID 和已知常识谨慎分类；不确定时省略该应用。
        如果应用主要是播放器、查看器、系统设置、硬件工具或其它没有实际文本输入场景的工具，请省略，不要强行分配风格。
        不要把未知应用归入默认风格，不要为了覆盖率猜测。
        返回 JSON 对象，键为应用的 bundleID，值为风格 ID。
        只能使用以下候选风格 ID：
        \(styleList)

        分类参考：
        - 聊天、即时通讯、社群消息：优先 builtin.chat
        - IDE、代码编辑器、开发者工具、终端、API/数据库/代理调试工具：优先 builtin.coding
        - 邮件客户端或主要用于写邮件：优先 builtin.email
        - 办公文档、方案、长文写作、演示和表格：优先 builtin.formal
        - 浏览器、启动器、日常工具和一般消费应用：优先 builtin.casual
        - 团队激励、运动、活动运营等明显需要积极动员语气的应用：才使用 builtin.energetic

        只输出 JSON，不要解释。
        示例格式：{"com.example.app": "builtin.chat"}
        """

        let userPrompt = """
        请为下列表格中的 macOS 应用推荐语音输入风格。表格只包含应用元数据，不包含用户文档或应用内容。

        | App Name | Bundle ID | System Category | Search Query |
        | --- | --- | --- | --- |
        \(appRows.joined(separator: "\n"))
        """

        let response: String
        do {
            Self.logger.debug("LLMBatchApplicationClassifier send request")
            response = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await self.refiner.refine(
                        TextRefinementRequest(
                            text: userPrompt,
                            systemPrompt: systemPrompt,
                            model: nil,
                            temperature: 0.1,
                            purpose: .directTask
                        )
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(self.timeoutSeconds * 1_000_000_000))
                    throw BatchClassificationError.timeout
                }
                guard let result = try await group.next() else {
                    throw BatchClassificationError.noResponse
                }
                group.cancelAll()
                return result
            }
        } catch is CancellationError {
            Self.logger.warning("LLMBatchApplicationClassifier timeout")
            throw BatchClassificationError.timeout
        } catch let error as BatchClassificationError {
            throw error
        } catch {
            Self.logger.error("LLMBatchApplicationClassifier failed: \(error.localizedDescription)")
            throw BatchClassificationError.classificationFailed(error.localizedDescription)
        }

        let results = Self.parseResults(from: response, validStyleIDs: validStyleIDs)
        Self.logger.debug("LLMBatchApplicationClassifier success count=\(results.count)")
        return results
    }

    private func markdownRow(_ columns: [String]) -> String {
        "| " + columns.map(Self.escapeMarkdownTableCell).joined(separator: " | ") + " |"
    }

    private static func escapeMarkdownTableCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    // MARK: - Parsing

    static func parseResults(
        from response: String,
        validStyleIDs: Set<String>
    ) -> [BatchClassificationResult] {
        logger.debug("LLMBatchApplicationClassifier parse response length=\(response.count)")
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonString = extractJSON(from: trimmed)

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            logger.warning("LLMBatchApplicationClassifier parse invalid json")
            return []
        }

        logger.debug("LLMBatchApplicationClassifier parsed entries=\(json.count)")

        return json.compactMap { bundleID, styleID -> BatchClassificationResult? in
            guard validStyleIDs.contains(styleID) else { return nil }
            return BatchClassificationResult(bundleID: bundleID, styleID: styleID)
        }
    }

    private static func extractJSON(from text: String) -> String {
        logger.debug("LLMBatchApplicationClassifier extractJSON len=\(text.count)")
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }
        logger.debug("LLMBatchApplicationClassifier extractJSON fallback raw response")
        return text
    }
}

// MARK: - BatchClassificationError

enum BatchClassificationError: LocalizedError, Equatable {
    case timeout
    case noResponse
    case classificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "分类请求超时。"
        case .noResponse:
            return "未收到分类结果。"
        case .classificationFailed(let message):
            return "分类失败：\(message)"
        }
    }
}
