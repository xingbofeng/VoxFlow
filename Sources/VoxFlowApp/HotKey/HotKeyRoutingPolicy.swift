import CoreGraphics

struct HotKeyNotesState: Equatable {
    let shouldCaptureHotKey: Bool
    let isActive: Bool
    let isRecording: Bool
}

enum HotKeyRoutingEvent: Equatable {
    case press
    case release
    case shortPress
}

enum HotKeyRoutingDecision: Equatable {
    case ignore
    case startNotesRecording
    case finishNotesRecording
    case startDictation(VoiceAction)
    case releaseDictation(VoiceAction)
}

private enum HotKeyRoutingPolicyLogger {
    static let log = AppLogger.general
}

enum HotKeyWorkflowShortcut: Equatable {
    case clipboardImageOCR
    case screenshotOCR
    case cancel
}

enum ClipboardImageOCRShortcut {
    static let keyCode: Int64 = HotKeyShortcutRouting.vKeyCode

    static func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        HotKeyShortcutRouting.workflowShortcut(
            keyCode: keyCode,
            flags: flags,
            clipboardImageOCRKeyCode: ShortcutManager.defaultClipboardImageOCRShortcutKeyCode,
            screenshotOCRKeyCode: ShortcutManager.defaultScreenshotOCRShortcutKeyCode
        ) == .clipboardImageOCR
    }
}

enum ScreenshotOCRShortcut {
    static let keyCode: Int64 = HotKeyShortcutRouting.aKeyCode

    static func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        HotKeyShortcutRouting.workflowShortcut(
            keyCode: keyCode,
            flags: flags,
            clipboardImageOCRKeyCode: ShortcutManager.defaultClipboardImageOCRShortcutKeyCode,
            screenshotOCRKeyCode: ShortcutManager.defaultScreenshotOCRShortcutKeyCode
        ) == .screenshotOCR
    }
}

enum HotKeyRouterResult: Equatable {
    case voiceAction(VoiceAction)
    case workflowShortcut(HotKeyWorkflowShortcut)
    case passThrough
}

enum HotKeyRouter {
    static func route(
        keyCode: Int64,
        flags: CGEventFlags,
        dictationKeyCode: Int64?,
        agentComposeKeyCode: Int64?,
        agentDispatchKeyCode: Int64? = nil,
        clipboardImageOCRKeyCode: Int64? = ShortcutManager.defaultClipboardImageOCRShortcutKeyCode,
        screenshotOCRKeyCode: Int64? = ShortcutManager.defaultScreenshotOCRShortcutKeyCode
    ) -> HotKeyRouterResult {
        if let workflowShortcut = HotKeyShortcutRouting.workflowShortcut(
            keyCode: keyCode,
            flags: flags,
            clipboardImageOCRKeyCode: clipboardImageOCRKeyCode,
            screenshotOCRKeyCode: screenshotOCRKeyCode
        ) {
            return .workflowShortcut(workflowShortcut)
        }

        guard let action = ShortcutActionRouting.action(
            for: keyCode,
            flags: flags,
            dictationKeyCode: dictationKeyCode,
            agentComposeKeyCode: agentComposeKeyCode,
            agentDispatchKeyCode: agentDispatchKeyCode
        ) else {
            return .passThrough
        }

        return .voiceAction(action)
    }
}

enum HotKeyShortcutRouting {
    static let aKeyCode: Int64 = 0x00
    static let vKeyCode: Int64 = 0x09
    static let escapeKeyCode: Int64 = 53

    static func workflowShortcut(
        keyCode: Int64,
        flags: CGEventFlags,
        clipboardImageOCRKeyCode: Int64? = ShortcutManager.defaultClipboardImageOCRShortcutKeyCode,
        screenshotOCRKeyCode: Int64? = ShortcutManager.defaultScreenshotOCRShortcutKeyCode
    ) -> HotKeyWorkflowShortcut? {
        if keyCode == escapeKeyCode {
            return flags.intersection([
                .maskCommand,
                .maskShift,
                .maskAlternate,
                .maskControl,
            ]).isEmpty ? .cancel : nil
        }

        if let clipboardImageOCRKeyCode,
           ShortcutManager.shortcutMatches(
               clipboardImageOCRKeyCode,
               keyCode: keyCode,
               flags: flags
           ) {
            return .clipboardImageOCR
        }

        if let screenshotOCRKeyCode,
           ShortcutManager.shortcutMatches(
               screenshotOCRKeyCode,
               keyCode: keyCode,
               flags: flags
           ) {
            return .screenshotOCR
        }

        return nil
    }
}

