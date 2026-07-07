// SharedStatusStore.swift
// Mashangxie-specific helper wrapping shared state read/write for testability.
// Provides a single seam for the keyboard <-> app status protocol so unit tests
// can verify status transitions and transcription clearing without touching
// CFNotificationCenter directly.
import Foundation

/// Read/write helpers for the App Group shared status protocol.
///
/// The keyboard and main app communicate through a small set of App Group
/// UserDefaults keys plus Darwin notifications. This struct centralizes the
/// read/write/clear logic so the protocol is testable in isolation.
public struct SharedStatusStore {

    public init() {}

    private var defaults: UserDefaults? {
        AppGroup.defaultsIfAvailable
    }

    // MARK: - Status

    public func readStatus() -> DictationStatus? {
        guard let raw = defaults?.string(forKey: SharedKeys.dictationStatus) else {
            return nil
        }
        return DictationStatus(rawValue: raw)
    }

    public func writeStatus(_ status: DictationStatus) {
        guard let defaults else { return }
        defaults.set(status.rawValue, forKey: SharedKeys.dictationStatus)
        defaults.synchronize()
        DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
    }

    // MARK: - Transcription

    public func writeTranscription(_ text: String) {
        guard let defaults else { return }
        defaults.set(text, forKey: SharedKeys.lastTranscription)
        defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.lastTranscriptionTimestamp)
        defaults.synchronize()
    }

    public func readTranscription() -> String? {
        defaults?.string(forKey: SharedKeys.lastTranscription)
    }

    public func readTranscriptionTimestamp() -> Date? {
        let ts = defaults?.double(forKey: SharedKeys.lastTranscriptionTimestamp) ?? 0
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    public func writeLiveTranscription(_ text: String) {
        guard let defaults else { return }
        defaults.set(text, forKey: SharedKeys.liveTranscription)
        defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.liveTranscriptionTimestamp)
        defaults.synchronize()
    }

    public func readLiveTranscription() -> String? {
        defaults?.string(forKey: SharedKeys.liveTranscription)
    }

    public func readLiveTranscriptionTimestamp() -> Date? {
        let ts = defaults?.double(forKey: SharedKeys.liveTranscriptionTimestamp) ?? 0
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    public func clearLiveTranscription() {
        guard let defaults else { return }
        defaults.removeObject(forKey: SharedKeys.liveTranscription)
        defaults.removeObject(forKey: SharedKeys.liveTranscriptionTimestamp)
        defaults.synchronize()
    }

    /// Clear the consumed transcription so it cannot be inserted twice.
    /// Called by the keyboard after `textDocumentProxy.insertText` succeeds.
    public func clearConsumedTranscription() {
        guard let defaults else { return }
        defaults.removeObject(forKey: SharedKeys.lastTranscription)
        defaults.removeObject(forKey: SharedKeys.lastTranscriptionTimestamp)
        defaults.synchronize()
    }

    // MARK: - Error

    public func writeError(_ message: String) {
        guard let defaults else { return }
        defaults.set(message, forKey: SharedKeys.lastError)
        defaults.synchronize()
    }

    public func readError() -> String? {
        defaults?.string(forKey: SharedKeys.lastError)
    }

    public func clearError() {
        guard let defaults else { return }
        defaults.removeObject(forKey: SharedKeys.lastError)
        defaults.synchronize()
    }

    // MARK: - Stop / Cancel requests (keyboard -> app)

    public func setStopRequested(_ value: Bool) {
        guard let defaults else { return }
        defaults.set(value, forKey: SharedKeys.stopRequested)
        defaults.synchronize()
    }

    public func consumeStopRequested() -> Bool {
        guard let defaults else { return false }
        let v = defaults.bool(forKey: SharedKeys.stopRequested)
        if v {
            defaults.set(false, forKey: SharedKeys.stopRequested)
            defaults.synchronize()
        }
        return v
    }

    public func setCancelRequested(_ value: Bool) {
        guard let defaults else { return }
        defaults.set(value, forKey: SharedKeys.cancelRequested)
        defaults.synchronize()
    }

    public func consumeCancelRequested() -> Bool {
        guard let defaults else { return false }
        let v = defaults.bool(forKey: SharedKeys.cancelRequested)
        if v {
            defaults.set(false, forKey: SharedKeys.cancelRequested)
            defaults.synchronize()
        }
        return v
    }

    // MARK: - Heartbeat

    public func writeHeartbeat(_ date: Date = Date()) {
        guard let defaults else { return }
        defaults.set(date.timeIntervalSince1970, forKey: SharedKeys.recordingHeartbeat)
        defaults.synchronize()
    }

    public func readHeartbeat() -> Date? {
        let ts = defaults?.double(forKey: SharedKeys.recordingHeartbeat) ?? 0
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    // MARK: - Cold start

    public func setColdStartActive(_ value: Bool) {
        guard let defaults else { return }
        defaults.set(value, forKey: SharedKeys.coldStartActive)
        defaults.synchronize()
    }

    public func consumeColdStartActive() -> Bool {
        guard let defaults else { return false }
        let v = defaults.bool(forKey: SharedKeys.coldStartActive)
        if v {
            defaults.set(false, forKey: SharedKeys.coldStartActive)
            defaults.synchronize()
        }
        return v
    }
}
