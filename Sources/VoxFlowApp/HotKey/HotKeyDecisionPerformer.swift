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
}
