import XCTest
import ChineseInput

final class ChineseKeyboardLayoutTests: XCTestCase {
    override func tearDown() {
        ChineseKeyboardModeStore.active = .chineseQwerty
        super.tearDown()
    }

    func testDefaultKeyboardLayoutIsChineseQwerty() {
        ChineseKeyboardModeStore.active = .chineseQwerty

        let definition = KeyboardLayouts.current()

        XCTAssertEqual(definition.name, "中文拼音")
        XCTAssertEqual(definition.locale, "zh-Hans")
        XCTAssertEqual(definition.currentDeviceLayout?.normal.last?.compactMap(label), ["123", "\u{1F600}", "空格", "换行"])
        XCTAssertEqual(definition.currentDeviceLayout?.normal.last?.compactMap(alternate), ["openChineseNumbers"])
    }

    func testChineseNineGridLayoutUsesHamsterRows() {
        ChineseKeyboardModeStore.active = .chineseNineGrid

        let definition = KeyboardLayouts.current()
        let labels = definition.currentDeviceLayout?.normal.map { row in row.compactMap(label) }

        XCTAssertEqual(definition.name, "中文九键")
        XCTAssertEqual(labels?[0], ["符号", "ABC", "DEF", "delete"])
        XCTAssertEqual(labels?[1], ["GHI", "JKL", "MNO", "换行"])
        XCTAssertEqual(labels?[2], ["PQRS", "TUV", "WXYZ", "\u{1F600}"])
        XCTAssertEqual(labels?[3], ["123", "空格", "中/英", "发送"])
    }

    func testChineseNineGridSpecialKeysUseActionAlternates() {
        ChineseKeyboardModeStore.active = .chineseNineGrid

        let definition = KeyboardLayouts.current()
        let rows = definition.currentDeviceLayout?.normal

        XCTAssertEqual(alternate(for: rows?[0][0]), "openChineseSymbols")
        XCTAssertEqual(alternate(for: rows?[3][0]), "openChineseNumbers")
        XCTAssertEqual(alternate(for: rows?[3][2]), "switchEnglish")
    }

    func testEnglishLayoutKeepsEmojiAndCanSwitchBackToChineseQwerty() {
        ChineseKeyboardModeStore.active = .english

        let definition = KeyboardLayouts.current()

        XCTAssertEqual(definition.name, "English")
        XCTAssertEqual(definition.locale, "en")
        XCTAssertEqual(definition.currentDeviceLayout?.normal.last?.compactMap(label), ["123", "\u{1F600}", "space", "return"])
        XCTAssertEqual(definition.currentDeviceLayout?.normal.last?.compactMap(alternate), [])
    }

    private func label(for key: KeyDefinition) -> String? {
        switch key.type {
        case let .input(value, _):
            return value
        case .backspace:
            return "delete"
        case let .spacebar(name):
            return name
        case let .returnkey(name):
            return name
        case .symbols:
            return "123"
        default:
            return nil
        }
    }

    private func alternate(for key: KeyDefinition?) -> String? {
        guard let key else { return nil }
        switch key.type {
        case let .input(_, alternate):
            return alternate
        default:
            return nil
        }
    }
}
