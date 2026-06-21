import Foundation

/// Shared mapping from keyboard key codes to display names and SF Symbol icons.
/// Used by HelpView, SettingsRootView, and AppDelegate to avoid duplication.
enum KeyCodeMapping {
    static func displayName(for keyCode: Int64) -> String {
        let modifierMask = ShortcutManager.modifierMask(for: keyCode)
        if modifierMask != 0 {
            let modifiers = modifierDisplayNames(for: modifierMask)
            return (modifiers + [displayName(forBaseKeyCode: ShortcutManager.baseKeyCode(for: keyCode))])
                .joined(separator: " + ")
        }
        return displayName(forBaseKeyCode: keyCode)
    }

    private static func displayName(forBaseKeyCode keyCode: Int64) -> String {
        switch keyCode {
        case 54: return "右 Command"
        case 55: return "左 Command"
        case 56: return "左 Shift"
        case 60: return "右 Shift"
        case 58: return "左 Option"
        case 61: return "右 Option"
        case 59: return "左 Control"
        case 62: return "右 Control"
        case 36: return "Return"
        case 49: return "Space"
        case 53: return "Escape"
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        default: return "按键 \(keyCode)"
        }
    }

    static func iconName(for keyCode: Int64) -> String {
        if ShortcutManager.modifierMask(for: keyCode) != 0 {
            return "keyboard"
        }
        switch keyCode {
        case 54, 55: return "command"
        case 56, 60: return "shift"
        case 58, 61: return "option"
        case 59, 62: return "control"
        case 36: return "return"
        case 49: return "space"
        case 53: return "escape"
        default: return "keyboard"
        }
    }

    private static func modifierDisplayNames(for mask: Int64) -> [String] {
        var names: [String] = []
        if mask & ShortcutManager.commandModifierMask != 0 { names.append("Command") }
        if mask & ShortcutManager.shiftModifierMask != 0 { names.append("Shift") }
        if mask & ShortcutManager.optionModifierMask != 0 { names.append("Option") }
        if mask & ShortcutManager.controlModifierMask != 0 { names.append("Control") }
        return names
    }
}
