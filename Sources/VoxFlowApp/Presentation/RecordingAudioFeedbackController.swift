import Foundation

@MainActor
final class RecordingAudioFeedbackController {
    private static let logger = AppLogger.audio

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
        Self.logger.debug("RecordingAudioFeedbackController handle state=\(state)")
        switch state {
        case .recording:
            hasActiveSession = true
            if soundFeedbackEnabled() {
                Self.logger.debug("RecordingAudioFeedbackController playing start feedback")
                playSound(.start)
            }
            if muteWhileRecordingEnabled() {
                Self.logger.debug("RecordingAudioFeedbackController muting during recording")
                setMuted(true)
                mutedForSession = true
            }
        case .waitingForFinal, .processing, .injecting:
            Self.logger.debug("RecordingAudioFeedbackController restoring audio while state=\(state)")
            restoreAudioIfNeeded()
        case .idle:
            Self.logger.debug("RecordingAudioFeedbackController handle idle hasActiveSession=\(hasActiveSession)")
            restoreAudioIfNeeded()
            if hasActiveSession, soundFeedbackEnabled() {
                playSound(.complete)
            }
            hasActiveSession = false
        case .failed:
            Self.logger.debug("RecordingAudioFeedbackController handle failed hasActiveSession=\(hasActiveSession)")
            restoreAudioIfNeeded()
            if hasActiveSession, soundFeedbackEnabled() {
                playSound(.error)
            }
            hasActiveSession = false
        }
    }

    private func restoreAudioIfNeeded() {
        guard mutedForSession else { return }
        Self.logger.debug("RecordingAudioFeedbackController restoreAudioIfNeeded")
        setMuted(false)
        mutedForSession = false
    }
}
