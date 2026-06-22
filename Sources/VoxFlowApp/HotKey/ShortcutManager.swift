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
    static let defaultClipboardImageOCRShortcutKeyCode: Int64 = encodeShortcut(
        keyCode: HotKeyShortcutRouting.vKeyCode,
        modifierMask: commandModifierMask | shiftModifierMask
    )
    static let defaultScreenshotOCRShortcutKeyCode: Int64 = encodeShortcut(
        keyCode: HotKeyShortcutRouting.aKeyCode,
        modifierMask: commandModifierMask | shiftModifierMask
    )
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
        return modifierMask != 0
    }

    static func isSupportedWorkflowShortcutKeyCode(_ shortcut: Int64) -> Bool {
        let keyCode = baseKeyCode(for: shortcut)
        let modifierMask = modifierMask(for: shortcut)
        guard modifierMask != 0,
              !supportedModifierKeyCodes.contains(keyCode),
              !isSystemEditingShortcut(shortcut) else {
            return false
        }
        return true
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

    private static func isSystemEditingShortcut(_ shortcut: Int64) -> Bool {
        let keyCode = baseKeyCode(for: shortcut)
        let modifierMask = modifierMask(for: shortcut)
        guard modifierMask == commandModifierMask else { return false }
        return [
            HotKeyShortcutRouting.aKeyCode,
            0x06, // Z
            0x07, // X
            0x08, // C
            HotKeyShortcutRouting.vKeyCode,
        ].contains(keyCode)
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
        AppLogger.general.debug("ShortcutManager initialized")
        let dictationShortcut = shortcutKeyCode(for: .dictation) ?? -1
        let agentComposeShortcut = shortcutKeyCode(for: .agentCompose) ?? -1
        AppLogger.general.debug("ShortcutManager dictationShortcut=\(dictationShortcut) agentComposeShortcut=\(agentComposeShortcut)")
    }

    // MARK: - Keys

    private enum Keys {
        static let shortcutKeyCode = "ShortcutKeyCode"
        static let longPressThreshold = "LongPressThreshold"
        static let shortPressBehavior = "ShortPressBehavior"
        static let dictationShortcutKeyCode = "DictationShortcutKeyCode"
        static let agentComposeShortcutKeyCode = "AgentComposeShortcutKeyCode"
        static let agentComposeShortcutDisabled = "AgentComposeShortcutDisabled"
        static let clipboardImageOCRShortcutKeyCode = "ClipboardImageOCRShortcutKeyCode"
        static let clipboardImageOCRShortcutDisabled = "ClipboardImageOCRShortcutDisabled"
        static let screenshotOCRShortcutKeyCode = "ScreenshotOCRShortcutKeyCode"
        static let screenshotOCRShortcutDisabled = "ScreenshotOCRShortcutDisabled"
        static let migrationDone = "ShortcutManager_MigrationDone_V2"
    }

    // MARK: - Migration

    private func migrateIfNeeded() {
        AppLogger.general.debug("ShortcutManager migration check migrationDone=\(defaults.bool(forKey: Keys.migrationDone))")
        guard !defaults.bool(forKey: Keys.migrationDone) else { return }
        if defaults.object(forKey: Keys.shortcutKeyCode) != nil {
            AppLogger.general.info("ShortcutManager migrating legacy shortcut binding")
            let existing = Int64(defaults.integer(forKey: Keys.shortcutKeyCode))
            defaults.set(existing, forKey: Keys.dictationShortcutKeyCode)
        } else {
            AppLogger.general.debug("ShortcutManager no legacy shortcut binding found")
        }
        defaults.set(true, forKey: Keys.migrationDone)
        AppLogger.general.debug("ShortcutManager migration complete")
    }

    private func normalizeConflictingBindings() {
        AppLogger.general.debug("ShortcutManager normalize conflict check start")
        guard defaults.object(forKey: Keys.agentComposeShortcutKeyCode) != nil else {
            AppLogger.general.debug("ShortcutManager agent-compose shortcut missing, skip conflict normalization")
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
            AppLogger.general.warning("ShortcutManager removed duplicate agent-compose shortcut \(agentComposeKeyCode)")
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

    func shortcutKeyCode(for workflowShortcut: HotKeyWorkflowShortcut) -> Int64? {
        switch workflowShortcut {
        case .clipboardImageOCR:
            guard !defaults.bool(forKey: Keys.clipboardImageOCRShortcutDisabled) else {
                return nil
            }
            guard defaults.object(forKey: Keys.clipboardImageOCRShortcutKeyCode) != nil else {
                return Self.defaultClipboardImageOCRShortcutKeyCode
            }
            return Int64(defaults.integer(forKey: Keys.clipboardImageOCRShortcutKeyCode))
        case .screenshotOCR:
            guard !defaults.bool(forKey: Keys.screenshotOCRShortcutDisabled) else {
                return nil
            }
            guard defaults.object(forKey: Keys.screenshotOCRShortcutKeyCode) != nil else {
                return Self.defaultScreenshotOCRShortcutKeyCode
            }
            return Int64(defaults.integer(forKey: Keys.screenshotOCRShortcutKeyCode))
        case .cancel:
            return HotKeyShortcutRouting.escapeKeyCode
        }
    }

    func setShortcutKeyCode(_ keyCode: Int64?, for action: VoiceAction) {
        AppLogger.general.info(
            "ShortcutManager setShortcutKeyCode action=\(logName(for: action)) keyCode=\(keyCode.map(String.init) ?? "nil")"
        )
        switch action {
        case .dictation:
            dictationShortcutKeyCode = keyCode
        case .agentCompose:
            agentComposeShortcutKeyCode = keyCode
        case .agentDispatch:
            break
        }
    }

    func setShortcutKeyCode(_ keyCode: Int64?, for workflowShortcut: HotKeyWorkflowShortcut) {
        AppLogger.general.info(
            "ShortcutManager setShortcutKeyCode workflowShortcut=\(logName(for: workflowShortcut)) keyCode=\(keyCode.map(String.init) ?? "nil")"
        )
        switch workflowShortcut {
        case .clipboardImageOCR:
            if let keyCode {
                defaults.set(false, forKey: Keys.clipboardImageOCRShortcutDisabled)
                defaults.set(keyCode, forKey: Keys.clipboardImageOCRShortcutKeyCode)
            } else {
                defaults.set(true, forKey: Keys.clipboardImageOCRShortcutDisabled)
                defaults.removeObject(forKey: Keys.clipboardImageOCRShortcutKeyCode)
            }
        case .screenshotOCR:
            if let keyCode {
                defaults.set(false, forKey: Keys.screenshotOCRShortcutDisabled)
                defaults.set(keyCode, forKey: Keys.screenshotOCRShortcutKeyCode)
            } else {
                defaults.set(true, forKey: Keys.screenshotOCRShortcutDisabled)
                defaults.removeObject(forKey: Keys.screenshotOCRShortcutKeyCode)
            }
        case .cancel:
            break
        }
    }

    func resetToDefaults() {
        AppLogger.general.warning("ShortcutManager resetToDefaults")
        shortcutKeyCode = Self.defaultShortcutKeyCode
        longPressThreshold = Self.defaultLongPressThreshold
        shortPressBehavior = .toggleListening
        defaults.removeObject(forKey: Keys.agentComposeShortcutKeyCode)
        defaults.removeObject(forKey: Keys.agentComposeShortcutDisabled)
        defaults.removeObject(forKey: Keys.clipboardImageOCRShortcutKeyCode)
        defaults.removeObject(forKey: Keys.clipboardImageOCRShortcutDisabled)
        defaults.removeObject(forKey: Keys.screenshotOCRShortcutKeyCode)
        defaults.removeObject(forKey: Keys.screenshotOCRShortcutDisabled)
    }

    /// Checks if two actions have conflicting (identical) key bindings.
    func hasConflict() -> Bool {
        let dictation = shortcutKeyCode(for: .dictation)
        let agentCompose = shortcutKeyCode(for: .agentCompose)
        guard let d = dictation, let a = agentCompose else { return false }
        let conflict = d == a
        if conflict {
            AppLogger.general.warning("ShortcutManager conflict detected dictation=\(d) agentCompose=\(a)")
        }
        return conflict
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
            AppLogger.general.debug("ShortcutManager shortPressBehavior set=\(newValue.rawValue)")
            defaults.set(newValue.rawValue, forKey: Keys.shortPressBehavior)
        }
    }

    private func logName(for action: VoiceAction) -> String {
        switch action {
        case .dictation:
            return "dictation"
        case .agentCompose:
            return "agentCompose"
        case .agentDispatch:
            return "agentDispatch"
        }
    }

    private func logName(for workflowShortcut: HotKeyWorkflowShortcut) -> String {
        switch workflowShortcut {
        case .clipboardImageOCR:
            return "clipboardImageOCR"
        case .screenshotOCR:
            return "screenshotOCR"
        case .cancel:
            return "cancel"
        }
    }
}
