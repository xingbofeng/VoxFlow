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
    func dismissAfterDefaultHUDTimeout()
    func dismiss()
    func updateTranscription(_ text: String, isRefining: Bool)
    func updateAgentComposeStatus(_ stage: AgentComposeHUDStage)
    func updateAgentDispatch(_ presentation: AgentDispatchHUDPresentation)
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
    private static let logger = AppLogger.general

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
        case agentDispatch(AgentDispatchHUDPresentation)
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
        Self.logger.debug("voice_hud_feature_controller_init")
    }

    func handleState(
        _ state: DictationState,
        activeVoiceAction: VoiceAction?,
        shouldShowWaitingIndicator: Bool
    ) {
        Self.logger.debug(
            "voice_hud_handle_state state=\(state) action=\(activeVoiceAction?.rawValue ?? "nil") waitingIndicator=\(shouldShowWaitingIndicator)"
        )
        render(
            Self.snapshot(
                state: state,
                activeVoiceAction: activeVoiceAction,
                shouldShowWaitingIndicator: shouldShowWaitingIndicator
            )
        )
    }

    func render(_ snapshot: Snapshot) {
        logRender(snapshot)
        switch snapshot {
        case .hidden:
            overlay.dismiss()
        case .preparing:
            overlay.show()
            overlay.updateTranscription(
                L10n.localize("hud.message.prepare", comment: ""),
                isRefining: true
            )
        case .recording:
            overlay.show()
            overlay.updateTranscription("", isRefining: false)
        case let .waitingForFinal(showIndicator):
            if showIndicator {
                overlay.updateTranscription(
                    L10n.localize("hud.message.recognizing", comment: ""),
                    isRefining: true
                )
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
                text.isEmpty
                    ? L10n.localize("hud.message.recognizing", comment: "")
                    : text,
                isRefining: true
            )
        case .processing:
            overlay.showWithoutReset()
            overlay.updateTranscription(
                L10n.localize("hud.message.processing", comment: ""),
                isRefining: true
            )
        case .inserting:
            overlay.showWithoutReset()
            overlay.updateTranscription(
                L10n.localize("hud.message.writing", comment: ""),
                isRefining: true
            )
        case let .completed(text):
            overlay.updateTranscription(text, isRefining: false)
        case let .failedMessage(message):
            overlay.showTemporaryMessage(message, duration: 6.0, tone: .info, action: nil)
        case let .agentComposeStage(stage):
            overlay.updateAgentComposeStatus(stage)
            overlay.showWithoutReset()
            if stage.shouldDismissAfterDefaultHUDTimeout {
                overlay.dismissAfterDefaultHUDTimeout()
            }
        case let .agentDispatch(presentation):
            overlay.updateAgentDispatch(presentation)
            overlay.showWithoutReset()
            if presentation.shouldDismissAfterDefaultHUDTimeout {
                overlay.dismissAfterDefaultHUDTimeout()
            }
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
        Self.logger.debug("voice_hud_handle_agent_compose_stage stage=\(stage)")
        render(.agentComposeStage(stage))
    }

    func handleAgentDispatch(_ presentation: AgentDispatchHUDPresentation) {
        Self.logger.debug("voice_hud_handle_agent_dispatch presentation=\(presentationLogName(presentation))")
        switch presentation {
        case let .sent(agentName):
            showTemporaryMessage(
                L10n.format("hud.feedback.sent_to_agent_format", comment: "",
                    agentName
                ),
                duration: 2.2,
                tone: .success
            )
        case let .failure(message, retainedText):
            let detail = retainedText.isEmpty
                ? message
                : L10n.format("hud.feedback.command_retained_format", comment: "",
                    message
                )
            showTemporaryMessage(detail, duration: 5.0)
        case .listening:
            render(.recording(action: .agentDispatch))
        case .idle, .exact, .confirmation, .fallbackInput, .clipboardFallback:
            render(.agentDispatch(presentation))
        }
    }

    func updateStreamingText(_ partialText: String) {
        render(.streamingText(partialText))
    }

    func updateRMS(_ rms: Float) {
        render(.audioLevel(rms))
    }

    func handleASRPresentation(_ phase: ASRSessionPresentationPhase) {
        Self.logger.debug("voice_hud_handle_asr_presentation phase=\(asrPhaseLogName(phase))")
        render(Self.snapshot(phase: phase))
    }

    func handleRecognitionErrorFeedback(
        _ feedback: RecognitionErrorHUDFeedback,
        action: (() -> Void)? = nil
    ) {
        Self.logger.debug(
            "voice_hud_handle_recognition_error_feedback duration=\(feedback.duration) actionable=\(feedback.isActionable) messageLen=\(feedback.message.count)"
        )
        showTemporaryMessage(
            feedback.message,
            duration: feedback.duration,
            action: feedback.isActionable ? action : nil
        )
    }

    func handleCorrectionLearning(
        _ event: CorrectionObservationLearningEvent,
        undo: @escaping () -> Void
    ) {
        let message = event.items.count == 1
            ? L10n.format("hud.feedback.undo_prompt_format", comment: "",
                event.message
            )
            : event.message
        showTemporaryMessage(
            message,
            duration: 8.0,
            tone: .success,
            action: undo
        )
    }

    func handleWorkflowFeedback(_ feedback: WorkflowFeedback) {
        Self.logger.debug("voice_hud_handle_workflow_feedback feedback=\(workflowFeedbackLogName(feedback))")
        switch feedback {
        case .pasteLastResultSucceeded:
            showTemporaryMessage(
                L10n.localize("hud.feedback.paste_last_result_succeeded", comment: ""),
                duration: 1.8,
                tone: .success
            )
        case .clipboardImageOCRAlreadyRunning:
            showTemporaryMessage(
                L10n.localize("hud.feedback.clipboard_image_ocr_processing", comment: ""),
                duration: 2.2
            )
        case .clipboardImageOCRSucceeded:
            showTemporaryMessage(
                L10n.localize("hud.feedback.image_text_copied", comment: ""),
                duration: 2.2,
                tone: .success
            )
        case .noPasteLastResult:
            showTemporaryMessage(
                L10n.localize("hud.feedback.no_last_result_to_paste", comment: ""),
                duration: 2.2
            )
        case .noClipboardImage:
            showTemporaryMessage(
                L10n.localize("hud.feedback.no_clipboard_image", comment: ""),
                duration: 2.2
            )
        case .clipboardImageOCRFailed(let reason):
            showTemporaryMessage(
                L10n.format("hud.feedback.clipboard_ocr_failed_format", comment: "",
                    reason
                ),
                duration: 3.0
            )
        case .pasteOutputFailed(let recovery):
            showTemporaryMessage(
                L10n.localize("hud.feedback.paste_failed_retain_copy", comment: ""),
                duration: 8.0,
                action: recovery
            )
        case .clipboardImageOCROutputFailed(let recovery):
            showTemporaryMessage(
                L10n.localize("hud.feedback.image_text_paste_failed_retain_copy", comment: ""),
                duration: 8.0,
                action: recovery
            )
        case .agentComposeCopied:
            showTemporaryMessage(
                L10n.localize("hud.feedback.agent_compose_copied", comment: ""),
                duration: 2.5,
                tone: .success
            )
        case .agentComposeInjected:
            showTemporaryMessage(
                L10n.localize("hud.feedback.agent_compose_injected", comment: ""),
                duration: 2.5,
                tone: .success
            )
        case .agentComposeTargetChangedCopied:
            showTemporaryMessage(
                L10n.localize("hud.feedback.target_window_changed_copied", comment: ""),
                duration: 3.0
            )
        case .agentComposePermissionDeniedCopied:
            showTemporaryMessage(
                L10n.localize("hud.feedback.permission_denied_copied", comment: ""),
                duration: 3.0
            )
        case .agentComposeInjectionFailedCopied:
            showTemporaryMessage(
                L10n.localize("hud.feedback.input_failed_copied", comment: ""),
                duration: 3.0
            )
        case .agentComposeCopyFailed(let recovery):
            showTemporaryMessage(
                L10n.localize("hud.feedback.copy_failed_prompt", comment: ""),
                duration: 8.0,
                action: recovery
            )
        case .noCopyableResult:
            showTemporaryMessage(
                L10n.localize("hud.feedback.no_copyable_result", comment: ""),
                duration: 2.2
            )
        case .manualCopySucceeded:
            showTemporaryMessage(
                L10n.localize("hud.feedback.manual_copy_succeeded", comment: ""),
                duration: 1.8,
                tone: .success
            )
        case .manualCopyFailed:
            showTemporaryMessage(
                L10n.localize("hud.feedback.manual_copy_failed", comment: ""),
                duration: 3.0
            )
        }
    }

    func showTemporaryMessage(
        _ message: String,
        duration: TimeInterval,
        tone: HUDTemporaryMessageTone = .info,
        action: (() -> Void)? = nil
    ) {
        Self.logger.info(
            "voice_hud_show_temporary_message duration=\(duration) tone=\(tone) actionable=\(action != nil) messageLen=\(message.count)"
        )
        overlay.showTemporaryMessage(message, duration: duration, tone: tone, action: action)
    }

    private func logRender(_ snapshot: Snapshot) {
        switch snapshot {
        case .hidden:
            Self.logger.debug("voice_hud_render snapshot=hidden")
        case .preparing:
            Self.logger.debug("voice_hud_render snapshot=preparing")
        case let .recording(action):
            Self.logger.info("voice_hud_render snapshot=recording action=\(action?.rawValue ?? "nil")")
        case let .waitingForFinal(showIndicator):
            Self.logger.info("voice_hud_render snapshot=waitingForFinal indicator=\(showIndicator)")
        case let .recognizing(text):
            Self.logger.debug("voice_hud_render snapshot=recognizing textLen=\(text.count)")
        case let .finalizing(text):
            Self.logger.info("voice_hud_render snapshot=finalizing textLen=\(text.count)")
        case .processing:
            Self.logger.info("voice_hud_render snapshot=processing")
        case .inserting:
            Self.logger.info("voice_hud_render snapshot=inserting")
        case let .completed(text):
            Self.logger.info("voice_hud_render snapshot=completed textLen=\(text.count)")
        case let .failedMessage(message):
            Self.logger.warning("voice_hud_render snapshot=failedMessage messageLen=\(message.count)")
        case let .agentComposeStage(stage):
            Self.logger.debug("voice_hud_render snapshot=agentComposeStage stage=\(stage)")
        case let .agentDispatch(presentation):
            Self.logger.debug("voice_hud_render snapshot=agentDispatch presentation=\(presentationLogName(presentation))")
        case let .transcription(text, isRefining):
            Self.logger.debug("voice_hud_render snapshot=transcription textLen=\(text.count) refining=\(isRefining)")
        case let .streamingText(text):
            Self.logger.debug("voice_hud_render snapshot=streamingText textLen=\(text.count)")
        case let .audioLevel(rms):
            Self.logger.debug("voice_hud_render snapshot=audioLevel rms=\(rms)")
        }
    }

    private func asrPhaseLogName(_ phase: ASRSessionPresentationPhase) -> String {
        switch phase {
        case .idle: return "idle"
        case .preparing: return "preparing"
        case let .recognizing(text): return "recognizing(textLen=\(text.count))"
        case let .waitingForFinal(text): return "waitingForFinal(textLen=\(text.count))"
        case let .completed(text): return "completed(textLen=\(text.count))"
        case let .failed(message): return "failed(messageLen=\(message.count))"
        }
    }

    private func presentationLogName(_ presentation: AgentDispatchHUDPresentation) -> String {
        switch presentation {
        case .idle: return "idle"
        case let .listening(agentNames): return "listening(agentCount=\(agentNames.count))"
        case let .exact(agentName, message): return "exact(agentNameLen=\(agentName.count),messageLen=\(message.count))"
        case let .confirmation(utterance, candidates): return "confirmation(utteranceLen=\(utterance.count),candidateCount=\(candidates.count))"
        case let .fallbackInput(text): return "fallbackInput(textLen=\(text.count))"
        case let .clipboardFallback(text): return "clipboardFallback(textLen=\(text.count))"
        case let .sent(agentName): return "sent(agentNameLen=\(agentName.count))"
        case let .failure(message, retainedText): return "failure(messageLen=\(message.count),retainedLen=\(retainedText.count))"
        }
    }

    private func workflowFeedbackLogName(_ feedback: WorkflowFeedback) -> String {
        switch feedback {
        case .pasteLastResultSucceeded: return "pasteLastResultSucceeded"
        case .clipboardImageOCRAlreadyRunning: return "clipboardImageOCRAlreadyRunning"
        case .clipboardImageOCRSucceeded: return "clipboardImageOCRSucceeded"
        case .noPasteLastResult: return "noPasteLastResult"
        case .noClipboardImage: return "noClipboardImage"
        case let .clipboardImageOCRFailed(reason): return "clipboardImageOCRFailed(reasonLen=\(reason.count))"
        case .pasteOutputFailed: return "pasteOutputFailed"
        case .clipboardImageOCROutputFailed: return "clipboardImageOCROutputFailed"
        case .agentComposeCopied: return "agentComposeCopied"
        case .agentComposeInjected: return "agentComposeInjected"
        case .agentComposeTargetChangedCopied: return "agentComposeTargetChangedCopied"
        case .agentComposePermissionDeniedCopied: return "agentComposePermissionDeniedCopied"
        case .agentComposeInjectionFailedCopied: return "agentComposeInjectionFailedCopied"
        case .agentComposeCopyFailed: return "agentComposeCopyFailed"
        case .noCopyableResult: return "noCopyableResult"
        case .manualCopySucceeded: return "manualCopySucceeded"
        case .manualCopyFailed: return "manualCopyFailed"
        }
    }
}

extension OverlayWindowController: HUDOverlayControlling {}

private extension AgentComposeHUDStage {
    var shouldDismissAfterDefaultHUDTimeout: Bool {
        switch self {
        case .copied, .inserted, .contextUnavailable:
            return true
        case .readingWindow, .transcribing, .generating:
            return false
        }
    }
}

private extension AgentDispatchHUDPresentation {
    var shouldDismissAfterDefaultHUDTimeout: Bool {
        switch self {
        case .fallbackInput, .clipboardFallback, .sent, .failure:
            return true
        case .idle, .listening, .exact, .confirmation:
            return false
        }
    }
}
