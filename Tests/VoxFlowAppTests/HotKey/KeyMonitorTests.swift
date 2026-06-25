import CoreGraphics
import XCTest
@testable import VoxFlowApp

final class KeyMonitorTests: XCTestCase {
    func testVoiceShortcutTransitionsProduceOnePressAndOneRelease() {
        var state = VoiceShortcutKeyState()

        XCTAssertEqual(
            state.transition(keyCode: 54, action: .dictation, isModifierPressed: true, threshold: 0.0),
            .pressed
        )
        XCTAssertEqual(
            state.transition(keyCode: 54, action: .dictation, isModifierPressed: false, threshold: 0.0),
            .released
        )
    }

    func testRepeatedVoiceShortcutDownEventDoesNotToggleIntoRelease() {
        var state = VoiceShortcutKeyState()

        XCTAssertEqual(
            state.transition(keyCode: 54, action: .dictation, isModifierPressed: true, threshold: 0.5),
            .pressed
        )
        XCTAssertNil(state.transition(keyCode: 54, action: .dictation, isModifierPressed: true, threshold: 0.5))
        XCTAssertTrue(state.isPressed)
    }

    func testMultiplePressesAreTrackedCorrectly() {
        var state = VoiceShortcutKeyState()

        XCTAssertEqual(
            state.transition(keyCode: 54, action: .dictation, isModifierPressed: true, threshold: 0.0),
            .pressed
        )
        XCTAssertEqual(
            state.transition(keyCode: 54, action: .dictation, isModifierPressed: false, threshold: 0.0),
            .released
        )

        XCTAssertEqual(
            state.transition(keyCode: 54, action: .dictation, isModifierPressed: true, threshold: 0.0),
            .pressed
        )
        XCTAssertTrue(state.isPressed)

        XCTAssertEqual(
            state.transition(keyCode: 54, action: .dictation, isModifierPressed: false, threshold: 10.0),
            .shortPress
        )
        XCTAssertFalse(state.isPressed)
    }

    func testResetAllowsNextEventToPress() {
        var state = VoiceShortcutKeyState()

        XCTAssertEqual(
            state.transition(keyCode: 54, action: .dictation, isModifierPressed: true, threshold: 0.5),
            .pressed
        )
        state.reset()
        XCTAssertEqual(
            state.transition(keyCode: 54, action: .dictation, isModifierPressed: true, threshold: 0.5),
            .pressed
        )
    }

    func testUnrelatedModifierEventDoesNotClearActiveVoiceShortcut() {
        var state = VoiceShortcutKeyState()

        XCTAssertEqual(
            state.transition(keyCode: 54, action: .dictation, isModifierPressed: true, threshold: 0.0),
            .pressed
        )
        XCTAssertNil(
            state.transition(keyCode: 56, action: .agentCompose, isModifierPressed: true, threshold: 0.0)
        )
        XCTAssertTrue(state.isPressed)
        XCTAssertEqual(
            state.transition(keyCode: 54, action: .dictation, isModifierPressed: false, threshold: 0.0),
            .released
        )
    }

    func testHotKeyStateMachineSerializesConcurrentTransitions() {
        let stateMachine = HotKeyStateMachine()
        let queue = DispatchQueue(label: "HotKeyStateMachineTests.concurrent", attributes: .concurrent)
        let group = DispatchGroup()

        for _ in 0..<200 {
            group.enter()
            queue.async {
                _ = stateMachine.transition(
                    keyCode: 54,
                    action: .dictation,
                    isModifierPressed: true,
                    threshold: 0.0
                )
                _ = stateMachine.transition(
                    keyCode: 54,
                    action: .dictation,
                    isModifierPressed: false,
                    threshold: 0.0
                )
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 2), .success)
        XCTAssertFalse(stateMachine.isPressed)
    }

    // MARK: - Short press vs long press

    func testShortPressDetectedWhenDurationBelowThreshold() {
        var state = VoiceShortcutKeyState()

        XCTAssertEqual(
            state.transition(keyCode: 54, action: .dictation, isModifierPressed: true, threshold: 10.0),
            .pressed
        )
        XCTAssertEqual(
            state.transition(keyCode: 54, action: .dictation, isModifierPressed: false, threshold: 10.0),
            .shortPress
        )
    }

    func testLongPressDetectedWhenDurationAboveThreshold() {
        var state = VoiceShortcutKeyState()

        XCTAssertEqual(
            state.transition(keyCode: 54, action: .dictation, isModifierPressed: true, threshold: 0.0),
            .pressed
        )
        XCTAssertEqual(
            state.transition(keyCode: 54, action: .dictation, isModifierPressed: false, threshold: 0.0),
            .released
        )
    }

