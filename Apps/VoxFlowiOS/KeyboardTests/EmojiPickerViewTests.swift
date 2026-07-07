import XCTest
@testable import MashangxieKeyboard
@testable import Shared

final class EmojiPickerViewTests: XCTestCase {
    override func tearDown() {
        AppGroup.defaults.removeObject(forKey: SharedKeys.language)
        AppGroup.defaults.synchronize()
        super.tearDown()
    }

    func testEmojiSearchUsesUnicodeNamesForAllConfiguredLanguages() {
        AppGroup.defaults.set("fr", forKey: SharedKeys.language)
        XCTAssertEqual(EmojiSearchModeResolver.activeMode(), .unicodeNames)

        AppGroup.defaults.set("zh", forKey: SharedKeys.language)
        XCTAssertEqual(EmojiSearchModeResolver.activeMode(), .unicodeNames)

        AppGroup.defaults.set("en", forKey: SharedKeys.language)
        XCTAssertEqual(EmojiSearchModeResolver.activeMode(), .unicodeNames)
    }

    func testEmojiSearchDefaultsToUnicodeNamesForChineseFirstKeyboard() {
        AppGroup.defaults.removeObject(forKey: SharedKeys.language)
        XCTAssertEqual(EmojiSearchModeResolver.activeMode(), .unicodeNames)
    }
}
