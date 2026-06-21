import CoreGraphics
import Foundation

enum ShortPressBehavior: String, CaseIterable, Codable, Equatable {
    case toggleListening
    case none
}

/// Manages keyboard shortcut preferences stored in UserDefaults.
final class ShortcutManager: @unchecked Sendable {
    static let shared = ShortcutManager()
    static let defaultShortcutKeyCode: Int64 = 54
    static let defaultAgentComposeShortcutKeyCode: Int64 = 61
    static let defaultLongPressThreshold: TimeInterval = 0.5
    static let supportedModifierKeyCodes: Set<Int64> = [54, 55, 56, 60, 58, 61, 59, 62]
    private static let modifierEncodingShift: Int64 = 16
    private static let shortcutKeyCodeMask: Int64 = 0xFFFF
    static let commandModifierMask: Int64 = 1 << 0
    static let shiftModifierMask: Int64 = 1 << 1
    static let optionModifierMask: Int64 = 1 << 2
    static let controlModifierMask: Int64 = 1 << 3
    static let supportedModifierMask: Int64 = commandModifierMask
        | shiftModifierMask
        | optionModifierMask
        | controlModifierMask

    static func isSupportedVoiceShortcutKeyCode(_ shortcut: Int64) -> Bool {
        let keyCode = baseKeyCode(for: shortcut)
        let modifierMask = modifierMask(for: shortcut)
        if supportedModifierKeyCodes.contains(keyCode) {
            return modifierMask == 0
        }
        return modifierMask != 0 && !isReservedWorkflowShortcut(shortcut)
    }

    static func encodeShortcut(keyCode: Int64, flags: CGEventFlags) -> Int64 {
        encodeShortcut(keyCode: keyCode, modifierMask: modifierMask(from: flags))
    }

    static func encodeShortcut(keyCode: Int64, modifierMask: Int64) -> Int64 {
        let normalizedMask = modifierMask & supportedModifierMask
        if supportedModifierKeyCodes.contains(keyCode),
           normalizedMask == modifierMaskForPureModifierKeyCode(keyCode) {
            return keyCode
        }
        guard normalizedMask != 0 else {
            return keyCode
        }
        return (normalizedMask << modifierEncodingShift) | (keyCode & shortcutKeyCodeMask)
    }

    static func baseKeyCode(for shortcut: Int64) -> Int64 {
        shortcut & shortcutKeyCodeMask
    }

    static func modifierMask(for shortcut: Int64) -> Int64 {
        (shortcut >> modifierEncodingShift) & supportedModifierMask
    }

    static func modifierMask(
        command: Bool,
        shift: Bool,
        option: Bool,
        control: Bool
    ) -> Int64 {
        var mask: Int64 = 0
        if command { mask |= commandModifierMask }
        if shift { mask |= shiftModifierMask }
        if option { mask |= optionModifierMask }
        if control { mask |= controlModifierMask }
        return mask
    }

    static func modifierMask(from flags: CGEventFlags) -> Int64 {
        modifierMask(
            command: flags.contains(.maskCommand),
            shift: flags.contains(.maskShift),
            option: flags.contains(.maskAlternate),
            control: flags.contains(.maskControl)
        )
    }

    static func flags(fromModifierMask mask: Int64) -> CGEventFlags {
        var flags = CGEventFlags()
        if mask & commandModifierMask != 0 { flags.insert(.maskCommand) }
        if mask & shiftModifierMask != 0 { flags.insert(.maskShift) }
        if mask & optionModifierMask != 0 { flags.insert(.maskAlternate) }
        if mask & controlModifierMask != 0 { flags.insert(.maskControl) }
        return flags
    }

