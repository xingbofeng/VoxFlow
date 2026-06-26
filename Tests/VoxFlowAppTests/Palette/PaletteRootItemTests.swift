import XCTest
@testable import VoxFlowApp

final class PaletteRootItemTests: XCTestCase {
    func testCommandRootItemsUseStableIDsAndCurrentCommandMetadata() {
        let recentAssets = PaletteRootItem.command(.recentAssets)
        let screenshotOCR = PaletteRootItem.command(.screenshotOCR)

        XCTAssertEqual(recentAssets.id.rawValue, "command:recentAssets")
        XCTAssertEqual(recentAssets.kind, .command)
        XCTAssertEqual(recentAssets.title, "最近资产")
        XCTAssertEqual(recentAssets.subtitle, "打开最近的语音、截图和剪切板")
        XCTAssertEqual(recentAssets.activation, .command(.recentAssets))

        XCTAssertEqual(screenshotOCR.id.rawValue, "command:screenshotOCR")
        XCTAssertEqual(screenshotOCR.title, "截图 OCR")
        XCTAssertTrue(screenshotOCR.aliases.contains("ocr"))
        XCTAssertTrue(screenshotOCR.aliases.contains("截图"))
    }

    func testAllCurrentPaletteCommandsMapToRootItems() {
        let commands: [PaletteCommand] = [
            .recentAssets,
            .assetHistory,
            .screenshotOCR,
            .startAgentCompose,
            .startAgentDispatch,
            .startDictation,
        ]

        let items = commands.map(PaletteRootItem.command)

        XCTAssertEqual(items.map(\.title), ["最近资产", "历史资产", "截图 OCR", "帮我说", "AI 编程", "开始听写"])
        XCTAssertEqual(Set(items.map(\.id)).count, commands.count)
    }

    func testApplicationRootItemsPreferBundleIDForStableIDs() {
        let app = InstalledApplication(
            id: "com.tinyspeck.slackmacgap",
            name: "Slack",
            bundleID: "com.tinyspeck.slackmacgap",
            iconPath: "/Applications/Slack.app/Contents/Resources/app.icns",
            path: "/Applications/Slack.app",
            systemCategory: .userApplication
        )

        let item = PaletteRootItem.application(app)

        XCTAssertEqual(item.id.rawValue, "application:com.tinyspeck.slackmacgap")
        XCTAssertEqual(item.kind, .application)
        XCTAssertEqual(item.title, "Slack")
        XCTAssertEqual(item.subtitle, "应用")
        XCTAssertEqual(item.icon, .applicationIcon(path: "/Applications/Slack.app/Contents/Resources/app.icns"))
        XCTAssertEqual(item.activation, .application(app))
    }

    func testFavoriteRootActionsExposeShiftCommandFShortcut() {
        XCTAssertEqual(PaletteRootAction.open.shortcutBadges, ["↩"])
        XCTAssertEqual(PaletteRootAction.addFavorite.shortcutBadges, ["⇧", "⌘", "F"])
        XCTAssertEqual(PaletteRootAction.removeFavorite.shortcutBadges, ["⇧", "⌘", "F"])
    }

    func testApplicationRootItemsUsePathFallbackWhenBundleIDIsMissing() {
        let app = InstalledApplication(
            id: "path:/applications/local.app",
            name: "Local",
            bundleID: nil,
            iconPath: nil,
            path: "/Applications/Local.app",
            systemCategory: .userApplication
        )

        let item = PaletteRootItem.application(app)

        XCTAssertEqual(item.id.rawValue, "application:path:/applications/local.app")
        XCTAssertEqual(item.icon, .systemImage("app"))
    }

    func testOpenURLRootItemUsesWebsiteIcon() {
        let item = PaletteRootItem.openURL(normalizedURL: "https://miora.design")

        XCTAssertEqual(item.icon, .websiteIcon(pageURL: "https://miora.design"))
    }

    func testTranslateRootItemCarriesText() {
        let item = PaletteRootItem.translate(text: "hello")

        XCTAssertEqual(item.id.rawValue, "translateInput")
        XCTAssertEqual(item.title, "翻译")
        XCTAssertEqual(item.subtitle, "翻译 hello")
        XCTAssertEqual(item.activation, .translate(text: "hello"))
    }
}
