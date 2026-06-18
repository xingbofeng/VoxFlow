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
    }

    func testPressStartsDictationImmediatelyWhenIdle() {
        let recorder = HotKeyFeatureRecorder()
        recorder.dictationState = .idle
        recorder.shortPressBehavior = .none
        recorder.longPressThreshold = 0.42
        let controller = recorder.makeController()
        controller.start()

        recorder.pressHandler?(.dictation)

        XCTAssertTrue(recorder.scheduledActions.isEmpty)
        XCTAssertTrue(recorder.scheduledThresholds.isEmpty)
        XCTAssertEqual(recorder.decisions, [.startDictation(.dictation)])
    }

    func testPressSchedulesLongPressWhenShortPressToggleIsEnabled() {
        let recorder = HotKeyFeatureRecorder()
        recorder.dictationState = .idle
        recorder.shortPressBehavior = .toggleListening
        recorder.longPressThreshold = 0.42
        let controller = recorder.makeController()
        controller.start()

        recorder.pressHandler?(.dictation)

        XCTAssertEqual(recorder.scheduledActions, [.dictation])
        XCTAssertEqual(recorder.scheduledThresholds, [0.42])
        XCTAssertTrue(recorder.decisions.isEmpty)

        recorder.fireScheduledPress()

        XCTAssertEqual(recorder.decisions, [.startDictation(.dictation)])
    }

    func testShortPressStartsDictationWithoutReleasingWhenToggleIsEnabled() {
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
    var monitorStartResult = true

    private(set) var monitorStartCount = 0
    private(set) var monitorStopCount = 0
    private(set) var cancelCount = 0
    private(set) var scheduledActions: [VoiceAction] = []
    private(set) var scheduledThresholds: [TimeInterval] = []
    private(set) var decisions: [HotKeyRoutingDecision] = []
    private(set) var accessibilityAlertCount = 0
    private(set) var scheduledAccessibilityAlertCount = 0

    var pressHandler: ((VoiceAction) -> Void)?
    var releaseHandler: ((VoiceAction) -> Void)?
    var shortPressHandler: ((VoiceAction) -> Void)?

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
