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
