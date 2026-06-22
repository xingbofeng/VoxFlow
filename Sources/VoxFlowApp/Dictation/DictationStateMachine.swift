import Foundation

enum DictationState: Equatable {
    case idle
    case recording
    case waitingForFinal
    case processing
    case injecting
    case failed(String)

    var isIdle: Bool {
        self == .idle
    }

    var isRecordingActive: Bool {
        self == .recording || self == .waitingForFinal
    }

    var isCancellable: Bool {
        isRecordingActive || self == .processing
    }
}

struct DictationStateMachine {
    private(set) var state: DictationState = .idle

    @discardableResult
    mutating func startRecording() -> Bool {
        transition(from: [.idle], to: .recording)
    }

    @discardableResult
    mutating func waitForFinalResult() -> Bool {
        transition(from: [.recording], to: .waitingForFinal)
    }

    @discardableResult
    mutating func startProcessing() -> Bool {
        transition(from: [.recording, .waitingForFinal], to: .processing)
    }

    @discardableResult
    mutating func startInjecting() -> Bool {
        transition(from: [.processing], to: .injecting)
    }

    mutating func finish() {
        state = .idle
    }

    mutating func fail(message: String) {
        state = .failed(message)
    }

    mutating func reset() {
        state = .idle
    }

    mutating func noteTransition(from source: DictationState, to destination: DictationState) {
        AppLogger.dictation.debug("state_transition from=\(stateLogName(source)) to=\(stateLogName(destination))")
    }

    private mutating func transition(from allowedStates: [DictationState], to nextState: DictationState) -> Bool {
        guard allowedStates.contains(state) else {
            AppLogger.dictation.warning(
                "state_transition_blocked current=\(stateLogName(state)) target=\(stateLogName(nextState))"
            )
            return false
        }
        noteTransition(from: state, to: nextState)
        state = nextState
        return true
    }

    private func stateLogName(_ state: DictationState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .recording:
            return "recording"
        case .waitingForFinal:
            return "waitingForFinal"
        case .processing:
            return "processing"
        case .injecting:
            return "injecting"
        case .failed:
            return "failed"
        }
    }
}