    static func shortcutMatches(_ shortcut: Int64, keyCode: Int64, flags: CGEventFlags) -> Bool {
        let baseKeyCode = baseKeyCode(for: shortcut)
        guard baseKeyCode == keyCode else { return false }
        let encodedModifierMask = modifierMask(for: shortcut)
        if encodedModifierMask == 0 {
            guard supportedModifierKeyCodes.contains(keyCode) else {
                return modifierMask(from: flags) == 0
            }
            return ShortcutModifierRouting.isPureModifierShortcut(keyCode: keyCode, flags: flags)
        }
        return modifierMask(from: flags) == encodedModifierMask
    }

    static func isReservedWorkflowShortcut(_ shortcut: Int64) -> Bool {
        let modifierMask = modifierMask(for: shortcut)
        guard modifierMask != 0 else { return false }

        return HotKeyShortcutRouting.workflowShortcut(
            keyCode: baseKeyCode(for: shortcut),
            flags: flags(fromModifierMask: modifierMask)
        ) != nil
    }

    private static func modifierMaskForPureModifierKeyCode(_ keyCode: Int64) -> Int64 {
        switch keyCode {
        case 54, 55:
            return commandModifierMask
        case 56, 60:
            return shiftModifierMask
        case 58, 61:
            return optionModifierMask
        case 59, 62:
            return controlModifierMask
        default:
            return 0
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateIfNeeded()
        normalizeConflictingBindings()
    }

    // MARK: - Keys

    private enum Keys {
        static let shortcutKeyCode = "ShortcutKeyCode"
        static let longPressThreshold = "LongPressThreshold"
        static let shortPressBehavior = "ShortPressBehavior"
        static let dictationShortcutKeyCode = "DictationShortcutKeyCode"
        static let agentComposeShortcutKeyCode = "AgentComposeShortcutKeyCode"
        static let agentComposeShortcutDisabled = "AgentComposeShortcutDisabled"
        static let migrationDone = "ShortcutManager_MigrationDone_V2"
    }

    // MARK: - Migration

    private func migrateIfNeeded() {
        guard !defaults.bool(forKey: Keys.migrationDone) else { return }
        if defaults.object(forKey: Keys.shortcutKeyCode) != nil {
            let existing = Int64(defaults.integer(forKey: Keys.shortcutKeyCode))
            defaults.set(existing, forKey: Keys.dictationShortcutKeyCode)
        }
        defaults.set(true, forKey: Keys.migrationDone)
    }

    private func normalizeConflictingBindings() {
        guard defaults.object(forKey: Keys.agentComposeShortcutKeyCode) != nil else {
            return
        }

        let dictationKeyCode: Int64
        if defaults.object(forKey: Keys.dictationShortcutKeyCode) != nil {
            dictationKeyCode = Int64(defaults.integer(forKey: Keys.dictationShortcutKeyCode))
        } else {
            dictationKeyCode = Self.defaultShortcutKeyCode
        }

        let agentComposeKeyCode = Int64(defaults.integer(forKey: Keys.agentComposeShortcutKeyCode))
        if agentComposeKeyCode == dictationKeyCode {
            defaults.removeObject(forKey: Keys.agentComposeShortcutKeyCode)
        }
    }

    // MARK: - Shortcut Key Code (Legacy)

    /// The keyboard key code for the hotkey. Default is 54 (Right Command).
    var shortcutKeyCode: Int64 {
        get { dictationShortcutKeyCode ?? Self.defaultShortcutKeyCode }
        set {
            defaults.set(newValue, forKey: Keys.shortcutKeyCode)
            defaults.set(newValue, forKey: Keys.dictationShortcutKeyCode)
        }
    }

    // MARK: - Per-Action Bindings

    var dictationShortcutKeyCode: Int64? {
        get {
            guard defaults.object(forKey: Keys.dictationShortcutKeyCode) != nil else {
                return nil
            }
            return Int64(defaults.integer(forKey: Keys.dictationShortcutKeyCode))
        }
        set {
            if let value = newValue {
                defaults.set(value, forKey: Keys.dictationShortcutKeyCode)
                defaults.set(value, forKey: Keys.shortcutKeyCode)
            } else {
                defaults.removeObject(forKey: Keys.dictationShortcutKeyCode)
            }
        }
    }

    var agentComposeShortcutKeyCode: Int64? {
        get {
            guard defaults.object(forKey: Keys.agentComposeShortcutKeyCode) != nil else {
                return nil
            }
            return Int64(defaults.integer(forKey: Keys.agentComposeShortcutKeyCode))
        }
        set {
            if let value = newValue {
                defaults.set(false, forKey: Keys.agentComposeShortcutDisabled)
                defaults.set(value, forKey: Keys.agentComposeShortcutKeyCode)
            } else {
                defaults.set(true, forKey: Keys.agentComposeShortcutDisabled)
                defaults.removeObject(forKey: Keys.agentComposeShortcutKeyCode)
            }
        }
    }

    func shortcutKeyCode(for action: VoiceAction) -> Int64? {
        switch action {
        case .dictation:
            return dictationShortcutKeyCode ?? Self.defaultShortcutKeyCode
        case .agentCompose:
            guard !defaults.bool(forKey: Keys.agentComposeShortcutDisabled) else {
                return nil
            }
            if let agentComposeShortcutKeyCode {
                return agentComposeShortcutKeyCode
            }
            let effectiveDictationKeyCode = dictationShortcutKeyCode ?? Self.defaultShortcutKeyCode
            return effectiveDictationKeyCode == Self.defaultAgentComposeShortcutKeyCode
                ? nil
                : Self.defaultAgentComposeShortcutKeyCode
        case .agentDispatch:
            return nil
        }
    }

    func setShortcutKeyCode(_ keyCode: Int64?, for action: VoiceAction) {
        switch action {
        case .dictation:
            dictationShortcutKeyCode = keyCode
        case .agentCompose:
            agentComposeShortcutKeyCode = keyCode
        case .agentDispatch:
            break
        }
    }

    func resetToDefaults() {
        shortcutKeyCode = Self.defaultShortcutKeyCode
        longPressThreshold = Self.defaultLongPressThreshold
        shortPressBehavior = .toggleListening
        defaults.removeObject(forKey: Keys.agentComposeShortcutKeyCode)
        defaults.removeObject(forKey: Keys.agentComposeShortcutDisabled)
    }

    /// Checks if two actions have conflicting (identical) key bindings.
    func hasConflict() -> Bool {
        let dictation = shortcutKeyCode(for: .dictation)
        let agentCompose = shortcutKeyCode(for: .agentCompose)
        guard let d = dictation, let a = agentCompose else { return false }
        return d == a
    }

    /// Returns all action-keycode pairs that conflict.
    func conflictingActions() -> [(VoiceAction, VoiceAction)] {
        var conflicts: [(VoiceAction, VoiceAction)] = []
        let actions = VoiceAction.allCases
        for i in 0..<actions.count {
            for j in (i + 1)..<actions.count {
                let a = actions[i]
                let b = actions[j]
                if let ka = shortcutKeyCode(for: a),
                   let kb = shortcutKeyCode(for: b),
                   ka == kb {
                    conflicts.append((a, b))
                }
            }
        }
        return conflicts
    }

    // MARK: - Long Press Threshold

    /// Duration in seconds that distinguishes a long press from a short press. Default is 0.5.
    var longPressThreshold: TimeInterval {
        get {
            guard defaults.object(forKey: Keys.longPressThreshold) != nil else {
                return Self.defaultLongPressThreshold
            }
            return defaults.double(forKey: Keys.longPressThreshold)
        }
        set {
            defaults.set(newValue, forKey: Keys.longPressThreshold)
        }
    }

    // MARK: - Short Press Behavior

    /// Action to perform on a short press. Default is `.toggleListening`.
    var shortPressBehavior: ShortPressBehavior {
        get {
            guard let raw = defaults.string(forKey: Keys.shortPressBehavior) else {
                return .toggleListening
            }
            return ShortPressBehavior(rawValue: raw) ?? .toggleListening
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.shortPressBehavior)
        }
    }
}