    func testShortcutEventsPassThroughWhileAppIsActive() {
        XCTAssertTrue(
            ShortcutEventRouting.shouldPassThrough(
                appIsActive: true,
                appIsFrontmost: false,
                isCapturingShortcut: false
            )
        )
        XCTAssertFalse(
            ShortcutEventRouting.shouldPassThrough(
                appIsActive: false,
                appIsFrontmost: false,
                isCapturingShortcut: false
            )
        )
    }

    func testShortcutEventsPassThroughOnlyWhileCapturingShortcut() {
        XCTAssertTrue(
            ShortcutEventRouting.shouldPassThrough(
                appIsActive: false,
                appIsFrontmost: false,
                isCapturingShortcut: true
            )
        )
        XCTAssertTrue(
            ShortcutEventRouting.shouldPassThrough(
                appIsActive: true,
                appIsFrontmost: true,
                isCapturingShortcut: true
            )
        )
    }

    func testShortcutEventsPassThroughWhileVoiceInputIsFrontmost() {
        XCTAssertTrue(
            ShortcutEventRouting.shouldPassThrough(
                appIsActive: false,
                appIsFrontmost: true,
                isCapturingShortcut: false
            )
        )
    }

    func testShortcutEventsAreCapturedWhileAppIsInBackground() {
        XCTAssertFalse(
            ShortcutEventRouting.shouldPassThrough(
                appIsActive: false,
                appIsFrontmost: false,
                isCapturingShortcut: false
            )
        )
    }

    func testWorkflowShortcutEventsPassThroughOnlyWhileCapturingShortcut() {
        XCTAssertFalse(
            WorkflowShortcutEventRouting.shouldPassThrough(isCapturingShortcut: false)
        )
        XCTAssertTrue(
            WorkflowShortcutEventRouting.shouldPassThrough(isCapturingShortcut: true)
        )
    }

    func testConsumedWorkflowShortcutConsumesReleaseEvenWhenReleaseFlagsDoNotMatch() {
        var state = WorkflowShortcutKeyState()

        XCTAssertEqual(
            state.transition(
                keyCode: 0x09,
                routedEvent: .workflowShortcut(.clipboardImageOCR),
                isPressed: true,
                consumed: true
            ),
            .consume
        )
        XCTAssertEqual(
            state.transition(
                keyCode: 0x09,
                routedEvent: .passThrough,
                isPressed: false,
                consumed: false
            ),
            .consume
        )
    }

    func testUnconsumedWorkflowShortcutReleasePassesThrough() {
        var state = WorkflowShortcutKeyState()

        XCTAssertEqual(
            state.transition(
                keyCode: 0x09,
                routedEvent: .workflowShortcut(.clipboardImageOCR),
                isPressed: true,
                consumed: false
            ),
            .passThrough
        )
        XCTAssertEqual(
            state.transition(
                keyCode: 0x09,
                routedEvent: .passThrough,
                isPressed: false,
                consumed: false
            ),
            .passThrough
        )
    }

    func testAgentComposeShortcutRoutesToAgentComposeAction() {
        XCTAssertEqual(
            ShortcutActionRouting.action(
                for: 61,
                dictationKeyCode: 54,
                agentComposeKeyCode: 61
            ),
            .agentCompose
        )
    }

    func testAgentDispatchIsNotRoutedByASeparateModifierKey() {
        XCTAssertNil(
            ShortcutActionRouting.action(
                for: 62,
                dictationKeyCode: 54,
                agentComposeKeyCode: 61,
                agentDispatchKeyCode: nil
            )
        )
    }

    func testRightOptionRoutesThroughHotKeyRouterToAgentCompose() {
        XCTAssertEqual(
            HotKeyRouter.route(
                keyCode: 61,
                flags: [.maskAlternate],
                dictationKeyCode: 54,
                agentComposeKeyCode: ShortcutManager.defaultAgentComposeShortcutKeyCode
            ),
            .voiceAction(.agentCompose)
        )
    }

    func testCombinationShortcutRoutesThroughHotKeyRouterToDictation() {
        let commandShiftY = ShortcutManager.encodeShortcut(
            keyCode: 0x10,
            modifierMask: ShortcutManager.commandModifierMask | ShortcutManager.shiftModifierMask
        )

        XCTAssertEqual(
            HotKeyRouter.route(
                keyCode: 0x10,
                flags: [.maskCommand, .maskShift],
                dictationKeyCode: commandShiftY,
                agentComposeKeyCode: ShortcutManager.defaultAgentComposeShortcutKeyCode
            ),
            .voiceAction(.dictation)
        )
        XCTAssertEqual(
            HotKeyRouter.route(
                keyCode: 0x10,
                flags: [.maskCommand],
                dictationKeyCode: commandShiftY,
                agentComposeKeyCode: ShortcutManager.defaultAgentComposeShortcutKeyCode
            ),
            .passThrough
        )
    }

