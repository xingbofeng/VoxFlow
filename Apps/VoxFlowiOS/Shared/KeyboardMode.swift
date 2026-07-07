// DictusCore/Sources/DictusCore/KeyboardMode.swift
// Default keyboard layer enum — replaces the old 3-mode KeyboardMode system.
import Foundation

/// Which keyboard layer to show when the keyboard first appears.
///
/// WHY only two cases:
/// The old system had 3 modes (micro, emojiMicro, full) with separate layouts.
/// This caused recurring layout bugs and code duplication. Now there's always
/// a full keyboard — this enum just controls which layer opens first:
/// letters (AZERTY/QWERTY) or numbers (123/symbols).
public enum DefaultKeyboardLayer: String, CaseIterable, Codable {
    case letters
    case numbers

    /// Reads the active default layer from App Group UserDefaults.
    /// Defaults to `.letters` if nothing is stored.
    public static var active: DefaultKeyboardLayer {
        guard let raw = AppGroup.preferences.string(forKey: SharedKeys.defaultKeyboardLayer),
              let layer = DefaultKeyboardLayer(rawValue: raw) else {
            return .letters
        }
        return layer
    }

    /// User-facing display name for settings and onboarding UI.
    /// Matches the labels on the keyboard's layer-switch key (ABC / 123).
    public var displayName: String {
        switch self {
        case .letters: return "ABC"
        case .numbers: return "123"
        }
    }

    /// Migrates from the old KeyboardMode system to DefaultKeyboardLayer.
    ///
    /// WHY migration:
    /// Existing users may have "micro", "emojiMicro", or "full" stored.
    /// We map them to the new system and clean up the old key.
    ///
    /// Mapping:
    /// - "micro" → "numbers" (dictation-first users wanted minimal typing)
    /// - "full" → "letters" (same behavior as before)
    /// - "emojiMicro" → "letters" (emoji is accessible via button on all layers)
    /// - absent/invalid → no-op (defaults handle it)
    public static func migrateFromKeyboardModeIfNeeded() {
        let defaults = AppGroup.preferences

        // Skip if already migrated (new key exists)
        if defaults.string(forKey: SharedKeys.defaultKeyboardLayer) != nil {
            return
        }

        // Read old value — suppress deprecation warning since we need it for migration
        let oldKey = "dictus.keyboardMode"
        guard let oldValue = defaults.string(forKey: oldKey) else {
            return // No old value stored, defaults will handle it
        }

        let newValue: String
        switch oldValue {
        case "micro":
            newValue = DefaultKeyboardLayer.numbers.rawValue
        case "full", "emojiMicro":
            newValue = DefaultKeyboardLayer.letters.rawValue
        default:
            newValue = DefaultKeyboardLayer.letters.rawValue
        }

        defaults.set(newValue, forKey: SharedKeys.defaultKeyboardLayer)
        defaults.removeObject(forKey: oldKey)
    }
}
