import Foundation

struct DictationStatePresentationResult: Equatable {
    let shouldClearActiveVoiceAction: Bool
}

@MainActor
final class DictationStatePresentationController {
    typealias HandleFeedbackState = (DictationState) -> Void
    typealias HandleHUDState = (DictationState, VoiceAction?, Bool) -> Void
    typealias ShouldShowWaitingIndicator = (VoiceAction?) -> Bool
    typealias MonitorAction = () -> Void
    typealias SetRefiningStatusVisible = (Bool) -> Void

    private let handleFeedbackState: HandleFeedbackState
    private let handleHUDState: HandleHUDState
    private let shouldShowWaitingIndicator: ShouldShowWaitingIndicator
    private let startCancelMonitor: MonitorAction
    private let stopCancelMonitor: MonitorAction
    private let setRefiningStatusVisible: SetRefiningStatusVisible

    init(
        handleFeedbackState: @escaping HandleFeedbackState,
        handleHUDState: @escaping HandleHUDState,
        shouldShowWaitingIndicator: @escaping ShouldShowWaitingIndicator,
        startCancelMonitor: @escaping MonitorAction,
        stopCancelMonitor: @escaping MonitorAction,
        setRefiningStatusVisible: @escaping SetRefiningStatusVisible
    ) {
        self.handleFeedbackState = handleFeedbackState
        self.handleHUDState = handleHUDState
        self.shouldShowWaitingIndicator = shouldShowWaitingIndicator
        self.startCancelMonitor = startCancelMonitor
        self.stopCancelMonitor = stopCancelMonitor
        self.setRefiningStatusVisible = setRefiningStatusVisible
    }

    func handle(
        _ state: DictationState,
        activeVoiceAction: VoiceAction?
    ) -> DictationStatePresentationResult {
        handleFeedbackState(state)
        handleHUDState(
            state,
            activeVoiceAction,
            shouldShowWaitingIndicator(activeVoiceAction)
        )

        switch state {
        case .idle:
            stopCancelMonitor()
            setRefiningStatusVisible(false)
            return DictationStatePresentationResult(shouldClearActiveVoiceAction: true)
        case .recording:
            startCancelMonitor()
            setRefiningStatusVisible(false)
        case .waitingForFinal:
            break
        case .processing:
            setRefiningStatusVisible(true)
        case .injecting:
            stopCancelMonitor()
            setRefiningStatusVisible(false)
        case .failed:
            stopCancelMonitor()
            setRefiningStatusVisible(false)
        }

        return DictationStatePresentationResult(shouldClearActiveVoiceAction: false)
    }
}
