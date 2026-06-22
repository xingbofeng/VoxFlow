import XCTest
@testable import VoxFlowApp

final class ShortcutManagerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var sut: ShortcutManager!

    override func setUp() {
        super.setUp()
        suiteName = "com.voiceinput.tests.\(UUID().uuidString)"
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

    // MARK: - Key Code

    func testDefaultKeyCodeIsRightCommand() {
        XCTAssertEqual(sut.shortcutKeyCode, 54)
    }

    func testDefaultAgentComposeKeyCodeIsRightOption() {
        XCTAssertEqual(sut.shortcutKeyCode(for: .agentCompose), 61)
    }

    func testDefaultWorkflowShortcutsPreserveExistingOCRBindings() {
        XCTAssertEqual(
            sut.shortcutKeyCode(for: .clipboardImageOCR),
            ShortcutManager.defaultClipboardImageOCRShortcutKeyCode
        )
        XCTAssertEqual(
            sut.shortcutKeyCode(for: .screenshotOCR),
            ShortcutManager.defaultScreenshotOCRShortcutKeyCode
        )
    }

    func testAgentDispatchDoesNotOwnASeparateShortcutKey() {
        XCTAssertNil(sut.shortcutKeyCode(for: .agentDispatch))
    }

    func testSupportedVoiceShortcutKeyCodesIncludeModifierCombinations() {
        XCTAssertTrue(ShortcutManager.isSupportedVoiceShortcutKeyCode(54))
        XCTAssertTrue(ShortcutManager.isSupportedVoiceShortcutKeyCode(61))
        XCTAssertFalse(ShortcutManager.isSupportedVoiceShortcutKeyCode(0x09))

        let commandShiftY = ShortcutManager.encodeShortcut(
            keyCode: 0x10,
            modifierMask: ShortcutManager.commandModifierMask | ShortcutManager.shiftModifierMask
        )
        XCTAssertTrue(ShortcutManager.isSupportedVoiceShortcutKeyCode(commandShiftY))
    }

    func testWorkflowShortcutBindingsCanBeChangedAndCleared() {
        let screenshotOCR = ShortcutManager.encodeShortcut(
            keyCode: 0x0B,
            modifierMask: ShortcutManager.optionModifierMask | ShortcutManager.shiftModifierMask
        )
        let clipboardImageOCR = ShortcutManager.encodeShortcut(
            keyCode: 0x2D,
            modifierMask: ShortcutManager.optionModifierMask | ShortcutManager.shiftModifierMask
        )

        sut.setShortcutKeyCode(clipboardImageOCR, for: .clipboardImageOCR)
        sut.setShortcutKeyCode(screenshotOCR, for: .screenshotOCR)

        XCTAssertEqual(sut.shortcutKeyCode(for: .clipboardImageOCR), clipboardImageOCR)
        XCTAssertEqual(sut.shortcutKeyCode(for: .screenshotOCR), screenshotOCR)

        sut.setShortcutKeyCode(nil, for: .clipboardImageOCR)

        XCTAssertNil(sut.shortcutKeyCode(for: .clipboardImageOCR))
        XCTAssertEqual(sut.shortcutKeyCode(for: .screenshotOCR), screenshotOCR)
    }

    func testOCRWorkflowShortcutsRequireModifiedNonSystemKeys() {
        XCTAssertFalse(ShortcutManager.isSupportedWorkflowShortcutKeyCode(0x09))
        XCTAssertFalse(ShortcutManager.isSupportedWorkflowShortcutKeyCode(54))

        let commandV = ShortcutManager.encodeShortcut(
            keyCode: HotKeyShortcutRouting.vKeyCode,
            modifierMask: ShortcutManager.commandModifierMask
        )
        XCTAssertFalse(ShortcutManager.isSupportedWorkflowShortcutKeyCode(commandV))

        let commandShiftV = ShortcutManager.encodeShortcut(
            keyCode: HotKeyShortcutRouting.vKeyCode,
            modifierMask: ShortcutManager.commandModifierMask | ShortcutManager.shiftModifierMask
        )
        XCTAssertTrue(ShortcutManager.isSupportedWorkflowShortcutKeyCode(commandShiftV))
    }

    func testPureModifierShortcutEncodingPreservesLegacyKeyCode() {
        XCTAssertEqual(
            ShortcutManager.encodeShortcut(keyCode: 54, modifierMask: ShortcutManager.commandModifierMask),
            54
        )
    }

    func testSetAndGetCustomKeyCode() {
        sut.shortcutKeyCode = 63
        XCTAssertEqual(sut.shortcutKeyCode, 63)
    }

    // MARK: - Long Press Threshold

    func testDefaultLongPressThresholdIs500ms() {
        XCTAssertEqual(sut.longPressThreshold, 0.5, accuracy: 0.001)
    }

    func testSetAndGetLongPressThreshold() {
        sut.longPressThreshold = 1.0
        XCTAssertEqual(sut.longPressThreshold, 1.0, accuracy: 0.001)
    }

    // MARK: - Short Press Behavior

    func testDefaultShortPressBehaviorIsToggleListening() {
        XCTAssertEqual(sut.shortPressBehavior, .toggleListening)
    }
}
