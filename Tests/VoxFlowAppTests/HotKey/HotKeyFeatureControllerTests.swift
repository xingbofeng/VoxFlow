import XCTest
@testable import VoxFlowApp

@MainActor
final class HotKeyFeatureControllerTests: XCTestCase {
    func testStartInstallsMonitorHandlersAndStartsMonitor() {
        let recorder = HotKeyFeatureRecorder()
        let controller = recorder.makeController()

        controller.start()

        XCTAssertEqual(recorder.monitorStartCount, 1)
        XCTAssertNotNil(recorder.pressHandler)
        XCTAssertNotNil(recorder.releaseHandler)
        XCTAssertNotNil(recorder.shortPressHandler)
        XCTAssertNotNil(recorder.workflowShortcutHandler)
    }

    func testHoldModeShortPressDoesNotStart() {
        let recorder = HotKeyFeatureRecorder()
        recorder.dictationState = .idle
        recorder.shortPressBehavior = .none
        recorder.longPressThreshold = 0.42
        let controller = recorder.makeController()
        controller.start()

        recorder.pressHandler?(.dictation)
        recorder.shortPressHandler?(.dictation)

        XCTAssertEqual(recorder.scheduledActions, [.dictation])
        XCTAssertEqual(recorder.scheduledThresholds, [0.42])
        XCTAssertEqual(recorder.cancelCount, 1)
        XCTAssertTrue(recorder.decisions.isEmpty)
    }

    func testHoldModeStartsOnlyAfterThreshold() {
        let recorder = HotKeyFeatureRecorder()
        recorder.dictationState = .idle
        recorder.shortPressBehavior = .none
        recorder.longPressThreshold = 0.42
        let controller = recorder.makeController()
        controller.start()

        recorder.pressHandler?(.dictation)
        recorder.fireScheduledPress()
        recorder.fireScheduledPress()

        XCTAssertEqual(recorder.scheduledActions, [.dictation])
        XCTAssertEqual(recorder.scheduledThresholds, [0.42])
        XCTAssertEqual(recorder.decisions, [.startDictation(.dictation)])
    }

    func testHoldModeReleaseStopsStartedRecording() {
        let recorder = HotKeyFeatureRecorder()
        recorder.dictationState = .idle
        recorder.shortPressBehavior = .none
        let controller = recorder.makeController()
        controller.start()

        recorder.pressHandler?(.dictation)
        recorder.fireScheduledPress()
        recorder.dictationState = .recording
        recorder.activeVoiceAction = .dictation
        recorder.releaseHandler?(.dictation)

        XCTAssertEqual(
            recorder.decisions,
            [.startDictation(.dictation), .releaseDictation(.dictation)]
        )
    }

    func testPressStartsImmediatelyWhenShortPressToggleIsEnabled() {
        let recorder = HotKeyFeatureRecorder()
        recorder.dictationState = .idle
        recorder.shortPressBehavior = .toggleListening
        recorder.longPressThreshold = 0.42
        let controller = recorder.makeController()
        controller.start()

        recorder.pressHandler?(.dictation)

        XCTAssertTrue(recorder.scheduledActions.isEmpty)
        XCTAssertTrue(recorder.scheduledThresholds.isEmpty)
        XCTAssertEqual(recorder.decisions, [.startDictation(.dictation)])
    }

    func testDictationShortcutStartsAgentDispatchWhenCommandCenterIsEnabled() {
        let recorder = HotKeyFeatureRecorder()
        recorder.dictationState = .idle
        recorder.shortPressBehavior = .toggleListening
        recorder.primaryVoiceAction = .agentDispatch
        let controller = recorder.makeController()
        controller.start()

        recorder.pressHandler?(.dictation)

        XCTAssertEqual(recorder.decisions, [.startDictation(.agentDispatch)])
    }

    func testCommandCenterDoesNotStealNotesCaptureShortcut() {
        let recorder = HotKeyFeatureRecorder()
        recorder.dictationState = .idle
        recorder.shortPressBehavior = .toggleListening
        recorder.primaryVoiceAction = .agentDispatch
        recorder.notesState = HotKeyNotesState(
            shouldCaptureHotKey: true,
            isActive: true,
            isRecording: false
        )
        let controller = recorder.makeController()
        controller.start()

        recorder.pressHandler?(.dictation)

        XCTAssertEqual(recorder.decisions, [.startNotesRecording])
    }

    func testAgentComposePressStartsImmediatelyWhenShortPressToggleIsEnabled() {
        let recorder = HotKeyFeatureRecorder()
        recorder.dictationState = .idle
        recorder.shortPressBehavior = .toggleListening
        recorder.longPressThreshold = 0.42
        let controller = recorder.makeController()
        controller.start()

        recorder.pressHandler?(.agentCompose)

        XCTAssertTrue(recorder.scheduledActions.isEmpty)
        XCTAssertTrue(recorder.scheduledThresholds.isEmpty)
        XCTAssertEqual(recorder.decisions, [.startDictation(.agentCompose)])
    }

