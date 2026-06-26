import Foundation

@MainActor
struct HotKeyMonitorClient {
    typealias Handler = @MainActor (VoiceAction) -> Void
    typealias WorkflowShortcutHandler = @MainActor (HotKeyWorkflowShortcut) -> Bool

    let setPressHandler: (@escaping Handler) -> Void
    let setReleaseHandler: (@escaping Handler) -> Void
    let setShortPressHandler: (@escaping Handler) -> Void
    let setWorkflowShortcutHandler: (@escaping WorkflowShortcutHandler) -> Void
    let start: () -> Bool
    let stop: () -> Void

    static func live(keyMonitor: KeyMonitor) -> HotKeyMonitorClient {
        HotKeyMonitorClient(
            setPressHandler: { handler in
                keyMonitor.onHotKeyPress = { action in
                    MainActor.assumeIsolated {
                        handler(action)
                    }
                }
            },
            setReleaseHandler: { handler in
                keyMonitor.onHotKeyRelease = { action in
                    MainActor.assumeIsolated {
                        handler(action)
                    }
                }
            },
            setShortPressHandler: { handler in
                keyMonitor.onShortPress = { action in
                    MainActor.assumeIsolated {
                        handler(action)
                    }
                }
            },
            setWorkflowShortcutHandler: { handler in
                keyMonitor.onWorkflowShortcut = { shortcut in
                    MainActor.assumeIsolated {
                        handler(shortcut)
                    }
                }
            },
            start: {
                keyMonitor.start()
            },
            stop: {
                keyMonitor.stop()
            }
        )
    }
}

@MainActor
struct DelayedHotKeyPressClient {
    typealias Handler = @MainActor (VoiceAction) -> Void

    let schedule: (VoiceAction, TimeInterval, @escaping Handler) -> Void
    let cancel: () -> Void

    static func live(
        controller: DelayedHotKeyPressController
    ) -> DelayedHotKeyPressClient {
        DelayedHotKeyPressClient(
            schedule: { action, threshold, handler in
                controller.schedule(action: action, threshold: threshold) { action in
                    handler(action)
                }
            },
            cancel: {
                controller.cancel()
            }
        )
    }
}

@MainActor
final class HotKeyFeatureController {
    private static let logger = AppLogger.general
    private let monitor: HotKeyMonitorClient
    private let delayedPress: DelayedHotKeyPressClient
    private let longPressThreshold: () -> TimeInterval
    private let currentShortPressBehavior: () -> ShortPressBehavior
    private let currentDictationState: () -> DictationState
    private let activeVoiceAction: () -> VoiceAction?
    private let primaryVoiceAction: () -> VoiceAction
    private let currentNotesState: () -> HotKeyNotesState
    private let performDecision: (HotKeyRoutingDecision) -> Void
    private let performWorkflowShortcut: (HotKeyWorkflowShortcut) -> Bool
    private let scheduleAccessibilityAlert: (@escaping @MainActor @Sendable () -> Void) -> Void
    private let showAccessibilityAlert: () -> Void
    private var actionStartedOnCurrentPress: VoiceAction?

    init(
        monitor: HotKeyMonitorClient,
        delayedPress: DelayedHotKeyPressClient,
        longPressThreshold: @escaping () -> TimeInterval,
        currentShortPressBehavior: @escaping () -> ShortPressBehavior = { .none },
        currentDictationState: @escaping () -> DictationState,
        activeVoiceAction: @escaping () -> VoiceAction?,
        primaryVoiceAction: @escaping () -> VoiceAction = { .dictation },
        currentNotesState: @escaping () -> HotKeyNotesState,
        performDecision: @escaping (HotKeyRoutingDecision) -> Void,
        performWorkflowShortcut: @escaping (HotKeyWorkflowShortcut) -> Bool = { _ in false },
        scheduleAccessibilityAlert: @escaping (@escaping @MainActor @Sendable () -> Void) -> Void,
        showAccessibilityAlert: @escaping () -> Void
    ) {
        self.monitor = monitor
        self.delayedPress = delayedPress
        self.longPressThreshold = longPressThreshold
        self.currentShortPressBehavior = currentShortPressBehavior
        self.currentDictationState = currentDictationState
        self.activeVoiceAction = activeVoiceAction
        self.primaryVoiceAction = primaryVoiceAction
        self.currentNotesState = currentNotesState
        self.performDecision = performDecision
        self.performWorkflowShortcut = performWorkflowShortcut
        self.scheduleAccessibilityAlert = scheduleAccessibilityAlert
        self.showAccessibilityAlert = showAccessibilityAlert
    }

