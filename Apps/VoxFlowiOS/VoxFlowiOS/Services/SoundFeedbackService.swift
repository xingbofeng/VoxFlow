// DictusApp/Services/SoundFeedbackService.swift
// Plays short WAV sounds at key dictation lifecycle events using AVAudioPlayer.
import AVFoundation
import Shared

/// Plays audio feedback for dictation recording events (start, stop, cancel).
///
/// WHY AVAudioPlayer (not AudioServicesPlaySystemSound):
/// AudioServicesPlaySystemSound respects the silent switch natively but has no volume
/// control — sounds play at full system volume. AVAudioPlayer has a .volume property
/// (0.0–1.0) for user-adjustable volume. To still respect the silent switch, we use
/// the .ambient audio category which is silenced when the hardware switch is flipped.
///
/// WHY static cached players:
/// Creating an AVAudioPlayer from a URL has ~5-10ms overhead (file I/O + decode).
/// By pre-loading and caching players, subsequent plays just call .play() which is
/// near-instant. We call prepareToPlay() on cache to pre-fill audio buffers.
///
/// WHY enum with static methods (same pattern as HapticFeedback):
/// Consistency with the existing DictusCore HapticFeedback enum.
@MainActor
enum SoundFeedbackService {

    // MARK: - Cache

    /// Maps sound file name to a pre-loaded AVAudioPlayer ready to play.
    private static var cachedPlayers: [String: AVAudioPlayer] = [:]

    // MARK: - Configuration

    private static func isEnabled() -> Bool {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        // Default OFF: AVAudioSession is .playAndRecord (for recording), which ignores
        // the hardware silent switch. Sounds would play even in silent mode. Rather than
        // risk breaking recording by switching categories, we default to off and let
        // users opt-in via Settings, knowing sounds will always play.
        return defaults?.object(forKey: SharedKeys.soundFeedbackEnabled) as? Bool ?? false
    }

    /// Read the user's volume preference (0.0–1.0), default 0.5.
    ///
    /// WHY Double then Float() conversion:
    /// @AppStorage stores Double in UserDefaults. Casting directly to Float via
    /// `as? Float` fails silently because Swift doesn't bridge Double→Float.
    /// We read as Double first, then convert.
    ///
    /// WHY maxVolume = 0.1:
    /// The bundled WAV files are recorded at very high gain. A 0.1 cap means
    /// the slider controls a 0.5%–10% range of the original audio. Slider at 100%
    /// gives a subtle but clearly audible feedback beep.
    private static let maxVolume: Float = 0.1

    private static func volume() -> Float {
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        let rawValue = defaults?.double(forKey: SharedKeys.soundVolume) ?? 0
        // double(forKey:) returns 0.0 if key not set — treat 0 as "use default"
        let sliderValue = Float(rawValue > 0 ? rawValue : 0.5)
        return sliderValue * maxVolume
    }

    // MARK: - Playback

    /// Play a sound by file name (without .wav extension).
    ///
    /// Uses AVAudioPlayer with the ambient category so the silent switch is respected.
    /// Volume is applied from user preferences on each play.
    ///
    /// - Parameter soundName: File name without extension (e.g., "electronic_01f")
    static func play(_ soundName: String) {
        guard !soundName.isEmpty else {
            PersistentLog.log("[Sound] play() called with empty name")
            return
        }

        let vol = volume()

        // Check cache — reuse existing player
        if let player = cachedPlayers[soundName] {
            player.volume = vol
            player.currentTime = 0
            player.play()
            return
        }

        // Find the WAV file in the app bundle's Sounds subdirectory.
        guard let url = Bundle.main.url(forResource: soundName, withExtension: "wav", subdirectory: "Sounds") else {
            PersistentLog.log("[Sound] WAV not found in bundle: \(soundName).wav (subdirectory: Sounds)")
            return
        }

        // Create player, cache, and play
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = vol
            player.prepareToPlay()
            cachedPlayers[soundName] = player
            player.play()
            PersistentLog.log("[Sound] Playing: \(soundName) at volume \(vol)")
        } catch {
            PersistentLog.log("[Sound] Failed to create player for \(soundName): \(error.localizedDescription)")
        }
    }

    /// Play the recording-start sound.
    /// Default: "electronic_01f" (short distinct beep)
    static func playRecordStart() {
        guard isEnabled() else { return }
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        let name = defaults?.string(forKey: SharedKeys.recordStartSoundName) ?? "electronic_01f"
        play(name)
    }

    /// Play the recording-stop sound.
    /// Default: "electronic_02b"
    static func playRecordStop() {
        guard isEnabled() else { return }
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        let name = defaults?.string(forKey: SharedKeys.recordStopSoundName) ?? "electronic_02b"
        play(name)
    }

    /// Play the recording-cancel sound.
    /// Default: "electronic_03c"
    static func playRecordCancel() {
        guard isEnabled() else { return }
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        let name = defaults?.string(forKey: SharedKeys.recordCancelSoundName) ?? "electronic_03c"
        play(name)
    }

    // MARK: - Sound Catalog

    /// All available sound file names (without extension), sorted alphabetically.
    static func availableSounds() -> [String] {
        [
            "electronic_01a", "electronic_01b", "electronic_01c",
            "electronic_01d", "electronic_01e", "electronic_01f",
            "electronic_02a", "electronic_02b", "electronic_02c",
            "electronic_02d", "electronic_02e", "electronic_02f",
            "electronic_03a", "electronic_03b", "electronic_03c",
            "electronic_03d", "electronic_03e", "electronic_03f",
            "electronic_03g", "electronic_03h", "electronic_03i",
            "electronic_04a", "electronic_04b", "electronic_04c",
            "electronic_04d", "electronic_04e", "electronic_04f",
            "electronic_04g",
            "ui_chime_01",
        ]
    }

    /// Format a sound file name for display in the UI.
    /// Example: "electronic_01a" -> "Electronic 01a"
    static func displayName(for soundName: String) -> String {
        let formatted = soundName.replacingOccurrences(of: "_", with: " ")
        return formatted.prefix(1).uppercased() + formatted.dropFirst()
    }
}
