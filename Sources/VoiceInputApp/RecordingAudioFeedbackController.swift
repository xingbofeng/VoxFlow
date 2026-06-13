import Foundation

@MainActor
final class RecordingAudioFeedbackController {
    enum SoundEvent: String {
        case start
        case complete
        case error
    }

    private let soundFeedbackEnabled: () -> Bool
    private let muteWhileRecordingEnabled: () -> Bool
    private let playSound: (SoundEvent) -> Void
    private let setMuted: (Bool) -> Void
    private var hasActiveSession = false
    private var mutedForSession = false

    init(
        soundFeedbackEnabled: @escaping () -> Bool,
        muteWhileRecordingEnabled: @escaping () -> Bool,
        playSound: @escaping (SoundEvent) -> Void,
        setMuted: @escaping (Bool) -> Void
    ) {
        self.soundFeedbackEnabled = soundFeedbackEnabled
        self.muteWhileRecordingEnabled = muteWhileRecordingEnabled
        self.playSound = playSound
        self.setMuted = setMuted
    }

    func handle(_ state: DictationState) {
        switch state {
        case .recording:
            hasActiveSession = true
            if soundFeedbackEnabled() {
                playSound(.start)
            }
            if muteWhileRecordingEnabled() {
                setMuted(true)
                mutedForSession = true
            }
        case .waitingForFinal, .processing, .injecting:
            restoreAudioIfNeeded()
        case .idle:
            restoreAudioIfNeeded()
            if hasActiveSession, soundFeedbackEnabled() {
                playSound(.complete)
            }
            hasActiveSession = false
        case .failed:
            restoreAudioIfNeeded()
            if hasActiveSession, soundFeedbackEnabled() {
                playSound(.error)
            }
            hasActiveSession = false
        }
    }

    private func restoreAudioIfNeeded() {
        guard mutedForSession else { return }
        setMuted(false)
        mutedForSession = false
    }
}
