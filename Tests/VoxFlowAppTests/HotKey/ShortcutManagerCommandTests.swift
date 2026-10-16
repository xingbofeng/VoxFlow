import XCTest
@testable import VoxFlowApp

final class ShortcutManagerCommandTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var sut: ShortcutManager!

    override func setUp() {
        super.setUp()
        suiteName = "com.voiceinput.tests.command.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        sut = ShortcutManager(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        sut = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultCommandShortcutIsCommandShiftE() {
        XCTAssertEqual(
            sut.shortcutKeyCode(for: .command),
            ShortcutManager.defaultCommandShortcutKeyCode
        )
        XCTAssertEqual(
            ShortcutManager.baseKeyCode(for: ShortcutManager.defaultCommandShortcutKeyCode),
            HotKeyShortcutRouting.eKeyCode
        )
        XCTAssertEqual(
            ShortcutManager.modifierMask(for: ShortcutManager.defaultCommandShortcutKeyCode),
            ShortcutManager.commandModifierMask | ShortcutManager.shiftModifierMask
        )
    }

    func testEKeyCodeIs0x0E() {
        XCTAssertEqual(HotKeyShortcutRouting.eKeyCode, 0x0E)
    }

    func testCommandShortcutCanBeChangedAndCleared() {
        let custom = ShortcutManager.encodeShortcut(
            keyCode: 0x11,
            modifierMask: ShortcutManager.commandModifierMask | ShortcutManager.controlModifierMask
        )

        sut.setShortcutKeyCode(custom, for: .command)

        XCTAssertEqual(sut.shortcutKeyCode(for: .command), custom)

        sut.setShortcutKeyCode(nil, for: .command)

        XCTAssertNil(sut.shortcutKeyCode(for: .command))
    }

    func testCommandShortcutDisabledFlagPersists() {
        sut.setShortcutKeyCode(nil, for: .command)

        let restored = ShortcutManager(defaults: defaults)
        XCTAssertNil(restored.shortcutKeyCode(for: .command))

        restored.setShortcutKeyCode(
            ShortcutManager.defaultCommandShortcutKeyCode,
            for: .command
        )
        XCTAssertEqual(
            restored.shortcutKeyCode(for: .command),
            ShortcutManager.defaultCommandShortcutKeyCode
        )
    }

    func testResetToDefaultsRestoresCommandShortcut() {
        sut.setShortcutKeyCode(nil, for: .command)
        XCTAssertNil(sut.shortcutKeyCode(for: .command))

        sut.resetToDefaults()

        XCTAssertEqual(
            sut.shortcutKeyCode(for: .command),
            ShortcutManager.defaultCommandShortcutKeyCode
        )
    }

    func testCommandDefaultDoesNotConflictWithExistingDictationOptionBinding() {
        sut.dictationShortcutKeyCode = ShortcutManager.defaultCommandShortcutKeyCode

        XCTAssertNil(sut.shortcutKeyCode(for: .command))
        XCTAssertFalse(sut.hasConflict())
    }

    func testCommandRouteIsRoutedByHotKeyRouter() {
        XCTAssertEqual(
            HotKeyRouter.route(
                keyCode: HotKeyShortcutRouting.eKeyCode,
                flags: [.maskCommand, .maskShift],
                dictationKeyCode: 54,
                agentComposeKeyCode: ShortcutManager.defaultAgentComposeShortcutKeyCode,
                commandKeyCode: ShortcutManager.defaultCommandShortcutKeyCode
            ),
            .voiceAction(.command)
        )
    }

    func testCommandDoesNotRouteWhenUnbound() {
        XCTAssertEqual(
            HotKeyRouter.route(
                keyCode: HotKeyShortcutRouting.eKeyCode,
                flags: [.maskCommand, .maskShift],
                dictationKeyCode: 54,
                agentComposeKeyCode: ShortcutManager.defaultAgentComposeShortcutKeyCode,
                commandKeyCode: nil
            ),
            .passThrough
        )
    }
}
