// HapticFeedback.swift
// Adapted from DictusCore (commit 7264b1d8). MIT License — Copyright (c) 2026 PIVI Solutions.
// No identifier changes needed — uses AppGroup/SharedKeys which are already adapted.
// Marked @MainActor for Swift 6 concurrency (UIKit feedback generators are main-actor isolated).
#if canImport(UIKit)
import UIKit
#endif

/// Provides distinct haptic feedback for key dictation events.
///
/// Both the main app (RecordingView) and the Keyboard Extension (mic button,
/// transcription insert) use the same haptic patterns. Centralizing them in the
/// Shared target ensures consistent tactile feedback across both processes.

@MainActor
public enum HapticFeedback {

    #if canImport(UIKit) && !os(macOS)
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    #endif

    #if canImport(UIKit) && !os(macOS)
    private static var _isEnabled: Bool = {
        AppGroup.preferences.object(forKey: SharedKeys.hapticsEnabled) as? Bool ?? true
    }()

    public static func refreshEnabledState() {
        _isEnabled = AppGroup.preferences.object(forKey: SharedKeys.hapticsEnabled) as? Bool ?? true
    }

    private static func isEnabled() -> Bool {
        return _isEnabled
    }

    public static func prepareForNextTap() {
        #if canImport(UIKit) && !os(macOS)
        selectionGenerator.prepare()
        #endif
    }
    #endif

    public static func warmUp() {
        #if canImport(UIKit) && !os(macOS)
        lightGenerator.prepare()
        mediumGenerator.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
        #endif
    }

    public static func recordingStarted() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        mediumGenerator.impactOccurred()
        mediumGenerator.prepare()
        #endif
    }

    public static func recordingStopped() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        lightGenerator.impactOccurred()
        lightGenerator.prepare()
        #endif
    }

    public static func textInserted() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
        #endif
    }

    public static func actionRefused() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        notificationGenerator.notificationOccurred(.error)
        notificationGenerator.prepare()
        #endif
    }

    public static func keyTapped() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
        #endif
    }

    public static func autocorrectApplied() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        lightGenerator.impactOccurred()
        lightGenerator.prepare()
        #endif
    }

    public static func trackpadActivated() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        mediumGenerator.impactOccurred()
        mediumGenerator.prepare()
        #endif
    }

    public static func cursorMoved() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
        #endif
    }
}
