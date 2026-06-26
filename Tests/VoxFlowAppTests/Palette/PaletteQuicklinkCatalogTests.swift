import XCTest
@testable import VoxFlowApp

@MainActor
final class PaletteQuicklinkCatalogTests: XCTestCase {
    func testCatalogContainsBuiltInQuicklinksInSpecifiedOrder() {
        let catalog = PaletteQuicklinkCatalog.all

        XCTAssertEqual(catalog.map(\.id), [
            "google",
            "bing",
            "perplexity",
            "github",
            "stackoverflow",
            "youtube",
            "bilibili",
            "x",
            "xiaohongshu",
            "taobao",
            "jd",
        ])
    }

    func testEveryQuicklinkHasTitleAliasesAndSearchTemplate() {
        for link in PaletteQuicklinkCatalog.all {
            XCTAssertFalse(link.title.isEmpty, "标题不应为空：\(link.id)")
            XCTAssertFalse(link.aliases.isEmpty, "别名不应为空：\(link.id)")
            XCTAssertTrue(link.searchURLTemplate.contains("{query}"), "搜索模板须含 {{query}} 占位：\(link.id)")
            XCTAssertTrue(link.homepageURL.hasPrefix("http"), "主页 URL 须为 http(s)：\(link.id)")
            XCTAssertFalse(link.iconResourceName.isEmpty, "图标资源名不应为空：\(link.id)")
        }
    }

    func testEveryQuicklinkIconResourceIsBundledInQuicklinkIconsDirectory() throws {
        for link in PaletteQuicklinkCatalog.all {
            let url = try XCTUnwrap(
                VoxFlowAppResourceBundle.url(
                    forResource: link.iconResourceName,
                    withExtension: "png",
                    subdirectory: "QuicklinkIcons"
                ),
                "缺少 Quicklink 图标资源：\(link.iconResourceName).png"
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "图标文件不存在：\(url.path)")
        }
    }

    func testQuicklinkIDsAreUnique() {
        let ids = PaletteQuicklinkCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Quicklink id 必须唯一")
    }

    func testKnownAliasesForEachQuicklink() {
        XCTAssertEqual(PaletteQuicklinkCatalog.quicklink(id: "google")?.aliases, ["google", "谷歌", "g", "搜索"])
        XCTAssertEqual(PaletteQuicklinkCatalog.quicklink(id: "taobao")?.aliases, ["taobao", "tb", "淘宝"])
        XCTAssertEqual(PaletteQuicklinkCatalog.quicklink(id: "github")?.aliases, ["github", "gh", "代码", "repo"])
        XCTAssertEqual(PaletteQuicklinkCatalog.quicklink(id: "jd")?.aliases, ["jd", "jingdong", "京东"])
    }

    func testAliasMatchingResolvesEnglishChineseAndShortAliases() {
        XCTAssertEqual(PaletteQuicklinkCatalog.quicklink(matchingAlias: "taobao")?.id, "taobao")
        XCTAssertEqual(PaletteQuicklinkCatalog.quicklink(matchingAlias: "tb")?.id, "taobao")
        XCTAssertEqual(PaletteQuicklinkCatalog.quicklink(matchingAlias: "淘宝")?.id, "taobao")
        XCTAssertEqual(PaletteQuicklinkCatalog.quicklink(matchingAlias: "github")?.id, "github")
        XCTAssertEqual(PaletteQuicklinkCatalog.quicklink(matchingAlias: "gh")?.id, "github")
        XCTAssertEqual(PaletteQuicklinkCatalog.quicklink(matchingAlias: "代码")?.id, "github")
        XCTAssertEqual(PaletteQuicklinkCatalog.quicklink(matchingAlias: "xhs")?.id, "xiaohongshu")
        XCTAssertEqual(PaletteQuicklinkCatalog.quicklink(matchingAlias: "b站")?.id, "bilibili")
    }

    func testAliasMatchingIsCaseInsensitive() {
        XCTAssertEqual(PaletteQuicklinkCatalog.quicklink(matchingAlias: "GitHub")?.id, "github")
        XCTAssertEqual(PaletteQuicklinkCatalog.quicklink(matchingAlias: "TAOBAO")?.id, "taobao")
    }

    func testAliasMatchingReturnsNilForUnknownAlias() {
        XCTAssertNil(PaletteQuicklinkCatalog.quicklink(matchingAlias: "nonexistent"))
        XCTAssertNil(PaletteQuicklinkCatalog.quicklink(matchingAlias: ""))
    }

    func testSearchURLEncodesQueryAndReplacesPlaceholder() {
        let google = PaletteQuicklinkCatalog.quicklink(id: "google")!
        XCTAssertEqual(google.searchURL(for: "macbook stand"), "https://www.google.com/search?q=macbook%20stand")

        let taobao = PaletteQuicklinkCatalog.quicklink(id: "taobao")!
        XCTAssertEqual(taobao.searchURL(for: "macbook stand"), "https://s.taobao.com/search?q=macbook%20stand")
    }

    func testSearchURLEncodesChineseQuery() {
        let bilibili = PaletteQuicklinkCatalog.quicklink(id: "bilibili")!
        let url = bilibili.searchURL(for: "Swift 入门")
        XCTAssertTrue(url.hasPrefix("https://search.bilibili.com/all?keyword="))
        XCTAssertTrue(url.contains("Swift"))
        XCTAssertTrue(url.contains("%E5%85%A5%E9%97%A8"), "中文应被 percent encoded：\(url)")
    }

    func testSearchURLForEmptyQueryReturnsHomepage() {
        let google = PaletteQuicklinkCatalog.quicklink(id: "google")!
        XCTAssertEqual(google.searchURL(for: ""), google.homepageURL)
        XCTAssertEqual(google.searchURL(for: "   "), google.homepageURL)
    }

    func testQuicklinkByIDReturnsNilForUnknown() {
        XCTAssertNil(PaletteQuicklinkCatalog.quicklink(id: "yahoo"))
    }
}