    func testShortPressAfterImmediateToggleStartKeepsRecording() {
        let recorder = HotKeyFeatureRecorder()
        recorder.dictationState = .idle
        recorder.shortPressBehavior = .toggleListening
        let controller = recorder.makeController()
        controller.start()

        recorder.pressHandler?(.dictation)
        recorder.shortPressHandler?(.dictation)

        XCTAssertEqual(recorder.cancelCount, 1)
        XCTAssertEqual(recorder.decisions, [.startDictation(.dictation)])
    }

    func testSecondShortPressWhileRecordingReleasesWhenToggleIsEnabled() {
        let recorder = HotKeyFeatureRecorder()
        recorder.dictationState = .recording
        recorder.activeVoiceAction = .dictation
        recorder.shortPressBehavior = .toggleListening
        let controller = recorder.makeController()
        controller.start()

        recorder.pressHandler?(.dictation)
        recorder.shortPressHandler?(.dictation)

        XCTAssertEqual(recorder.cancelCount, 1)
        XCTAssertEqual(recorder.decisions, [.releaseDictation(.dictation)])
    }

    func testShortPressIsIgnoredWhenToggleIsDisabled() {
        let recorder = HotKeyFeatureRecorder()
        recorder.dictationState = .idle
        recorder.shortPressBehavior = .none
        let controller = recorder.makeController()
        controller.start()

        recorder.shortPressHandler?(.dictation)

        XCTAssertEqual(recorder.cancelCount, 1)
        XCTAssertTrue(recorder.decisions.isEmpty)
    }

    func testPressIsIgnoredWhileDictationIsBusy() {
        let recorder = HotKeyFeatureRecorder()
        recorder.dictationState = .processing
        let controller = recorder.makeController()
        controller.start()

        recorder.pressHandler?(.dictation)

        XCTAssertTrue(recorder.scheduledActions.isEmpty)
        XCTAssertTrue(recorder.decisions.isEmpty)
    }

    func testAgentComposePressIsIgnoredWhileNotesRecording() {
        let recorder = HotKeyFeatureRecorder()
        recorder.dictationState = .idle
        recorder.shortPressBehavior = .toggleListening
        recorder.notesState = HotKeyNotesState(
            shouldCaptureHotKey: false,
            isActive: true,
            isRecording: true
        )
        let controller = recorder.makeController()
        controller.start()

        recorder.pressHandler?(.agentCompose)

        XCTAssertTrue(recorder.scheduledActions.isEmpty)
        XCTAssertTrue(recorder.decisions.isEmpty)
    }

    func testReleaseCancelsDelayedPressAndPerformsReleaseDecision() {
        let recorder = HotKeyFeatureRecorder()
        recorder.dictationState = .recording
        recorder.activeVoiceAction = .dictation
        let controller = recorder.makeController()
        controller.start()

        recorder.releaseHandler?(.dictation)

        XCTAssertEqual(recorder.cancelCount, 1)
        XCTAssertEqual(recorder.decisions, [.releaseDictation(.dictation)])
    }

    func testShortPressCancelsDelayedPressAndPerformsShortPressDecision() {
        let recorder = HotKeyFeatureRecorder()
        recorder.dictationState = .idle
        recorder.notesState = HotKeyNotesState(
            shouldCaptureHotKey: true,
            isActive: true,
            isRecording: false
        )
        let controller = recorder.makeController()
        controller.start()

        recorder.shortPressHandler?(.dictation)

        XCTAssertEqual(recorder.cancelCount, 1)
        XCTAssertEqual(recorder.decisions, [.startNotesRecording])
    }

    func testStartFailureSchedulesAccessibilityAlert() {
        let recorder = HotKeyFeatureRecorder()
        recorder.monitorStartResult = false
        let controller = recorder.makeController()

        controller.start()

        XCTAssertEqual(recorder.scheduledAccessibilityAlertCount, 1)
        XCTAssertEqual(recorder.accessibilityAlertCount, 0)

        recorder.runScheduledAccessibilityAlerts()

        XCTAssertEqual(recorder.accessibilityAlertCount, 1)
    }

    func testStopStopsMonitorAndCancelsDelayedPress() {
        let recorder = HotKeyFeatureRecorder()
        let controller = recorder.makeController()

        controller.stop()

        XCTAssertEqual(recorder.monitorStopCount, 1)
        XCTAssertEqual(recorder.cancelCount, 1)
    }

    func testWorkflowShortcutIsPerformedAndConsumed() {
        let recorder = HotKeyFeatureRecorder()
        let controller = recorder.makeController()
        controller.start()

        let consumed = recorder.workflowShortcutHandler?(.clipboardImageOCR)

        XCTAssertEqual(consumed, true)
        XCTAssertEqual(recorder.workflowShortcuts, [.clipboardImageOCR])
    }

