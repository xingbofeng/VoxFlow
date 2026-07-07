// SharedKeys.swift
// Adapted from DictusCore (commit 7264b1d8). MIT License — Copyright (c) 2026 PIVI Solutions.
// Key prefix changed from `dictus.` to `mashangxie.`. Model-management keys removed
// (Phase 1 does not use Dictus WhisperKit/Parakeet/model provider — see Section 6).
import Foundation

/// Centralized UserDefaults keys for App Group shared storage.
/// Using an enum with static properties prevents typo-based bugs.
public enum SharedKeys {
    // MARK: - Core dictation state
    public static let dictationStatus = "mashangxie.dictationStatus"
    public static let lastTranscription = "mashangxie.lastTranscription"
    public static let lastTranscriptionTimestamp = "mashangxie.lastTranscriptionTimestamp"
    public static let liveTranscription = "mashangxie.liveTranscription"
    public static let liveTranscriptionTimestamp = "mashangxie.liveTranscriptionTimestamp"
    public static let lastError = "mashangxie.lastError"

    // MARK: - Keyboard-App cross-process contracts
    /// Current keyboard layout type stored as String ("azerty" or "qwerty")
    public static let keyboardLayout = "mashangxie.keyboardLayout"
    /// JSON-encoded [Float] waveform energy data written by app during recording
    public static let waveformEnergy = "mashangxie.waveformEnergy"
    /// Bool flag set by keyboard to request recording stop
    public static let stopRequested = "mashangxie.stopRequested"
    /// Bool flag set by keyboard to request recording cancellation
    public static let cancelRequested = "mashangxie.cancelRequested"
    /// Double: elapsed recording seconds, updated at ~5Hz during recording
    public static let recordingElapsedSeconds = "mashangxie.recordingElapsedSeconds"

    /// Default keyboard layer: "letters" or "numbers".
    public static let defaultKeyboardLayer = "mashangxie.defaultKeyboardLayer"

    // MARK: - User preferences
    /// ASR provider id string. Default "apple" (Apple Speech). See task 7.3.
    public static let provider = "mashangxie.provider"
    /// Dictus-compatible active model key. In Mashangxie this points to the ASR provider id.
    public static let activeModel = provider
    /// Language code for transcription, default "zh"
    public static let language = "mashangxie.language"
    /// Whether haptic feedback is enabled, default true
    public static let hapticsEnabled = "mashangxie.hapticsEnabled"
    /// Whether the user has completed onboarding, default false
    public static let hasCompletedOnboarding = "mashangxie.hasCompletedOnboarding"
    /// Current onboarding step index. Persisted so the user resumes at the right
    /// step even after iOS TCC-triggered terminations (e.g., when "Allow Full
    /// Access" is toggled during keyboard setup).
    public static let onboardingCurrentPage = "mashangxie.onboardingCurrentPage"
    /// Whether autocorrect is enabled, default true
    public static let autocorrectEnabled = "mashangxie.autocorrectEnabled"
    /// Whether Live Activity / Dynamic Island recording state is enabled, default true
    public static let liveActivityEnabled = "mashangxie.liveActivityEnabled"
    /// Bool: when true, logs autocorrect decisions with the typed word + correction
    /// to the App Group persistent log for debugging. CONTAINS USER TEXT — never
    /// active in Release builds (code is compile-time excluded via #if DEBUG).
    public static let autocorrectDebugLogging = "mashangxie.autocorrectDebugLogging"

    // MARK: - Audio heartbeat
    /// Double (timeIntervalSince1970): written directly from the audio thread at ~1Hz
    /// during active recording. The keyboard watchdog reads this as a fallback
    /// when Darwin waveform notifications don't arrive (iOS main thread throttling
    /// in background). If the heartbeat is fresh (< 5s), the app is still recording.
    public static let recordingHeartbeat = "mashangxie.recordingHeartbeat"

    // MARK: - Cold start detection
    /// Bool flag: true when the app was opened from the keyboard for cold start dictation.
    /// Set by handleIncomingURL when source=keyboard query parameter is present.
    /// Cleared when the app enters background.
    public static let coldStartActive = "mashangxie.coldStartActive"
    /// String: URL scheme of the source app (e.g., "weixin") or "unknown".
    /// Used by auto-return logic to navigate back to the correct app after dictation.
    public static let sourceAppScheme = "mashangxie.sourceAppScheme"

    // MARK: - Sound Feedback
    /// Whether sound feedback is enabled for recording events, default true
    public static let soundFeedbackEnabled = "mashangxie.soundFeedbackEnabled"
    /// Name of the WAV file (without extension) to play when recording starts
    public static let recordStartSoundName = "mashangxie.recordStartSoundName"
    /// Name of the WAV file (without extension) to play when recording stops
    public static let recordStopSoundName = "mashangxie.recordStopSoundName"
    /// Name of the WAV file (without extension) to play when recording is cancelled
    public static let recordCancelSoundName = "mashangxie.recordCancelSoundName"
    /// Sound volume from 0.0 to 1.0, default 0.5
    public static let soundVolume = "mashangxie.soundVolume"

    // MARK: - ClipboardBridge pending state (keyboard-local only, NOT shared via AppGroup)
    //
    // These keys are written to the keyboard's standard UserDefaults (not AppGroup)
    // because ClipboardBridge is specifically the fallback when AppGroup is not
    // available. The keyboard reads its own local state on the next appearance
    // after returning from the main app.
    //
    // Lifecycle:
    // 1. Keyboard mic tapped in Clipboard mode -> set pendingClipboardLaunched=true
    // 2. User returns from main app with text on pasteboard -> set pendingClipboardText
    // 3. User taps preview -> insert text, clear all pending keys
    // 4. User taps X -> clear all pending keys (no insertion, no pasteboard clear)
    /// Bool: true after the keyboard opened the clipboard-start deep link and is
    /// waiting for the user to return with pasteboard content.
    public static let pendingClipboardLaunched = "mashangxie.pendingClipboardLaunched"
    /// String: full clipboard text captured during the pending return. Stored
    /// locally so the keyboard can insert it on preview tap without re-reading
    /// the pasteboard.
    public static let pendingClipboardText = "mashangxie.pendingClipboardText"
    /// String: optional ClipboardReadFailureReason raw value. Stored locally so
    /// a killed/restarted keyboard extension does not restore an exhausted
    /// pasteboard read as an infinite loading state.
    public static let pendingClipboardFailureReason = "mashangxie.pendingClipboardFailureReason"
    /// Double: timestamp when pendingClipboardLaunched was set, for staleness checks.
    public static let pendingClipboardTimestamp = "mashangxie.pendingClipboardTimestamp"
}
