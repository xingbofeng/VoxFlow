import XCTest
@testable import VoxFlowApp

@MainActor
final class LanguageManagerTests: XCTestCase {
    func testDefaultLanguageIsSimplifiedChinese() {
        XCTAssertEqual(RecognitionLanguage.default, .simplifiedChinese)
        XCTAssertEqual(RecognitionLanguage.default.rawValue, "zh-CN")
    }

    func testSelectableLanguagesIncludeMenuSupportedLocales() {
        XCTAssertEqual(
            RecognitionLanguage.allCases.map(\.rawValue),
            ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"]
        )
    }

    func testJapaneseCanBePersistedFromSelection() {
        let defaultsKey = "VoxFlow_SelectedLanguage"
        let defaults = UserDefaults.standard
        let previousStoredValue = defaults.object(forKey: defaultsKey)
        let previousLanguage = LanguageManager.shared.currentLanguage
        defer {
            if let previousStoredValue {
                defaults.set(previousStoredValue, forKey: defaultsKey)
            } else {
                defaults.removeObject(forKey: defaultsKey)
            }
            LanguageManager.shared.setLanguage(previousLanguage)
        }

        LanguageManager.shared.setLanguage(.english)
        LanguageManager.shared.setLanguage(.japanese)

        XCTAssertEqual(LanguageManager.shared.currentLanguage, .japanese)
        XCTAssertEqual(defaults.string(forKey: defaultsKey), "ja-JP")
    }

    func testStoredJapaneseLanguageIsRestored() {
        let suiteName = "test.LanguageManager.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("ja-JP", forKey: "VoxFlow_SelectedLanguage")

        let manager = LanguageManager(defaults: defaults)

        XCTAssertEqual(manager.currentLanguage, .japanese)
        XCTAssertEqual(defaults.string(forKey: "VoxFlow_SelectedLanguage"), "ja-JP")
    }

    func testManualInterfaceLanguageSelectsExplicitLocalizationBundle() {
        let defaultsKey = "VoxFlow_InterfaceLanguage"
        let defaults = UserDefaults.standard
        let previousStoredValue = defaults.object(forKey: defaultsKey)
        defer {
            if let previousStoredValue {
                defaults.set(previousStoredValue, forKey: defaultsKey)
            } else {
                defaults.removeObject(forKey: defaultsKey)
            }
        }

        defaults.set(AppLanguage.ja.rawValue, forKey: defaultsKey)
        XCTAssertEqual(L10n.localize("navigation.route.home"), "ホーム")

        defaults.set(AppLanguage.ko.rawValue, forKey: defaultsKey)
        XCTAssertEqual(L10n.localize("navigation.route.home"), "홈")

        defaults.set(AppLanguage.zhHant.rawValue, forKey: defaultsKey)
        XCTAssertEqual(L10n.localize("navigation.route.home"), "首頁")
    }
}
