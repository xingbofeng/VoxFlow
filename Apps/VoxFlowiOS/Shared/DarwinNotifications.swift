// DarwinNotifications.swift
// Adapted from DictusCore (commit 7264b1d8). MIT License — Copyright (c) 2026 PIVI Solutions.
// Notification prefix changed from `com.pivi.dictus.` to `com.mashangxie.ios.`.
import Foundation

/// Darwin notification names for cross-process signaling.
/// Darwin notifications carry no payload — they are ping-only.
/// After receiving a notification, read the actual data from AppGroup.defaults.
public enum DarwinNotificationName {
    /// Posted by the main app when transcription result is written to App Group.
    nonisolated(unsafe) public static let transcriptionReady = "com.mashangxie.ios.transcriptionReady" as CFString

    /// Posted by the main app when live partial transcription text is written to App Group.
    nonisolated(unsafe) public static let transcriptionPartial = "com.mashangxie.ios.transcriptionPartial" as CFString

    /// Posted by the main app when dictation status changes.
    nonisolated(unsafe) public static let statusChanged = "com.mashangxie.ios.statusChanged" as CFString

    /// Posted by keyboard extension to request the main app stop recording (keyboard -> app).
    nonisolated(unsafe) public static let stopRecording = "com.mashangxie.ios.stopRecording" as CFString

    /// Posted by keyboard extension to request the main app cancel recording (keyboard -> app).
    nonisolated(unsafe) public static let cancelRecording = "com.mashangxie.ios.cancelRecording" as CFString

    /// Posted by the main app when waveform energy data is written to App Group (app -> keyboard).
    nonisolated(unsafe) public static let waveformUpdate = "com.mashangxie.ios.waveformUpdate" as CFString

    /// Posted by keyboard extension to request the main app start recording (keyboard -> app).
    /// Used when the app is already running in background — avoids opening the app via URL.
    /// Fallback: if app doesn't respond within 500ms, keyboard opens mashangxie://dictate URL.
    nonisolated(unsafe) public static let startRecording = "com.mashangxie.ios.startRecording" as CFString

    /// Posted by the main app when AVAudioSession is interrupted (phone call, Siri, etc.)
    /// or when media services were reset by the OS. Consumers tear down dependent state.
    nonisolated(unsafe) public static let audioSessionInterrupted = "com.mashangxie.ios.audioSessionInterrupted" as CFString
}

/// Global callback registry for Darwin notifications.
/// Must be at module level because CFNotificationCenter callbacks are C function pointers
/// that cannot capture Swift context. The registry is thread-safe via NSLock.
private let _darwinCallbackLock = NSLock()
nonisolated(unsafe) private var _darwinCallbacks: [String: () -> Void] = [:]

/// C-compatible callback dispatched by CFNotificationCenter.
/// No context captured — looks up handler in the global registry by notification name.
private let _darwinCallback: CFNotificationCallback = { _, _, cfName, _, _ in
    guard let cfName = cfName else { return }
    let key = cfName.rawValue as String
    _darwinCallbackLock.lock()
    let cb = _darwinCallbacks[key]
    _darwinCallbackLock.unlock()
    cb?()
}

/// Helper to post and observe Darwin notifications.
/// Thread safety: `_darwinCallbacks` is protected by `_darwinCallbackLock`.
public enum DarwinNotificationCenter {

    public static func post(_ name: CFString) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name),
            nil, nil, true
        )
    }

    public static func addObserver(
        for name: CFString,
        callback: @escaping () -> Void
    ) {
        _darwinCallbackLock.lock()
        _darwinCallbacks[name as String] = callback
        _darwinCallbackLock.unlock()

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            _darwinCallback,
            name,
            nil,
            .deliverImmediately
        )
    }

    /// Remove a specific observer by notification name.
    /// Prefer this over removeAllObservers() for safer cleanup.
    public static func removeObserver(for name: CFString) {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            CFNotificationName(name),
            nil
        )
        _darwinCallbackLock.lock()
        _darwinCallbacks.removeValue(forKey: name as String)
        _darwinCallbackLock.unlock()
    }

    /// Remove all registered observers.
    public static func removeAllObservers() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        _darwinCallbackLock.lock()
        let names = Array(_darwinCallbacks.keys)
        _darwinCallbacks.removeAll()
        _darwinCallbackLock.unlock()

        for name in names {
            CFNotificationCenterRemoveObserver(
                center,
                nil,
                CFNotificationName(name as CFString),
                nil
            )
        }
    }
}