    func start() {
        Self.logger.debug("hotkey_feature_controller_start")
        monitor.setPressHandler { [weak self] action in
            self?.handlePress(action)
        }
        monitor.setReleaseHandler { [weak self] action in
            self?.handleRelease(action)
        }
        monitor.setShortPressHandler { [weak self] action in
            self?.handleShortPress(action)
        }
        monitor.setWorkflowShortcutHandler { [weak self] shortcut in
            self?.handleWorkflowShortcut(shortcut) ?? false
        }

        guard monitor.start() else {
            Self.logger.warning("hotkey_feature_controller_start_failed monitor.start returned false")
            scheduleAccessibilityAlert { [weak self] in
                self?.showAccessibilityAlert()
            }
            return
        }
        Self.logger.debug("hotkey_feature_controller_started")
    }

    func stop() {
        Self.logger.debug("hotkey_feature_controller_stop")
        monitor.stop()
        delayedPress.cancel()
    }

    private func handlePress(_ action: VoiceAction) {
        Self.logger.debug("hotkey_handle_press action=\(action.logName) state=\(currentDictationState())")
        let notesState = currentNotesState()
        let action = resolvedAction(for: action, notesState: notesState)
        guard currentDictationState().isIdle else {
            Self.logger.debug("hotkey_handle_press ignored state=\(currentDictationState())")
            return
        }
        guard action == .dictation || !notesState.isActive || !notesState.isRecording else {
            Self.logger.debug(
                "hotkey_handle_press ignored notesState.active=\(notesState.isActive) notesState.recording=\(notesState.isRecording)"
            )
            return
        }
        if currentShortPressBehavior() == .toggleListening {
            Self.logger.debug("hotkey_handle_press direct decision action=\(action.logName)")
            actionStartedOnCurrentPress = action
            performPressDecision(action)
            return
        }
        actionStartedOnCurrentPress = nil
        delayedPress.schedule(action, longPressThreshold()) { [weak self] action in
            guard let self else { return }
            guard self.currentDictationState().isIdle else { return }
            guard self.actionStartedOnCurrentPress != action else { return }
            self.actionStartedOnCurrentPress = action
            Self.logger.debug("hotkey_handle_press delayed action=\(action.logName)")
            self.performPressDecision(action)
        }
    }

    private func performPressDecision(_ action: VoiceAction) {
        performLoggedDecision(for: .press, action: action)
    }

    private func handleRelease(_ action: VoiceAction) {
        Self.logger.debug("hotkey_handle_release action=\(action.logName)")
        let action = resolvedAction(for: action, notesState: currentNotesState())
        delayedPress.cancel()
        guard actionStartedOnCurrentPress == action || activeVoiceAction() == action else {
            Self.logger.debug(
                "hotkey_handle_release ignored started=\(actionStartedOnCurrentPress?.logName ?? "nil") active=\(activeVoiceAction()?.logName ?? "nil")"
            )
            actionStartedOnCurrentPress = nil
            return
        }
        actionStartedOnCurrentPress = nil
        performLoggedDecision(for: .release, action: action)
    }

    private func handleShortPress(_ action: VoiceAction) {
        Self.logger.debug("hotkey_handle_short_press action=\(action.logName)")
        let notesState = currentNotesState()
        let action = resolvedAction(for: action, notesState: notesState)
        delayedPress.cancel()
        if actionStartedOnCurrentPress == action {
            Self.logger.debug("hotkey_handle_short_press ignored: action in progress")
            actionStartedOnCurrentPress = nil
            return
        }
        if action == .dictation, currentNotesState().shouldCaptureHotKey {
            Self.logger.debug("hotkey_handle_short_press notes capture path action=\(action.logName)")
            performLoggedDecision(for: .shortPress, action: action)
            return
        }
        guard currentShortPressBehavior() == .toggleListening else {
            Self.logger.debug("hotkey_handle_short_press ignored toggleListening disabled")
            return
        }
        performLoggedDecision(for: .shortPress, action: action)
    }

