import Foundation

@MainActor
enum HUDTemporaryMessageTone: Equatable {
    case info
    case success
}

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
        tone: HUDTemporaryMessageTone,
        action: (() -> Void)?
    )
}

@MainActor
final class VoiceHUDFeatureController {
    enum Snapshot: Equatable {
        case hidden
        case preparing
        case recording(action: VoiceAction?)
        case waitingForFinal(showIndicator: Bool)
        case recognizing(text: String)
        case finalizing(text: String)
        case processing
        case inserting
        case completed(text: String)
        case failedMessage(String)
        case agentComposeStage(AgentComposeHUDStage)
        case transcription(text: String, isRefining: Bool)
        case streamingText(String)
        case audioLevel(Float)
    }

    enum WorkflowFeedback {
        case pasteLastResultSucceeded
        case clipboardImageOCRAlreadyRunning
        case clipboardImageOCRSucceeded
        case noPasteLastResult
        case noClipboardImage
        case clipboardImageOCRFailed(String)
        case pasteOutputFailed(recovery: () -> Void)
        case clipboardImageOCROutputFailed(recovery: () -> Void)
        case agentComposeCopied
        case agentComposeInjected
        case agentComposeTargetChangedCopied
        case agentComposePermissionDeniedCopied
        case agentComposeInjectionFailedCopied
        case agentComposeCopyFailed(recovery: () -> Void)
        case noCopyableResult
        case manualCopySucceeded
        case manualCopyFailed
    }

    private let overlay: any HUDOverlayControlling

    init(overlay: any HUDOverlayControlling) {
        self.overlay = overlay
    }

    func handleState(
        _ state: DictationState,
        activeVoiceAction: VoiceAction?,
        shouldShowWaitingIndicator: Bool
    ) {
        render(
            Self.snapshot(
                state: state,
                activeVoiceAction: activeVoiceAction,
                shouldShowWaitingIndicator: shouldShowWaitingIndicator
            )
        )
    }

    func render(_ snapshot: Snapshot) {
        switch snapshot {
        case .hidden:
            overlay.dismiss()
        case .preparing:
            overlay.show()
            overlay.updateTranscription("准备识别...", isRefining: true)
        case let .recording(action):
            if action == .agentCompose {
                overlay.showWithoutReset()
            } else {
                overlay.show()
                overlay.updateTranscription("", isRefining: false)
            }
        case let .waitingForFinal(showIndicator):
            if showIndicator {
                overlay.updateTranscription("正在识别...", isRefining: true)
            }
        case let .recognizing(text):
            overlay.show()
            if text.isEmpty {
                overlay.updateTranscription("", isRefining: false)
            } else {
                overlay.updateStreamingText(text)
            }
        case let .finalizing(text):
            overlay.updateTranscription(
                text.isEmpty ? "正在识别..." : text,
                isRefining: true
            )
        case .processing:
            overlay.showWithoutReset()
            overlay.updateTranscription("正在处理...", isRefining: true)
        case .inserting:
            overlay.showWithoutReset()
            overlay.updateTranscription("正在写入...", isRefining: true)
        case let .completed(text):
            overlay.updateTranscription(text, isRefining: false)
        case let .failedMessage(message):
            overlay.showTemporaryMessage(message, duration: 6.0, tone: .info, action: nil)
        case let .agentComposeStage(stage):
            overlay.updateAgentComposeStatus(stage)
            overlay.showWithoutReset()
        case let .transcription(text, isRefining):
            overlay.updateTranscription(text, isRefining: isRefining)
        case let .streamingText(partialText):
            overlay.updateStreamingText(partialText)
        case let .audioLevel(rms):
            overlay.updateRMS(rms)
        }
    }

    static func snapshot(
        state: DictationState,
        activeVoiceAction: VoiceAction?,
        shouldShowWaitingIndicator: Bool
    ) -> Snapshot {
        switch state {
        case .idle, .failed:
            return .hidden
        case .injecting:
            return .inserting
        case .recording:
            return .recording(action: activeVoiceAction)
        case .waitingForFinal:
            return .waitingForFinal(showIndicator: shouldShowWaitingIndicator)
        case .processing:
            return .processing
        }
    }

