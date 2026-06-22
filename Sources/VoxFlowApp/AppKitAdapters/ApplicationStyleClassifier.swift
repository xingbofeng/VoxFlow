import Foundation

protocol ApplicationStyleClassifying: AnyObject, Sendable {
    func classify(target: DictationTarget, styles: [StyleProfileRecord]) async throws -> String?
}

final class LLMApplicationStyleClassifier: ApplicationStyleClassifying, @unchecked Sendable {
    private let refiner: any PromptAwareTextRefining
    private let logger = AppLogger.dictation

    init(refiner: any PromptAwareTextRefining) {
        self.refiner = refiner
    }

    func classify(target: DictationTarget, styles: [StyleProfileRecord]) async throws -> String? {
        guard refiner.isEnabled, refiner.isConfigured else {
            logger.debug("LLMApplicationStyleClassifier skip: refiner not ready")
            return nil
        }
        let candidates = styles
            .filter(\.enabled)
            .map { "\($0.id): \($0.name) - \($0.subtitle ?? $0.category)" }
            .joined(separator: "\n")
        logger.debug("LLMApplicationStyleClassifier request candidateCount=\(candidates.count)")
        let response = try await refiner.refine(
            TextRefinementRequest(
                text: "应用名：\(target.appName ?? "未知")\nBundle ID：\(target.bundleID ?? "未知")",
                systemPrompt: """
                根据当前应用，从候选风格中选择最适合语音输入的一项。
                只输出一个候选风格 ID，不要解释；无法判断时输出空字符串。
                候选风格：
                \(candidates)
                """,
                model: nil,
                temperature: nil
            )
        )
        let selectedID = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let isValid = styles.contains { $0.enabled && $0.id == selectedID }
        if isValid {
            logger.debug("LLMApplicationStyleClassifier hit selectedStyle=\(selectedID)")
            return selectedID
        }
        logger.warning("LLMApplicationStyleClassifier invalid selectedStyle=\(selectedID)")
        return nil
    }
}
