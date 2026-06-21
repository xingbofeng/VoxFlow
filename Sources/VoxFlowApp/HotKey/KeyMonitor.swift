@preconcurrency import Cocoa
import CoreGraphics

fileprivate let _kAXPrompt: String = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String

enum HotKeyTransition: Equatable {
    case pressed
    case released
    case shortPress
}

struct ActiveVoiceShortcutState {
    let keyCode: Int64
    let action: VoiceAction
    let pressedAt: ContinuousClock.Instant
}

struct VoiceShortcutKeyState {
    private let clock = ContinuousClock()
    private(set) var activeShortcut: ActiveVoiceShortcutState?

    var isPressed: Bool {
        activeShortcut != nil
    }

    mutating func transition(
        keyCode: Int64,
        action: VoiceAction,
        isModifierPressed: Bool,
        threshold: TimeInterval
    ) -> HotKeyTransition? {
        let now = clock.now

        guard let activeShortcut else {
            guard isModifierPressed else { return nil }
            self.activeShortcut = ActiveVoiceShortcutState(
                keyCode: keyCode,
                action: action,
                pressedAt: now
            )
            return .pressed
        }

        guard activeShortcut.keyCode == keyCode, activeShortcut.action == action else {
            return nil
        }

        guard !isModifierPressed else { return nil }

        self.activeShortcut = nil
        let duration = activeShortcut.pressedAt.duration(to: now)
        let elapsedSeconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
        return elapsedSeconds < threshold ? .shortPress : .released
    }

    mutating func reset() {
        activeShortcut = nil
    }
}

final class HotKeyStateMachine: @unchecked Sendable {
    private let lock = NSLock()
    private var state = VoiceShortcutKeyState()

    var isPressed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.isPressed
    }

    func transition(
        keyCode: Int64,
        action: VoiceAction,
        isModifierPressed: Bool,
        threshold: TimeInterval
    ) -> HotKeyTransition? {
        lock.lock()
        defer { lock.unlock() }
        return state.transition(
            keyCode: keyCode,
            action: action,
            isModifierPressed: isModifierPressed,
            threshold: threshold
        )
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        state.reset()
    }
}

enum ShortcutEventRouting {
    static func shouldPassThrough(
        appIsActive: Bool,
        appIsFrontmost: Bool,
        isCapturingShortcut: Bool
    ) -> Bool {
        isCapturingShortcut || appIsActive || appIsFrontmost
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
        flags: CGEventFlags = [],
        dictationKeyCode: Int64?,
        agentComposeKeyCode: Int64?,
        agentDispatchKeyCode: Int64? = nil
    ) -> VoiceAction? {
        if let dictationKeyCode,
           ShortcutManager.shortcutMatches(dictationKeyCode, keyCode: keyCode, flags: flags) {
            return .dictation
        }
        if let agentComposeKeyCode,
           ShortcutManager.shortcutMatches(agentComposeKeyCode, keyCode: keyCode, flags: flags) {
            return .agentCompose
        }
        if let agentDispatchKeyCode,
           ShortcutManager.shortcutMatches(agentDispatchKeyCode, keyCode: keyCode, flags: flags) {
            return .agentDispatch
        }
        return nil
    }
}

enum ShortcutModifierRouting {
    static func isPureModifierShortcut(keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard let expectedFlag = modifierFlag(for: keyCode) else {
            return true
        }
        let modifierFlags = CGEventFlags([
            .maskCommand,
            .maskShift,
            .maskAlternate,
            .maskControl,
        ])
        let activeModifierFlags = flags.intersection(modifierFlags)
        return activeModifierFlags.isEmpty || activeModifierFlags == expectedFlag
    }

    private static func modifierFlag(for keyCode: Int64) -> CGEventFlags? {
        switch keyCode {
        case 54, 55:
            return .maskCommand
        case 56, 60:
            return .maskShift
        case 58, 61:
            return .maskAlternate
        case 59, 62:
            return .maskControl
        default:
            return nil
        }
    }
}

