import Foundation

@MainActor
struct HotKeyMonitorClient {
    typealias Handler = @MainActor (VoiceAction) -> Void

    let setPressHandler: (@escaping Handler) -> Void
    let setReleaseHandler: (@escaping Handler) -> Void
    let setShortPressHandler: (@escaping Handler) -> Void
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
    private let monitor: HotKeyMonitorClient
    private let delayedPress: DelayedHotKeyPressClient
    private let longPressThreshold: () -> TimeInterval
    private let currentShortPressBehavior: () -> ShortPressBehavior
    private let currentDictationState: () -> DictationState
    private let activeVoiceAction: () -> VoiceAction?
    private let currentNotesState: () -> HotKeyNotesState
    private let performDecision: (HotKeyRoutingDecision) -> Void
    private let scheduleAccessibilityAlert: (@escaping @MainActor @Sendable () -> Void) -> Void
    private let showAccessibilityAlert: () -> Void

    init(
        monitor: HotKeyMonitorClient,
        delayedPress: DelayedHotKeyPressClient,
        longPressThreshold: @escaping () -> TimeInterval,
        currentShortPressBehavior: @escaping () -> ShortPressBehavior = { .none },
        currentDictationState: @escaping () -> DictationState,
        activeVoiceAction: @escaping () -> VoiceAction?,
        currentNotesState: @escaping () -> HotKeyNotesState,
        performDecision: @escaping (HotKeyRoutingDecision) -> Void,
        scheduleAccessibilityAlert: @escaping (@escaping @MainActor @Sendable () -> Void) -> Void,
        showAccessibilityAlert: @escaping () -> Void
    ) {
        self.monitor = monitor
        self.delayedPress = delayedPress
        self.longPressThreshold = longPressThreshold
        self.currentShortPressBehavior = currentShortPressBehavior
        self.currentDictationState = currentDictationState
        self.activeVoiceAction = activeVoiceAction
        self.currentNotesState = currentNotesState
        self.performDecision = performDecision
        self.scheduleAccessibilityAlert = scheduleAccessibilityAlert
        self.showAccessibilityAlert = showAccessibilityAlert
    }

    func start() {
        monitor.setPressHandler { [weak self] action in
            self?.handlePress(action)
        }
        monitor.setReleaseHandler { [weak self] action in
            self?.handleRelease(action)
        }
        monitor.setShortPressHandler { [weak self] action in
            self?.handleShortPress(action)
        }

        guard monitor.start() else {
            scheduleAccessibilityAlert { [weak self] in
                self?.showAccessibilityAlert()
            }
            return
        }
    }

    func stop() {
        monitor.stop()
        delayedPress.cancel()
    }

    private func handlePress(_ action: VoiceAction) {
        guard currentDictationState().isIdle else { return }
        if action == .dictation, currentShortPressBehavior() == .toggleListening {
            delayedPress.schedule(action, longPressThreshold()) { [weak self] action in
                self?.performPressDecision(action)
            }
            return
        }
        performPressDecision(action)
    }

    private func performPressDecision(_ action: VoiceAction) {
        performDecision(decision(for: .press, action: action))
    }

    private func handleRelease(_ action: VoiceAction) {
        delayedPress.cancel()
        performDecision(decision(for: .release, action: action))
    }

    private func handleShortPress(_ action: VoiceAction) {
        delayedPress.cancel()
        if action == .dictation, currentNotesState().shouldCaptureHotKey {
            performDecision(decision(for: .shortPress, action: action))
            return
        }
        guard currentShortPressBehavior() == .toggleListening else { return }
        performDecision(decision(for: .shortPress, action: action))
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
