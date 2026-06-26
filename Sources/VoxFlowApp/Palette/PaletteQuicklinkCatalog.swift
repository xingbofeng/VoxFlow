import Foundation

/// 内置 Quicklink 目录。第一版仅打包内置站点，不支持用户自定义，不联网获取配置。
///
/// 已统一使用本地 PNG logo 资源（`iconResourceName` 存放资源名，不含后缀名）。
enum PaletteQuicklinkCatalog {
    static let all: [PaletteQuicklink] = [
        PaletteQuicklink(
            id: "google",
            title: "Google",
            aliases: ["google", "谷歌", "g", "搜索"],
            iconResourceName: "google",
            searchURLTemplate: "https://www.google.com/search?q={query}",
            homepageURL: "https://www.google.com"
        ),
        PaletteQuicklink(
            id: "bing",
            title: "Bing",
            aliases: ["bing", "必应", "b"],
            iconResourceName: "bing",
            searchURLTemplate: "https://www.bing.com/search?q={query}",
            homepageURL: "https://www.bing.com"
        ),
        PaletteQuicklink(
            id: "perplexity",
            title: "Perplexity",
            aliases: ["perplexity", "pplx", "答案"],
            iconResourceName: "perplexity",
            searchURLTemplate: "https://www.perplexity.ai/search?q={query}",
            homepageURL: "https://www.perplexity.ai"
        ),
        PaletteQuicklink(
            id: "github",
            title: "GitHub",
            aliases: ["github", "gh", "代码", "repo"],
            iconResourceName: "github",
            searchURLTemplate: "https://github.com/search?q={query}",
            homepageURL: "https://github.com"
        ),
        PaletteQuicklink(
            id: "stackoverflow",
            title: "StackOverflow",
            aliases: ["stackoverflow", "stack", "so", "报错"],
            iconResourceName: "stackoverflow",
            searchURLTemplate: "https://stackoverflow.com/search?q={query}",
            homepageURL: "https://stackoverflow.com"
        ),
        PaletteQuicklink(
            id: "youtube",
            title: "YouTube",
            aliases: ["youtube", "yt", "视频"],
            iconResourceName: "youtube",
            searchURLTemplate: "https://www.youtube.com/results?search_query={query}",
            homepageURL: "https://www.youtube.com"
        ),
        PaletteQuicklink(
            id: "bilibili",
            title: "Bilibili",
            aliases: ["bilibili", "bili", "b站", "哔哩哔哩"],
            iconResourceName: "bilibili",
            searchURLTemplate: "https://search.bilibili.com/all?keyword={query}",
            homepageURL: "https://www.bilibili.com"
        ),
        PaletteQuicklink(
            id: "x",
            title: "X",
            aliases: ["x", "twitter", "推特"],
            iconResourceName: "x",
            searchURLTemplate: "https://x.com/search?q={query}",
            homepageURL: "https://x.com"
        ),
        PaletteQuicklink(
            id: "xiaohongshu",
            title: "小红书",
            aliases: ["小红书", "xhs", "rednote"],
            iconResourceName: "xiaohongshu",
            searchURLTemplate: "https://www.xiaohongshu.com/search_result?keyword={query}",
            homepageURL: "https://www.xiaohongshu.com"
        ),
        PaletteQuicklink(
            id: "taobao",
            title: "淘宝",
            aliases: ["taobao", "tb", "淘宝"],
            iconResourceName: "taobao",
            searchURLTemplate: "https://s.taobao.com/search?q={query}",
            homepageURL: "https://www.taobao.com"
        ),
        PaletteQuicklink(
            id: "jd",
            title: "京东",
            aliases: ["jd", "jingdong", "京东"],
            iconResourceName: "jd",
            searchURLTemplate: "https://search.jd.com/Search?keyword={query}",
            homepageURL: "https://www.jd.com"
        ),
    ]

    /// 按 id 查找内置 Quicklink。
    static func quicklink(id: String) -> PaletteQuicklink? {
        all.first { $0.id == id }
    }

    /// 按别名匹配（大小写不敏感、去首尾空白）；未命中返回 nil。
    static func quicklink(matchingAlias alias: String) -> PaletteQuicklink? {
        let normalized = alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return all.first { link in
            link.aliases.contains { $0.lowercased() == normalized }
        }
    }
}