/// Globally monitors and suppresses the right Command key via a CGEvent tap.
final class KeyMonitor: @unchecked Sendable {
    // MARK: - State

    private let hotKeyStateMachine = HotKeyStateMachine()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onHotKeyPress: ((VoiceAction) -> Void)?
    var onHotKeyRelease: ((VoiceAction) -> Void)?
    var onShortPress: ((VoiceAction) -> Void)?
    var onWorkflowShortcut: ((HotKeyWorkflowShortcut) -> Bool)?

    // MARK: - Lifecycle

    @MainActor
    func start() -> Bool {
        guard eventTap == nil else { return true }

        hotKeyStateMachine.reset()

        let options = [_kAXPrompt: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            return false
        }

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

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
        hotKeyStateMachine.reset()
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

        if type == .keyDown || type == .keyUp {
            return handleKeyEvent(event: event, isPressed: type == .keyDown)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }
        return handleFlagsChanged(event: event)
    }

    private func handleKeyEvent(event: CGEvent, isPressed: Bool) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let shortcutManager = ShortcutManager.shared

        let routedEvent = HotKeyRouter.route(
            keyCode: keyCode,
            flags: event.flags,
            dictationKeyCode: shortcutManager.shortcutKeyCode(for: .dictation),
            agentComposeKeyCode: shortcutManager.shortcutKeyCode(for: .agentCompose),
            agentDispatchKeyCode: shortcutManager.shortcutKeyCode(for: .agentDispatch)
        )
        switch routedEvent {
        case let .workflowShortcut(shortcut):
            guard isPressed else {
                return Unmanaged.passUnretained(event)
            }
            return handleWorkflowShortcut(event: event, shortcut: shortcut)
        case let .voiceAction(action):
            return handleVoiceShortcut(event: event, action: action, isPressed: isPressed)
        case .passThrough:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleWorkflowShortcut(event: CGEvent, shortcut: HotKeyWorkflowShortcut) -> Unmanaged<CGEvent>? {
        let shouldPassThrough = MainActor.assumeIsolated {
            if ShortcutCaptureState.shared.isCapturing {
                return true
            }
            guard shortcut != .cancel else {
                return false
            }
            let appBundleID = Bundle.main.bundleIdentifier ?? ProductBrand.bundleIdentifier
            let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            return ShortcutEventRouting.shouldPassThrough(
                appIsActive: NSApp.isActive,
                appIsFrontmost: frontmostBundleID == appBundleID,
                isCapturingShortcut: ShortcutCaptureState.shared.isCapturing
            )
        }
        if shouldPassThrough {
            return Unmanaged.passUnretained(event)
        }

        let shouldConsume = MainActor.assumeIsolated {
            onWorkflowShortcut?(shortcut) ?? false
        }
        return shouldConsume ? nil : Unmanaged.passUnretained(event)
    }

    private func handleFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let shortcutManager = ShortcutManager.shared

        let routedEvent = HotKeyRouter.route(
            keyCode: keyCode,
            flags: event.flags,
            dictationKeyCode: shortcutManager.shortcutKeyCode(for: .dictation),
            agentComposeKeyCode: shortcutManager.shortcutKeyCode(for: .agentCompose),
            agentDispatchKeyCode: shortcutManager.shortcutKeyCode(for: .agentDispatch)
        )
        guard case let .voiceAction(action) = routedEvent else {
            return Unmanaged.passUnretained(event)
        }

        return handleVoiceShortcut(
            event: event,
            action: action,
            isPressed: Self.isModifierPressed(keyCode: keyCode, flags: event.flags)
        )
    }

    private func handleVoiceShortcut(
        event: CGEvent,
        action: VoiceAction,
        isPressed: Bool
    ) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let shortcutManager = ShortcutManager.shared
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
            hotKeyStateMachine.reset()
            return Unmanaged.passUnretained(event)
        }

        guard let transition = hotKeyStateMachine.transition(
            keyCode: keyCode,
            action: action,
            isModifierPressed: isPressed,
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
