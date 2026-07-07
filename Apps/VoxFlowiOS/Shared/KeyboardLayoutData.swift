// DictusCore/Sources/DictusCore/KeyboardLayoutData.swift
// Shared keyboard layout data accessible by both DictusApp and DictusKeyboard.
import Foundation

/// Keyboard layout type persisted to App Group so both targets agree on the active layout.
///
/// WHY this lives in DictusCore:
/// Both the main app (settings UI) and the keyboard extension need to read/write the
/// layout preference. Putting the enum and its persistence logic in the shared framework
/// prevents each target from defining its own incompatible version.
public enum LayoutType: String, Codable, Sendable {
    case azerty
    case qwerty

    /// Reads the active layout from App Group UserDefaults, defaulting to QWERTY.
    public static var active: LayoutType {
        guard let raw = AppGroup.preferences.string(forKey: SharedKeys.keyboardLayout),
              let layout = LayoutType(rawValue: raw) else {
            return .qwerty
        }
        return layout
    }
}

/// QWERTY letter layout as raw string arrays.
///
/// WHY string arrays instead of KeyDefinition:
/// KeyDefinition lives in DictusKeyboard and carries UI-specific properties (widthMultiplier,
/// KeyType). DictusCore shouldn't depend on UI types. The keyboard target converts these
/// strings to KeyDefinition at the view layer. This also makes the layout data easily testable.
public enum QWERTYLayout {
    /// Four rows of key labels.
    /// - Row 0: 10 letter keys (Q through P)
    /// - Row 1: 9 letter keys (A through L)
    /// - Row 2: 7 letter keys (Z through M) — shift and delete are added by keyboard target
    /// - Row 3: 5 bottom row placeholders — actual rendering handled by keyboard target
    public static let lettersRows: [[String]] = [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"],
        ["globe", "123", "mic", "space", "return"]
    ]
}
