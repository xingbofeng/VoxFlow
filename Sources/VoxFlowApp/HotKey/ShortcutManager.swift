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

    static func isSupportedVoiceShortcutKeyCode(_ keyCode: Int64) -> Bool {
        supportedModifierKeyCodes.contains(keyCode)
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
        }
    }

    func setShortcutKeyCode(_ keyCode: Int64?, for action: VoiceAction) {
        switch action {
        case .dictation:
            dictationShortcutKeyCode = keyCode
        case .agentCompose:
            agentComposeShortcutKeyCode = keyCode
        }
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
