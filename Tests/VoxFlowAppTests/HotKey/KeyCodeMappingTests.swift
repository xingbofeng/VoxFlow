import XCTest
@testable import VoxFlowApp

final class KeyCodeMappingTests: XCTestCase {
    func testModifierKeysExposeMatchingNamesAndIcons() {
        XCTAssertEqual(KeyCodeMapping.displayName(for: 54), "右 Command")
        XCTAssertEqual(KeyCodeMapping.iconName(for: 54), "command")
        XCTAssertEqual(KeyCodeMapping.displayName(for: 61), "右 Option")
        XCTAssertEqual(KeyCodeMapping.iconName(for: 61), "option")
        XCTAssertEqual(KeyCodeMapping.displayName(for: 62), "右 Control")
        XCTAssertEqual(KeyCodeMapping.iconName(for: 62), "control")
    }

    func testUnknownKeyUsesSafeFallback() {
        XCTAssertEqual(KeyCodeMapping.displayName(for: 999), "按键 999")
        XCTAssertEqual(KeyCodeMapping.iconName(for: 999), "keyboard")
    }

    func testCombinationShortcutDisplaysModifierNamesAndBaseKey() {
        let commandShiftY = ShortcutManager.encodeShortcut(
            keyCode: 0x10,
            modifierMask: ShortcutManager.commandModifierMask | ShortcutManager.shiftModifierMask
        )

        XCTAssertEqual(KeyCodeMapping.displayName(for: commandShiftY), "Command + Shift + Y")
        XCTAssertEqual(KeyCodeMapping.iconName(for: commandShiftY), "keyboard")
    }
}
