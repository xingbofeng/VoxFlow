import Foundation

/// Palette 内置 Quicklink 模型，描述一个可搜索的站点入口。
///
/// `searchURLTemplate` 使用 `{query}` 占位，执行时进行 percent encoding；
/// query 为空时回退到 `homepageURL`。
struct PaletteQuicklink: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let aliases: [String]
    let iconResourceName: String
    let searchURLTemplate: String
    let homepageURL: String

    /// 根据查询文本生成目标 URL；空查询回退到站点主页。
    func searchURL(for query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return homepageURL }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return searchURLTemplate.replacingOccurrences(of: "{query}", with: encoded)
    }
}
