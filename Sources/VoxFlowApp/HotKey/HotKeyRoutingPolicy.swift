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

enum HotKeyWorkflowShortcut: Equatable {
    case clipboardImageOCR
    case cancel
}

enum ClipboardImageOCRShortcut {
    static let keyCode: Int64 = HotKeyShortcutRouting.vKeyCode

    static func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        HotKeyShortcutRouting.workflowShortcut(keyCode: keyCode, flags: flags) == .clipboardImageOCR
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
        agentComposeKeyCode: Int64?
    ) -> HotKeyRouterResult {
        if let workflowShortcut = HotKeyShortcutRouting.workflowShortcut(keyCode: keyCode, flags: flags) {
            return .workflowShortcut(workflowShortcut)
        }

        guard let action = ShortcutActionRouting.action(
            for: keyCode,
            dictationKeyCode: dictationKeyCode,
            agentComposeKeyCode: agentComposeKeyCode
        ) else {
            return .passThrough
        }

        guard ShortcutManager.isSupportedVoiceShortcutKeyCode(keyCode),
              ShortcutModifierRouting.isPureModifierShortcut(keyCode: keyCode, flags: flags) else {
            return .passThrough
        }

        return .voiceAction(action)
    }
}

enum HotKeyShortcutRouting {
    static let vKeyCode: Int64 = 0x09
    static let escapeKeyCode: Int64 = 53

    static func workflowShortcut(keyCode: Int64, flags: CGEventFlags) -> HotKeyWorkflowShortcut? {
        if keyCode == escapeKeyCode {
            return flags.intersection([
                .maskCommand,
                .maskShift,
                .maskAlternate,
                .maskControl,
            ]).isEmpty ? .cancel : nil
        }

        guard keyCode == vKeyCode else { return nil }

        let activeFlags = flags.intersection([
            .maskCommand,
            .maskShift,
            .maskAlternate,
            .maskControl,
        ])

        if activeFlags == [.maskCommand, .maskShift] {
            return .clipboardImageOCR
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
        switch event {
        case .press:
            if action == .dictation, notesState.shouldCaptureHotKey {
                return .startNotesRecording
            }
            return dictationState.isIdle ? .startDictation(action) : .ignore

        case .release:
            if action == .dictation, notesState.isActive, notesState.isRecording {
                return .finishNotesRecording
            }
            return activeVoiceAction == action ? .releaseDictation(action) : .ignore

        case .shortPress:
            if action == .dictation, notesState.shouldCaptureHotKey {
                return notesState.isRecording ? .finishNotesRecording : .startNotesRecording
            }

            switch dictationState {
            case .recording, .waitingForFinal:
                return .releaseDictation(action)
            case .idle:
                return .startDictation(action)
            case .processing, .injecting, .failed:
                return .ignore
            }
        }
    }
}
