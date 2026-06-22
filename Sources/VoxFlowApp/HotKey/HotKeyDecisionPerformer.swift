@MainActor
final class HotKeyDecisionPerformer {
    typealias NotesAction = () -> Void
    typealias DictationAction = (VoiceAction) -> Void

    private let startNotesRecording: NotesAction
    private let finishNotesRecording: NotesAction
    private let startDictation: DictationAction
    private let releaseDictation: DictationAction

    init(
        startNotesRecording: @escaping NotesAction,
        finishNotesRecording: @escaping NotesAction,
        startDictation: @escaping DictationAction,
        releaseDictation: @escaping DictationAction
    ) {
        self.startNotesRecording = startNotesRecording
        self.finishNotesRecording = finishNotesRecording
        self.startDictation = startDictation
        self.releaseDictation = releaseDictation
    }

    func perform(_ decision: HotKeyRoutingDecision) {
        AppLogger.general.debug("hotkey_decision_performer decision=\(decisionLogName(decision))")
        switch decision {
        case .ignore:
            break
        case .startNotesRecording:
            startNotesRecording()
        case .finishNotesRecording:
            finishNotesRecording()
        case .startDictation(let action):
            startDictation(action)
        case .releaseDictation(let action):
            releaseDictation(action)
        }
    }

    private func decisionLogName(_ decision: HotKeyRoutingDecision) -> String {
        switch decision {
        case .ignore:
            return "ignore"
        case .startNotesRecording:
            return "startNotesRecording"
        case .finishNotesRecording:
            return "finishNotesRecording"
        case .startDictation(let action):
            return "startDictation(\(actionLogName(action)))"
        case .releaseDictation(let action):
            return "releaseDictation(\(actionLogName(action)))"
        }
    }

    private func actionLogName(_ action: VoiceAction) -> String {
        switch action {
        case .dictation:
            return "dictation"
        case .agentCompose:
            return "agentCompose"
        case .agentDispatch:
            return "agentDispatch"
        }
    }
}
