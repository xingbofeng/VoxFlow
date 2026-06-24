import CoreGraphics
import XCTest
@testable import VoxFlowApp

final class PasteLastResultHotKeyTests: XCTestCase {
    func testCommandShiftVMatchesClipboardImageOCRShortcutOnly() {
        XCTAssertEqual(
            HotKeyShortcutRouting.workflowShortcut(
                keyCode: 0x09,
                flags: [.maskCommand, .maskShift]
            ),
            .clipboardImageOCR
        )
        XCTAssertTrue(
            ClipboardImageOCRShortcut.matches(
                keyCode: 0x09,
                flags: [.maskCommand, .maskShift]
            )
        )
    }

    func testCommandShiftAMatchesScreenshotOCRShortcutOnly() {
        XCTAssertEqual(
            HotKeyShortcutRouting.workflowShortcut(
                keyCode: 0x00,
                flags: [.maskCommand, .maskShift]
            ),
            .screenshotOCR
        )
        XCTAssertTrue(
            ScreenshotOCRShortcut.matches(
                keyCode: 0x00,
                flags: [.maskCommand, .maskShift]
            )
        )
    }

    func testOptionSpaceMatchesPaletteShortcutOnly() {
        XCTAssertEqual(
            HotKeyShortcutRouting.workflowShortcut(
                keyCode: HotKeyShortcutRouting.spaceKeyCode,
                flags: [.maskAlternate]
            ),
            .palette
        )
        XCTAssertNil(
            HotKeyShortcutRouting.workflowShortcut(
                keyCode: HotKeyShortcutRouting.spaceKeyCode,
                flags: []
            )
        )
    }

    func testShortcutIgnoresPlainVAndCommandV() {
        XCTAssertNil(HotKeyShortcutRouting.workflowShortcut(keyCode: 0x09, flags: []))
        XCTAssertNil(HotKeyShortcutRouting.workflowShortcut(keyCode: 0x09, flags: [.maskCommand]))
    }

    func testCustomWorkflowShortcutOverridesDefaultCommandShiftV() {
        let customClipboardOCR = ShortcutManager.encodeShortcut(
            keyCode: 0x0B,
            modifierMask: ShortcutManager.optionModifierMask | ShortcutManager.shiftModifierMask
        )

        XCTAssertEqual(
            HotKeyShortcutRouting.workflowShortcut(
                keyCode: 0x0B,
                flags: [.maskAlternate, .maskShift],
                clipboardImageOCRKeyCode: customClipboardOCR,
                screenshotOCRKeyCode: ShortcutManager.defaultScreenshotOCRShortcutKeyCode
            ),
            .clipboardImageOCR
        )
        XCTAssertNil(
            HotKeyShortcutRouting.workflowShortcut(
                keyCode: 0x09,
                flags: [.maskCommand, .maskShift],
                clipboardImageOCRKeyCode: customClipboardOCR,
                screenshotOCRKeyCode: ShortcutManager.defaultScreenshotOCRShortcutKeyCode
            )
        )
    }

    func testClearedWorkflowShortcutDoesNotRouteOCR() {
        XCTAssertNil(
            HotKeyShortcutRouting.workflowShortcut(
                keyCode: 0x09,
                flags: [.maskCommand, .maskShift],
                clipboardImageOCRKeyCode: nil,
                screenshotOCRKeyCode: ShortcutManager.defaultScreenshotOCRShortcutKeyCode
            )
        )
    }

    func testControlShiftVPassesThrough() {
        XCTAssertNil(
            HotKeyShortcutRouting.workflowShortcut(
                keyCode: 0x09,
                flags: [.maskControl, .maskShift]
            )
        )
        XCTAssertFalse(
            ClipboardImageOCRShortcut.matches(
                keyCode: 0x09,
                flags: [.maskControl, .maskShift]
            )
        )
    }

    func testShortcutRoutingRejectsAmbiguousModifierMixes() {
        XCTAssertNil(
            HotKeyShortcutRouting.workflowShortcut(
                keyCode: 0x09,
                flags: [.maskCommand, .maskShift, .maskControl]
            )
        )
        XCTAssertNil(
            HotKeyShortcutRouting.workflowShortcut(
                keyCode: 0x09,
                flags: [.maskShift]
            )
        )
        XCTAssertNil(
            HotKeyShortcutRouting.workflowShortcut(
                keyCode: 0x00,
                flags: [.maskCommand, .maskShift, .maskAlternate]
            )
        )
    }

    func testPlainEscapeRoutesToCancelShortcutOnly() {
        XCTAssertEqual(
            HotKeyShortcutRouting.workflowShortcut(
                keyCode: 53,
                flags: []
            ),
            .cancel
        )
        XCTAssertNil(
            HotKeyShortcutRouting.workflowShortcut(
                keyCode: 53,
                flags: [.maskCommand]
            )
        )
    }

    func testHotKeyRouterSeparatesVoiceActionsFromWorkflowShortcuts() {
        XCTAssertEqual(
            HotKeyRouter.route(
                keyCode: 54,
                flags: [.maskCommand],
                dictationKeyCode: 54,
                agentComposeKeyCode: 61
            ),
            .voiceAction(.dictation)
        )
        XCTAssertEqual(
            HotKeyRouter.route(
                keyCode: 0x09,
                flags: [.maskCommand, .maskShift],
                dictationKeyCode: 54,
                agentComposeKeyCode: 61,
                clipboardImageOCRKeyCode: ShortcutManager.defaultClipboardImageOCRShortcutKeyCode,
                screenshotOCRKeyCode: ShortcutManager.defaultScreenshotOCRShortcutKeyCode
            ),
            .workflowShortcut(.clipboardImageOCR)
        )
        XCTAssertEqual(
            HotKeyRouter.route(
                keyCode: 0x00,
                flags: [.maskCommand, .maskShift],
                dictationKeyCode: 54,
                agentComposeKeyCode: 61,
                clipboardImageOCRKeyCode: ShortcutManager.defaultClipboardImageOCRShortcutKeyCode,
                screenshotOCRKeyCode: ShortcutManager.defaultScreenshotOCRShortcutKeyCode
            ),
            .workflowShortcut(.screenshotOCR)
        )
        XCTAssertEqual(
            HotKeyRouter.route(
                keyCode: HotKeyShortcutRouting.spaceKeyCode,
                flags: [.maskAlternate],
                dictationKeyCode: 54,
                agentComposeKeyCode: 61,
                paletteKeyCode: ShortcutManager.defaultPaletteShortcutKeyCode
            ),
            .workflowShortcut(.palette)
        )
        XCTAssertEqual(
            HotKeyRouter.route(
                keyCode: 0x09,
                flags: [.maskControl, .maskShift],
                dictationKeyCode: 54,
                agentComposeKeyCode: 61
            ),
            .passThrough
        )
        XCTAssertEqual(
            HotKeyRouter.route(
                keyCode: 0x09,
                flags: [.maskCommand],
                dictationKeyCode: 0x09,
                agentComposeKeyCode: 61
            ),
            .passThrough
        )
    }
}