    private func resolvedAction(for action: VoiceAction, notesState: HotKeyNotesState) -> VoiceAction {
        guard action == .dictation, !notesState.shouldCaptureHotKey else {
            return action
        }
        let resolved = primaryVoiceAction()
        Self.logger.debug("hotkey_resolved_action input=\(action.logName) shouldCapture=\(notesState.shouldCaptureHotKey) resolved=\(resolved.logName)")
        return resolved
    }

    private func handleWorkflowShortcut(_ shortcut: HotKeyWorkflowShortcut) -> Bool {
        let shouldConsume: Bool
        switch shortcut {
        case .cancel:
            shouldConsume = performWorkflowShortcut(shortcut)
        case .palette:
            shouldConsume = performWorkflowShortcut(shortcut)
        case .clipboardImageOCR:
            shouldConsume = performWorkflowShortcut(shortcut)
        case .screenshotOCR:
            shouldConsume = performWorkflowShortcut(shortcut)
        case .selectionAction:
            shouldConsume = performWorkflowShortcut(shortcut)
        case .selectionTranslate:
            shouldConsume = performWorkflowShortcut(shortcut)
        case .selectionSummarize:
            shouldConsume = performWorkflowShortcut(shortcut)
        case .selectionAgent:
            shouldConsume = performWorkflowShortcut(shortcut)
        case .selectionAskAI:
            shouldConsume = performWorkflowShortcut(shortcut)
        }
        AppLogger.general.info(
            "hotkey_workflow_decision shortcut=\(shortcut.logName) decision=\(shouldConsume ? "consume" : "passThrough")"
        )
        return shouldConsume
    }

    private func performLoggedDecision(
        for event: HotKeyRoutingEvent,
        action: VoiceAction
    ) {
        let decision = decision(for: event, action: action)
        AppLogger.general.info(
            "hotkey_decision event=\(event.logName) action=\(action.logName) decision=\(decision.logName)"
        )
        performDecision(decision)
    }

    private func decision(
        for event: HotKeyRoutingEvent,
        action: VoiceAction
    ) -> HotKeyRoutingDecision {
        HotKeyRoutingPolicy.decision(
            for: event,
            action: action,
            dictationState: currentDictationState(),
            activeVoiceAction: activeVoiceAction(),
            notesState: currentNotesState()
        )
    }
}

private extension HotKeyRoutingEvent {
    var logName: String {
        switch self {
        case .press:
            return "press"
        case .release:
            return "release"
        case .shortPress:
            return "shortPress"
        }
    }
}

private extension HotKeyRoutingDecision {
    var logName: String {
        switch self {
        case .ignore:
            return "ignore"
        case .startNotesRecording:
            return "startNotesRecording"
        case .finishNotesRecording:
            return "finishNotesRecording"
        case .startDictation(let action):
            return "startDictation.\(action.logName)"
        case .releaseDictation(let action):
            return "releaseDictation.\(action.logName)"
        }
    }
}

private extension HotKeyWorkflowShortcut {
    var logName: String {
        switch self {
        case .palette:
            return "palette"
        case .clipboardImageOCR:
            return "clipboardImageOCR"
        case .screenshotOCR:
            return "screenshotOCR"
        case .selectionAction:
            return "selectionAction"
        case .selectionTranslate:
            return "selectionTranslate"
        case .selectionSummarize:
            return "selectionSummarize"
        case .selectionAgent:
            return "selectionAgent"
        case .selectionAskAI:
            return "selectionAskAI"
        case .cancel:
            return "cancel"
        }
    }
}

private extension VoiceAction {
    var logName: String {
        switch self {
        case .dictation:
            return "dictation"
        case .agentCompose:
            return "agentCompose"
        case .agentDispatch:
            return "agentDispatch"
        }
    }
}
