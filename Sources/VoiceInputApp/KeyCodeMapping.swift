import Foundation

/// Shared mapping from keyboard key codes to display names and SF Symbol icons.
/// Used by HelpView, SettingsRootView, and AppDelegate to avoid duplication.
enum KeyCodeMapping {
    static func displayName(for keyCode: Int64) -> String {
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
        default: return "按键 \(keyCode)"
        }
    }

    static func iconName(for keyCode: Int64) -> String {
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
}
