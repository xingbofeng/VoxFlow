import Foundation

public struct ContextBoostPromptSectionBuilder: Sendable {
    public init() {}

    public func build(hotwords: [TemporaryHotword]) -> String? {
        let lines = hotwords
            .map { sanitize($0.text) }
            .filter { !$0.isEmpty }
            .map { "- \($0)" }
        guard !lines.isEmpty else { return nil }

        return """
        临时屏幕上下文词，仅本次有效，不代表用户长期偏好：
        \(lines.joined(separator: "\n"))

        这些词只用于判断专有名词、上下文关键词和可能被听错的短语。
        不要添加上下文里有但用户没有说的信息。
        不要润色、不要扩写、不要总结。
        不确定时保留 ASR 原文。
        """
    }

    private func sanitize(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