    func testCancelShortcutDelegatesPassThroughDecisionToPerformer() {
        let recorder = HotKeyFeatureRecorder()
        recorder.dictationState = .idle
        recorder.workflowShortcutShouldConsume = false
        let controller = recorder.makeController()
        controller.start()

        let consumed = recorder.workflowShortcutHandler?(.cancel)

        XCTAssertEqual(consumed, false)
        XCTAssertEqual(recorder.workflowShortcuts, [.cancel])
    }

    func testCancelShortcutIsPerformedWhileRecording() {
        let recorder = HotKeyFeatureRecorder()
        recorder.dictationState = .recording
        let controller = recorder.makeController()
        controller.start()

        let consumed = recorder.workflowShortcutHandler?(.cancel)

        XCTAssertEqual(consumed, true)
        XCTAssertEqual(recorder.workflowShortcuts, [.cancel])
    }
}

@MainActor
private final class HotKeyFeatureRecorder {
    var dictationState: DictationState = .idle
    var activeVoiceAction: VoiceAction?
    var notesState = HotKeyNotesState(
        shouldCaptureHotKey: false,
        isActive: false,
        isRecording: false
    )
    var shortPressBehavior: ShortPressBehavior = .none
    var longPressThreshold: TimeInterval = 0.25
    var primaryVoiceAction: VoiceAction = .dictation
    var monitorStartResult = true
    var workflowShortcutShouldConsume = true

    private(set) var monitorStartCount = 0
    private(set) var monitorStopCount = 0
    private(set) var cancelCount = 0
    private(set) var scheduledActions: [VoiceAction] = []
    private(set) var scheduledThresholds: [TimeInterval] = []
    private(set) var decisions: [HotKeyRoutingDecision] = []
    private(set) var workflowShortcuts: [HotKeyWorkflowShortcut] = []
    private(set) var accessibilityAlertCount = 0
    private(set) var scheduledAccessibilityAlertCount = 0

    var pressHandler: ((VoiceAction) -> Void)?
    var releaseHandler: ((VoiceAction) -> Void)?
    var shortPressHandler: ((VoiceAction) -> Void)?
    var workflowShortcutHandler: ((HotKeyWorkflowShortcut) -> Bool)?

    private var scheduledPressHandler: ((VoiceAction) -> Void)?
    private var scheduledAccessibilityAlerts: [() -> Void] = []

    func makeController() -> HotKeyFeatureController {
        HotKeyFeatureController(
            monitor: HotKeyMonitorClient(
                setPressHandler: { [weak self] handler in
                    self?.pressHandler = handler
                },
                setReleaseHandler: { [weak self] handler in
                    self?.releaseHandler = handler
                },
                setShortPressHandler: { [weak self] handler in
                    self?.shortPressHandler = handler
                },
                setWorkflowShortcutHandler: { [weak self] handler in
                    self?.workflowShortcutHandler = handler
                },
                start: { [weak self] in
                    self?.monitorStartCount += 1
                    return self?.monitorStartResult ?? false
                },
                stop: { [weak self] in
                    self?.monitorStopCount += 1
                }
            ),
            delayedPress: DelayedHotKeyPressClient(
                schedule: { [weak self] action, threshold, handler in
                    self?.scheduledActions.append(action)
                    self?.scheduledThresholds.append(threshold)
                    self?.scheduledPressHandler = handler
                },
                cancel: { [weak self] in
                    self?.cancelCount += 1
                }
            ),
            longPressThreshold: { [weak self] in
                self?.longPressThreshold ?? 0.0
            },
            currentShortPressBehavior: { [weak self] in
                self?.shortPressBehavior ?? .none
            },
            currentDictationState: { [weak self] in
                self?.dictationState ?? .idle
            },
            activeVoiceAction: { [weak self] in
                self?.activeVoiceAction
            },
            primaryVoiceAction: { [weak self] in
                self?.primaryVoiceAction ?? .dictation
            },
            currentNotesState: { [weak self] in
                self?.notesState ?? HotKeyNotesState(
                    shouldCaptureHotKey: false,
                    isActive: false,
                    isRecording: false
                )
            },
            performDecision: { [weak self] decision in
                self?.decisions.append(decision)
            },
            performWorkflowShortcut: { [weak self] shortcut in
                self?.workflowShortcuts.append(shortcut)
                return self?.workflowShortcutShouldConsume ?? false
            },
            scheduleAccessibilityAlert: { [weak self] alert in
                self?.scheduledAccessibilityAlertCount += 1
                self?.scheduledAccessibilityAlerts.append(alert)
            },
            showAccessibilityAlert: { [weak self] in
                self?.accessibilityAlertCount += 1
            }
        )
    }

    func fireScheduledPress() {
        scheduledPressHandler?(scheduledActions.last ?? .dictation)
    }

    func runScheduledAccessibilityAlerts() {
        let alerts = scheduledAccessibilityAlerts
        scheduledAccessibilityAlerts.removeAll()
        alerts.forEach { $0() }
    }
}