    static func snapshot(phase: ASRSessionPresentationPhase) -> Snapshot {
        switch phase {
        case .idle:
            return .hidden
        case .preparing:
            return .preparing
        case .recognizing(let text):
            return .recognizing(text: text)
        case .waitingForFinal(let text):
            return .finalizing(text: text)
        case .completed(let text):
            return .completed(text: text)
        case .failed(let message):
            return .failedMessage(message)
        }
    }

    func updateTranscription(_ text: String, isRefining: Bool) {
        render(.transcription(text: text, isRefining: isRefining))
    }

    func processingStarted(_ text: String) {
        render(.transcription(text: text, isRefining: true))
    }

    func handleAgentComposeStage(_ stage: AgentComposeHUDStage) {
        render(.agentComposeStage(stage))
    }

    func updateStreamingText(_ partialText: String) {
        render(.streamingText(partialText))
    }

    func updateRMS(_ rms: Float) {
        render(.audioLevel(rms))
    }

    func handleASRPresentation(_ phase: ASRSessionPresentationPhase) {
        render(Self.snapshot(phase: phase))
    }

    func handleRecognitionErrorFeedback(
        _ feedback: RecognitionErrorHUDFeedback,
        action: (() -> Void)? = nil
    ) {
        showTemporaryMessage(
            feedback.message,
            duration: feedback.duration,
            action: feedback.isActionable ? action : nil
        )
    }

    func handleWorkflowFeedback(_ feedback: WorkflowFeedback) {
        switch feedback {
        case .pasteLastResultSucceeded:
            showTemporaryMessage("已粘贴上次结果", duration: 1.8, tone: .success)
        case .clipboardImageOCRAlreadyRunning:
            showTemporaryMessage("剪贴板图片 OCR 正在处理中", duration: 2.2)
        case .clipboardImageOCRSucceeded:
            showTemporaryMessage("已识别图片文字并粘贴", duration: 2.2, tone: .success)
        case .noPasteLastResult:
            showTemporaryMessage("没有可粘贴的上次结果", duration: 2.2)
        case .noClipboardImage:
            showTemporaryMessage("剪贴板里没有可识别的图片", duration: 2.2)
        case .clipboardImageOCRFailed(let reason):
            showTemporaryMessage("图片 OCR 失败：\(reason)", duration: 3.0)
        case .pasteOutputFailed(let recovery):
            showTemporaryMessage(
                "粘贴失败，结果已保留。点此复制",
                duration: 8.0,
                action: recovery
            )
        case .clipboardImageOCROutputFailed(let recovery):
            showTemporaryMessage(
                "OCR 粘贴失败，结果已保留。点此复制",
                duration: 8.0,
                action: recovery
            )
        case .agentComposeCopied:
            showTemporaryMessage("已生成并复制到剪贴板", duration: 2.5, tone: .success)
        case .agentComposeInjected:
            showTemporaryMessage("已生成并写入当前输入框", duration: 2.5, tone: .success)
        case .agentComposeTargetChangedCopied:
            showTemporaryMessage("目标窗口已变化，内容已复制", duration: 3.0)
        case .agentComposePermissionDeniedCopied:
            showTemporaryMessage("没有辅助功能权限，内容已复制", duration: 3.0)
        case .agentComposeInjectionFailedCopied:
            showTemporaryMessage("写入失败，内容已复制", duration: 3.0)
        case .agentComposeCopyFailed(let recovery):
            showTemporaryMessage(
                "生成完成，但复制失败。点此手动复制",
                duration: 8.0,
                action: recovery
            )
        case .noCopyableResult:
            showTemporaryMessage("没有可复制的结果", duration: 2.2)
        case .manualCopySucceeded:
            showTemporaryMessage("已手动复制结果", duration: 1.8, tone: .success)
        case .manualCopyFailed:
            showTemporaryMessage("手动复制失败，请稍后重试", duration: 3.0)
        }
    }

    func showTemporaryMessage(
        _ message: String,
        duration: TimeInterval,
        tone: HUDTemporaryMessageTone = .info,
        action: (() -> Void)? = nil
    ) {
        overlay.showTemporaryMessage(message, duration: duration, tone: tone, action: action)
    }
}

extension OverlayWindowController: HUDOverlayControlling {}
