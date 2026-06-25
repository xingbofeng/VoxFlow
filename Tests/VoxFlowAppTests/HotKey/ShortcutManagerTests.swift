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

    func testDefaultSelectionActionShortcutIsCommandShiftF() {
        XCTAssertEqual(
            sut.shortcutKeyCode(for: .selectionAction),
            ShortcutManager.defaultSelectionActionShortcutKeyCode
        )
        XCTAssertEqual(
            ShortcutManager.baseKeyCode(for: ShortcutManager.defaultSelectionActionShortcutKeyCode),
            HotKeyShortcutRouting.fKeyCode
        )
        XCTAssertEqual(
            ShortcutManager.modifierMask(for: ShortcutManager.defaultSelectionActionShortcutKeyCode),
            ShortcutManager.commandModifierMask | ShortcutManager.shiftModifierMask
        )
    }

    func testDefaultDirectSelectionActionShortcutsUseCommandShiftJKL() {
        XCTAssertEqual(
            sut.shortcutKeyCode(for: .selectionTranslate),
            ShortcutManager.defaultSelectionTranslateShortcutKeyCode
        )
        XCTAssertEqual(
            ShortcutManager.baseKeyCode(for: ShortcutManager.defaultSelectionTranslateShortcutKeyCode),
            HotKeyShortcutRouting.jKeyCode
        )
        XCTAssertEqual(
            sut.shortcutKeyCode(for: .selectionSummarize),
            ShortcutManager.defaultSelectionSummarizeShortcutKeyCode
        )
        XCTAssertEqual(
            ShortcutManager.baseKeyCode(for: ShortcutManager.defaultSelectionSummarizeShortcutKeyCode),
            HotKeyShortcutRouting.kKeyCode
        )
        XCTAssertEqual(
            sut.shortcutKeyCode(for: .selectionAgent),
            ShortcutManager.defaultSelectionAgentShortcutKeyCode
        )
        XCTAssertEqual(
            ShortcutManager.baseKeyCode(for: ShortcutManager.defaultSelectionAgentShortcutKeyCode),
            HotKeyShortcutRouting.lKeyCode
        )

        for shortcut in [
            ShortcutManager.defaultSelectionTranslateShortcutKeyCode,
            ShortcutManager.defaultSelectionSummarizeShortcutKeyCode,
            ShortcutManager.defaultSelectionAgentShortcutKeyCode,
        ] {
            XCTAssertEqual(
                ShortcutManager.modifierMask(for: shortcut),
                ShortcutManager.commandModifierMask | ShortcutManager.shiftModifierMask
            )
        }
    }

    func testDefaultPaletteShortcutIsOptionSpace() {
        XCTAssertEqual(
            sut.shortcutKeyCode(for: .palette),
            ShortcutManager.defaultPaletteShortcutKeyCode
        )
        XCTAssertEqual(
            ShortcutManager.baseKeyCode(for: ShortcutManager.defaultPaletteShortcutKeyCode),
            HotKeyShortcutRouting.spaceKeyCode
        )
        XCTAssertEqual(
            ShortcutManager.modifierMask(for: ShortcutManager.defaultPaletteShortcutKeyCode),
            ShortcutManager.optionModifierMask
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

    func testSelectionActionWorkflowShortcutCanBeChangedAndCleared() {
        let shortcut = ShortcutManager.encodeShortcut(
            keyCode: 0x0F,
            modifierMask: ShortcutManager.commandModifierMask | ShortcutManager.optionModifierMask
        )

        sut.setShortcutKeyCode(shortcut, for: .selectionAction)

        XCTAssertEqual(sut.shortcutKeyCode(for: .selectionAction), shortcut)

        sut.setShortcutKeyCode(nil, for: .selectionAction)

        XCTAssertNil(sut.shortcutKeyCode(for: .selectionAction))
    }

    func testDirectSelectionActionWorkflowShortcutsCanBeChangedAndCleared() {
        let shortcut = ShortcutManager.encodeShortcut(
            keyCode: 0x23,
            modifierMask: ShortcutManager.commandModifierMask | ShortcutManager.optionModifierMask
        )

        sut.setShortcutKeyCode(shortcut, for: .selectionTranslate)

        XCTAssertEqual(sut.shortcutKeyCode(for: .selectionTranslate), shortcut)

        sut.setShortcutKeyCode(nil, for: .selectionTranslate)

        XCTAssertNil(sut.shortcutKeyCode(for: .selectionTranslate))
    }

    func testPaletteWorkflowShortcutCanBeChangedAndCleared() {
        let shortcut = ShortcutManager.encodeShortcut(
            keyCode: 0x0F,
            modifierMask: ShortcutManager.controlModifierMask | ShortcutManager.optionModifierMask
        )

        sut.setShortcutKeyCode(shortcut, for: .palette)

        XCTAssertEqual(sut.shortcutKeyCode(for: .palette), shortcut)

        sut.setShortcutKeyCode(nil, for: .palette)

        XCTAssertNil(sut.shortcutKeyCode(for: .palette))
    }

    func testStartupNormalizesScreenshotOCRAwayFromClipboardOCRDefaultShortcut() {
        let commandShiftV = ShortcutManager.defaultClipboardImageOCRShortcutKeyCode
        defaults.set(true, forKey: "ClipboardImageOCRShortcutDisabled")
        defaults.set(commandShiftV, forKey: "ScreenshotOCRShortcutKeyCode")

        sut = ShortcutManager(defaults: defaults)

        XCTAssertEqual(
            sut.shortcutKeyCode(for: .clipboardImageOCR),
            ShortcutManager.defaultClipboardImageOCRShortcutKeyCode
        )
        XCTAssertEqual(
            sut.shortcutKeyCode(for: .screenshotOCR),
            ShortcutManager.defaultScreenshotOCRShortcutKeyCode
        )
        XCTAssertEqual(
            HotKeyShortcutRouting.workflowShortcut(
                keyCode: HotKeyShortcutRouting.vKeyCode,
                flags: [.maskCommand, .maskShift],
                clipboardImageOCRKeyCode: sut.shortcutKeyCode(for: .clipboardImageOCR),
                screenshotOCRKeyCode: sut.shortcutKeyCode(for: .screenshotOCR)
            ),
            .clipboardImageOCR
        )
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

    func testMiddleMouseRecordingDefaultsOffCanBeEnabledAndResets() {
        XCTAssertFalse(sut.middleMouseRecordingEnabled)

        sut.middleMouseRecordingEnabled = true

        XCTAssertTrue(sut.middleMouseRecordingEnabled)

        sut.resetToDefaults()

        XCTAssertFalse(sut.middleMouseRecordingEnabled)
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
