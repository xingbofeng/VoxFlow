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
    case palette
    case clipboardImageOCR
    case screenshotOCR
    case selectionAction
    case selectionTranslate
    case selectionSummarize
    case selectionAgent
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
        paletteKeyCode: Int64? = ShortcutManager.defaultPaletteShortcutKeyCode,
        clipboardImageOCRKeyCode: Int64? = ShortcutManager.defaultClipboardImageOCRShortcutKeyCode,
        screenshotOCRKeyCode: Int64? = ShortcutManager.defaultScreenshotOCRShortcutKeyCode,
        selectionActionKeyCode: Int64? = ShortcutManager.defaultSelectionActionShortcutKeyCode,
        selectionTranslateKeyCode: Int64? = ShortcutManager.defaultSelectionTranslateShortcutKeyCode,
        selectionSummarizeKeyCode: Int64? = ShortcutManager.defaultSelectionSummarizeShortcutKeyCode,
        selectionAgentKeyCode: Int64? = ShortcutManager.defaultSelectionAgentShortcutKeyCode
    ) -> HotKeyRouterResult {
        if let workflowShortcut = HotKeyShortcutRouting.workflowShortcut(
            keyCode: keyCode,
            flags: flags,
            paletteKeyCode: paletteKeyCode,
            clipboardImageOCRKeyCode: clipboardImageOCRKeyCode,
            screenshotOCRKeyCode: screenshotOCRKeyCode,
            selectionActionKeyCode: selectionActionKeyCode,
            selectionTranslateKeyCode: selectionTranslateKeyCode,
            selectionSummarizeKeyCode: selectionSummarizeKeyCode,
            selectionAgentKeyCode: selectionAgentKeyCode
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
    static let dKeyCode: Int64 = 0x02
    static let fKeyCode: Int64 = 0x03
    static let vKeyCode: Int64 = 0x09
    static let lKeyCode: Int64 = 0x25
    static let jKeyCode: Int64 = 0x26
    static let kKeyCode: Int64 = 0x28
    static let spaceKeyCode: Int64 = 0x31
    static let escapeKeyCode: Int64 = 53

    static func workflowShortcut(
        keyCode: Int64,
        flags: CGEventFlags,
        paletteKeyCode: Int64? = ShortcutManager.defaultPaletteShortcutKeyCode,
        clipboardImageOCRKeyCode: Int64? = ShortcutManager.defaultClipboardImageOCRShortcutKeyCode,
        screenshotOCRKeyCode: Int64? = ShortcutManager.defaultScreenshotOCRShortcutKeyCode,
        selectionActionKeyCode: Int64? = ShortcutManager.defaultSelectionActionShortcutKeyCode,
        selectionTranslateKeyCode: Int64? = ShortcutManager.defaultSelectionTranslateShortcutKeyCode,
        selectionSummarizeKeyCode: Int64? = ShortcutManager.defaultSelectionSummarizeShortcutKeyCode,
        selectionAgentKeyCode: Int64? = ShortcutManager.defaultSelectionAgentShortcutKeyCode
    ) -> HotKeyWorkflowShortcut? {
        if keyCode == escapeKeyCode {
            return flags.intersection([
                .maskCommand,
                .maskShift,
                .maskAlternate,
                .maskControl,
            ]).isEmpty ? .cancel : nil
        }

        if let paletteKeyCode,
           ShortcutManager.shortcutMatches(
               paletteKeyCode,
               keyCode: keyCode,
               flags: flags
           ) {
            return .palette
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

        if let selectionActionKeyCode,
           ShortcutManager.shortcutMatches(
               selectionActionKeyCode,
               keyCode: keyCode,
               flags: flags
           ) {
            return .selectionAction
        }

        if let selectionTranslateKeyCode,
           ShortcutManager.shortcutMatches(
               selectionTranslateKeyCode,
               keyCode: keyCode,
               flags: flags
           ) {
            return .selectionTranslate
        }

        if let selectionSummarizeKeyCode,
           ShortcutManager.shortcutMatches(
               selectionSummarizeKeyCode,
               keyCode: keyCode,
               flags: flags
           ) {
            return .selectionSummarize
        }

        if let selectionAgentKeyCode,
           ShortcutManager.shortcutMatches(
               selectionAgentKeyCode,
               keyCode: keyCode,
               flags: flags
           ) {
            return .selectionAgent
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
        case .palette:
            result = true
        case .clipboardImageOCR:
            result = dictationState.isIdle
        case .screenshotOCR:
            result = true
        case .selectionAction, .selectionTranslate, .selectionSummarize, .selectionAgent:
            result = dictationState.isIdle
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
        case .palette:
            result = false
        case .clipboardImageOCR:
            result = dictationState.isIdle
        case .screenshotOCR:
            result = false
        case .selectionAction, .selectionTranslate, .selectionSummarize, .selectionAgent:
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