    func testSelectionActionShortcutRoutesThroughHotKeyRouter() {
        XCTAssertEqual(
            HotKeyRouter.route(
                keyCode: HotKeyShortcutRouting.fKeyCode,
                flags: [.maskCommand, .maskShift],
                dictationKeyCode: 54,
                agentComposeKeyCode: ShortcutManager.defaultAgentComposeShortcutKeyCode,
                selectionActionKeyCode: ShortcutManager.defaultSelectionActionShortcutKeyCode
            ),
            .workflowShortcut(.selectionAction)
        )
    }

    func testDirectSelectionActionShortcutsRouteThroughHotKeyRouter() {
        XCTAssertEqual(
            HotKeyRouter.route(
                keyCode: HotKeyShortcutRouting.jKeyCode,
                flags: [.maskCommand, .maskShift],
                dictationKeyCode: 54,
                agentComposeKeyCode: ShortcutManager.defaultAgentComposeShortcutKeyCode,
                selectionTranslateKeyCode: ShortcutManager.defaultSelectionTranslateShortcutKeyCode
            ),
            .workflowShortcut(.selectionTranslate)
        )
        XCTAssertEqual(
            HotKeyRouter.route(
                keyCode: HotKeyShortcutRouting.kKeyCode,
                flags: [.maskCommand, .maskShift],
                dictationKeyCode: 54,
                agentComposeKeyCode: ShortcutManager.defaultAgentComposeShortcutKeyCode,
                selectionSummarizeKeyCode: ShortcutManager.defaultSelectionSummarizeShortcutKeyCode
            ),
            .workflowShortcut(.selectionSummarize)
        )
        XCTAssertEqual(
            HotKeyRouter.route(
                keyCode: HotKeyShortcutRouting.lKeyCode,
                flags: [.maskCommand, .maskShift],
                dictationKeyCode: 54,
                agentComposeKeyCode: ShortcutManager.defaultAgentComposeShortcutKeyCode,
                selectionAgentKeyCode: ShortcutManager.defaultSelectionAgentShortcutKeyCode
            ),
            .workflowShortcut(.selectionAgent)
        )
    }

    func testModifierShortcutRequiresOnlyThatModifierFlag() {
        XCTAssertTrue(
            ShortcutModifierRouting.isPureModifierShortcut(
                keyCode: 61,
                flags: [.maskAlternate]
            )
        )
        XCTAssertTrue(
            ShortcutModifierRouting.isPureModifierShortcut(
                keyCode: 61,
                flags: []
            )
        )
        XCTAssertFalse(
            ShortcutModifierRouting.isPureModifierShortcut(
                keyCode: 61,
                flags: [.maskAlternate, .maskCommand, .maskShift]
            )
        )
        XCTAssertFalse(
            ShortcutModifierRouting.isPureModifierShortcut(
                keyCode: 59,
                flags: [.maskControl, .maskShift]
            )
        )
    }

    func testConflictingShortcutRoutesToDictationForLegacySafety() {
        XCTAssertEqual(
            ShortcutActionRouting.action(
                for: 54,
                dictationKeyCode: 54,
                agentComposeKeyCode: 54
            ),
            .dictation
        )
    }

    func testUnboundShortcutDoesNotRouteToAnAction() {
        XCTAssertNil(
            ShortcutActionRouting.action(
                for: 61,
                dictationKeyCode: 54,
                agentComposeKeyCode: nil
            )
        )
    }

    func testMiddleMouseRecordingRoutesOnlyWhenEnabledAndButtonIsMiddle() {
        XCTAssertEqual(
            MouseShortcutRouting.action(
                buttonNumber: 2,
                middleMouseRecordingEnabled: true
            ),
            .dictation
        )
        XCTAssertNil(
            MouseShortcutRouting.action(
                buttonNumber: 2,
                middleMouseRecordingEnabled: false
            )
        )
        XCTAssertNil(
            MouseShortcutRouting.action(
                buttonNumber: 1,
                middleMouseRecordingEnabled: true
            )
        )
    }

    func testMiddleMouseButtonStateTogglesOnMouseDownAndIgnoresMouseUp() {
        var state = MouseShortcutButtonState()

        XCTAssertEqual(
            state.transition(buttonNumber: 2, isPressed: true),
            .pressed
        )
        XCTAssertNil(
            state.transition(buttonNumber: 2, isPressed: false),
            "Mouse up belongs to the same click and must not immediately stop recording."
        )
        XCTAssertEqual(
            state.transition(buttonNumber: 2, isPressed: true),
            .released
        )
        XCTAssertNil(
            state.transition(buttonNumber: 2, isPressed: false)
        )
    }
}
