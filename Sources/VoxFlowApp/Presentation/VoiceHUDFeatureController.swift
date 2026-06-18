import Foundation

@MainActor
protocol HUDOverlayControlling: AnyObject {
    func show()
    func showWithoutReset()
    func dismiss()
    func updateTranscription(_ text: String, isRefining: Bool)
    func updateAgentComposeStatus(_ stage: AgentComposeHUDStage)
    func updateStreamingText(_ partialText: String)
    func updateRMS(_ rms: Float)
    func showTemporaryMessage(
        _ message: String,
        duration: TimeInterval,
        action: (() -> Void)?
    )
}

@MainActor
final class VoiceHUDFeatureController {
    private let overlay: any HUDOverlayControlling

    init(overlay: any HUDOverlayControlling) {
        self.overlay = overlay
    }

    func handleState(
        _ state: DictationState,
        activeVoiceAction: VoiceAction?,
        shouldShowWaitingIndicator: Bool
    ) {
        switch state {
        case .idle, .injecting, .failed:
            overlay.dismiss()
        case .recording:
            if activeVoiceAction == .agentCompose {
                overlay.showWithoutReset()
            } else {
                overlay.show()
                overlay.updateTranscription("", isRefining: false)
            }
        case .waitingForFinal:
            if shouldShowWaitingIndicator {
                overlay.updateTranscription("正在识别...", isRefining: true)
            }
        case .processing:
            break
        }
    }

    func updateTranscription(_ text: String, isRefining: Bool) {
        overlay.updateTranscription(text, isRefining: isRefining)
    }

    func processingStarted(_ text: String) {
        overlay.updateTranscription(text, isRefining: true)
    }

    func handleAgentComposeStage(_ stage: AgentComposeHUDStage) {
        overlay.updateAgentComposeStatus(stage)
        overlay.showWithoutReset()
    }

    func updateStreamingText(_ partialText: String) {
        overlay.updateStreamingText(partialText)
    }

    func updateRMS(_ rms: Float) {
        overlay.updateRMS(rms)
    }

    func handleASRPresentation(_ phase: ASRSessionPresentationPhase) {
        switch phase {
        case .idle:
            overlay.dismiss()
        case .preparing:
            overlay.show()
            overlay.updateTranscription("准备识别...", isRefining: true)
        case .recognizing(let text):
            overlay.show()
            if text.isEmpty {
                overlay.updateTranscription("", isRefining: false)
            } else {
                overlay.updateStreamingText(text)
            }
        case .waitingForFinal(let text):
            overlay.updateTranscription(
                text.isEmpty ? "正在识别..." : text,
                isRefining: true
            )
        case .completed(let text):
            overlay.updateTranscription(text, isRefining: false)
        case .failed(let message):
            overlay.showTemporaryMessage(message, duration: 3.0, action: nil)
        }
    }

    func showTemporaryMessage(
        _ message: String,
        duration: TimeInterval,
        action: (() -> Void)? = nil
    ) {
        overlay.showTemporaryMessage(message, duration: duration, action: action)
    }
}

extension OverlayWindowController: HUDOverlayControlling {}