enum HotKeyRoutingPolicy {
    static func decision(
        for event: HotKeyRoutingEvent,
        action: VoiceAction,
        dictationState: DictationState,
        activeVoiceAction: VoiceAction?,
        notesState: HotKeyNotesState
    ) -> HotKeyRoutingDecision {
        let actionName = action
        switch event {
        case .press:
            if action != .dictation, notesState.isActive, notesState.isRecording {
                HotKeyRoutingPolicyLogger.log.debug("HotKeyRoutingPolicy decision=ignore event=press action=\(actionName)")
                return .ignore
            }
            if action == .dictation, notesState.shouldCaptureHotKey {
                HotKeyRoutingPolicyLogger.log.debug("HotKeyRoutingPolicy decision=startNotesRecording event=press")
                return .startNotesRecording
            }
            let decision: HotKeyRoutingDecision = dictationState.isIdle ? .startDictation(action) : .ignore
            HotKeyRoutingPolicyLogger.log.debug(
                "HotKeyRoutingPolicy decision=\(decision) event=press action=\(actionName) " +
                "state=\(String(describing: dictationState))"
            )
            return decision

        case .release:
            if action != .dictation, notesState.isActive, notesState.isRecording {
                HotKeyRoutingPolicyLogger.log.debug("HotKeyRoutingPolicy decision=ignore event=release action=\(actionName)")
                return .ignore
            }
            if action == .dictation, notesState.isActive, notesState.isRecording {
                HotKeyRoutingPolicyLogger.log.debug("HotKeyRoutingPolicy decision=finishNotesRecording event=release")
                return .finishNotesRecording
            }
            let decision: HotKeyRoutingDecision = activeVoiceAction == action ? .releaseDictation(action) : .ignore
            HotKeyRoutingPolicyLogger.log.debug(
                "HotKeyRoutingPolicy decision=\(decision) event=release action=\(actionName) " +
                "activeVoiceAction=\(String(describing: activeVoiceAction))"
            )
            return decision

        case .shortPress:
            if action != .dictation, notesState.isActive, notesState.isRecording {
                HotKeyRoutingPolicyLogger.log.debug("HotKeyRoutingPolicy decision=ignore event=shortPress action=\(actionName)")
                return .ignore
            }
            if action == .dictation, notesState.shouldCaptureHotKey {
                let decision: HotKeyRoutingDecision = notesState.isRecording ? .finishNotesRecording : .startNotesRecording
                HotKeyRoutingPolicyLogger.log.debug(
                    "HotKeyRoutingPolicy decision=\(decision) event=shortPress action=\(actionName) " +
                    "notesRecording=\(notesState.isRecording)"
                )
                return decision
            }

            switch dictationState {
            case .recording, .waitingForFinal:
                HotKeyRoutingPolicyLogger.log.debug("HotKeyRoutingPolicy decision=releaseDictation event=shortPress action=\(actionName)")
                return .releaseDictation(action)
            case .idle:
                HotKeyRoutingPolicyLogger.log.debug("HotKeyRoutingPolicy decision=startDictation event=shortPress action=\(actionName)")
                return .startDictation(action)
            case .processing, .injecting, .failed:
                HotKeyRoutingPolicyLogger.log.debug("HotKeyRoutingPolicy decision=ignore event=shortPress action=\(actionName)")
                return .ignore
            }
        }
    }
}

enum HotKeyWorkflowRoutingPolicy {
    static func shouldStartEphemeralWorkflow(
        _ shortcut: HotKeyWorkflowShortcut,
        dictationState: DictationState
    ) -> Bool {
        let result: Bool
        switch shortcut {
        case .clipboardImageOCR:
            result = dictationState.isIdle
        case .screenshotOCR:
            result = true
        case .cancel:
            result = false
        }
        HotKeyRoutingPolicyLogger.log.debug(
            "HotKeyWorkflowRoutingPolicy shouldStartEphemeralWorkflow shortcut=\(shortcut) " +
            "state=\(String(describing: dictationState)) result=\(result)"
        )
        return result
    }

    static func shouldPresentEphemeralWorkflowHUD(
        _ shortcut: HotKeyWorkflowShortcut,
        dictationState: DictationState
    ) -> Bool {
        let result: Bool
        switch shortcut {
        case .clipboardImageOCR:
            result = dictationState.isIdle
        case .screenshotOCR:
            result = false
        case .cancel:
            result = false
        }
        HotKeyRoutingPolicyLogger.log.debug(
            "HotKeyWorkflowRoutingPolicy shouldPresentHUD shortcut=\(shortcut) " +
            "state=\(String(describing: dictationState)) result=\(result)"
        )
        return result
    }
}
