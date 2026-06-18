@preconcurrency import Cocoa
import CoreGraphics

fileprivate let _kAXPrompt: String = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String

enum HotKeyTransition: Equatable {
    case pressed
    case released
    case shortPress
}

struct RightCommandKeyState {
    private(set) var isPressed = false
    private var pressTimestamp: Date?

    mutating func transition(isModifierPressed: Bool, threshold: TimeInterval) -> HotKeyTransition? {
        let now = Date()

        if isModifierPressed, !isPressed {
            isPressed = true
            pressTimestamp = now
            return .pressed
        }
        if !isModifierPressed, isPressed {
            isPressed = false
            let duration = pressTimestamp.map { now.timeIntervalSince($0) } ?? 0
            pressTimestamp = nil
            return duration < threshold ? .shortPress : .released
        }
        return nil
    }

    mutating func reset() {
        isPressed = false
        pressTimestamp = nil
    }
}

enum ShortcutEventRouting {
    static func shouldPassThrough(
        appIsActive: Bool,
        appIsFrontmost: Bool,
        isCapturingShortcut: Bool
    ) -> Bool {
        appIsActive || appIsFrontmost
    }
}

@MainActor
final class ShortcutCaptureState {
    static let shared = ShortcutCaptureState()
    var isCapturing = false

    private init() {}
}

enum ShortcutActionRouting {
    static func action(
        for keyCode: Int64,
        dictationKeyCode: Int64?,
        agentComposeKeyCode: Int64?
    ) -> VoiceAction? {
        if keyCode == dictationKeyCode {
            return .dictation
        }
        if keyCode == agentComposeKeyCode {
            return .agentCompose
        }
        return nil
    }
}

/// Globally monitors and suppresses the right Command key via a CGEvent tap.
final class KeyMonitor: @unchecked Sendable {
    // MARK: - State

    private var rightCommandState: RightCommandKeyState!
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onHotKeyPress: ((VoiceAction) -> Void)?
    var onHotKeyRelease: ((VoiceAction) -> Void)?
    var onShortPress: ((VoiceAction) -> Void)?

    // MARK: - Lifecycle

    @MainActor
    func start() -> Bool {
        guard eventTap == nil else { return true }

        rightCommandState = RightCommandKeyState()

        let options = [_kAXPrompt: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            return false
        }

        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        rightCommandState.reset()
    }

    // MARK: - Event Handling

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }
        return handleFlagsChanged(event: event)
    }

    private func handleFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let shortcutManager = ShortcutManager.shared

        guard let action = ShortcutActionRouting.action(
            for: keyCode,
            dictationKeyCode: shortcutManager.shortcutKeyCode(for: .dictation),
            agentComposeKeyCode: shortcutManager.shortcutKeyCode(for: .agentCompose)
        ) else {
            return Unmanaged.passUnretained(event)
        }

        let passThrough = MainActor.assumeIsolated {
            let appBundleID = Bundle.main.bundleIdentifier ?? ProductBrand.bundleIdentifier
            let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            return ShortcutEventRouting.shouldPassThrough(
                appIsActive: NSApp.isActive,
                appIsFrontmost: frontmostBundleID == appBundleID,
                isCapturingShortcut: ShortcutCaptureState.shared.isCapturing
            )
        }
        if passThrough {
            rightCommandState.reset()
            return Unmanaged.passUnretained(event)
        }

        guard let transition = rightCommandState.transition(
            isModifierPressed: Self.isModifierPressed(keyCode: keyCode, flags: event.flags),
            threshold: shortcutManager.longPressThreshold
        ) else {
            return nil
        }

        switch transition {
        case .pressed:
            let handler = onHotKeyPress
            DispatchQueue.main.async {
                handler?(action)
            }
        case .released:
            let handler = onHotKeyRelease
            DispatchQueue.main.async {
                handler?(action)
            }
        case .shortPress:
            let handler = onShortPress
            DispatchQueue.main.async {
                handler?(action)
            }
        }

        // Suppress the shortcut key event to prevent system-side effects.
        return nil
    }

    private static func isModifierPressed(keyCode: Int64, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case 54, 55:
            return flags.contains(.maskCommand)
        case 56, 60:
            return flags.contains(.maskShift)
        case 58, 61:
            return flags.contains(.maskAlternate)
        case 59, 62:
            return flags.contains(.maskControl)
        default:
            return false
        }
    }
}
