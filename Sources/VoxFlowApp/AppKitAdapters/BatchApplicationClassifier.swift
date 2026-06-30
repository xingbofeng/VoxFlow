import Foundation
import VoxFlowPromptKit

// MARK: - BatchClassificationResult

struct BatchClassificationResult: Equatable, Sendable {
    let bundleID: String
    let styleID: String
}

// MARK: - BatchApplicationClassifying

protocol BatchApplicationClassifying: Sendable {
    var isConfigured: Bool { get }

    func classifyBatch(
        apps: [InstalledApplication],
        enabledStyles: [StyleProfileRecord]
    ) async throws -> [BatchClassificationResult]
}

extension BatchApplicationClassifying {
    var isConfigured: Bool { true }
}

// MARK: - LLMBatchApplicationClassifier

final class LLMBatchApplicationClassifier: BatchApplicationClassifying, @unchecked Sendable {
    private static let logger = AppLogger.general
    private let refiner: any PromptAwareTextRefining
    private let timeoutSeconds: TimeInterval
    private let renderer = PromptRenderer()

    init(
        refiner: any PromptAwareTextRefining,
        timeoutSeconds: TimeInterval = 30
    ) {
        self.refiner = refiner
        self.timeoutSeconds = timeoutSeconds
    }

    var isConfigured: Bool {
        refiner.isConfigured
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

        let systemPrompt = renderer.render(
            BatchStyleClassificationPromptCatalog.system,
            context: PromptRenderContext(variables: ["styleList": styleList])
        )
        let metadata = PromptTraceMetadata.from(
            result: systemPrompt,
            routerVersion: BatchStyleClassificationPromptCatalog.system.version.stringValue
        )

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
                            systemPrompt: systemPrompt.renderedText,
                            model: nil,
                            temperature: 0.1,
                            purpose: .directTask,
                            promptMetadata: metadata
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
