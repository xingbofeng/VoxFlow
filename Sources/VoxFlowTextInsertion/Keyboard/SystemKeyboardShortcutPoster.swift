import AppKit

public enum KeyboardShortcutPostingError: Error, Equatable {
    case unsupportedKey
    case eventCreationFailed
}

@MainActor
public final class SystemKeyboardShortcutPoster {
    private let allowsSystemInteraction: @MainActor () -> Bool
    private let postEvents: @MainActor (CGEvent, CGEvent) -> Void

    public init(
        allowsSystemInteraction: @escaping @MainActor () -> Bool = {
            !TextInsertionRuntimeEnvironment.isRunningUnderXCTest()
        },
        postEvents: @escaping @MainActor (CGEvent, CGEvent) -> Void = {
            $0.post(tap: .cghidEventTap)
            $1.post(tap: .cghidEventTap)
        }
    ) {
        self.allowsSystemInteraction = allowsSystemInteraction
        self.postEvents = postEvents
    }

    public func postKey(named key: String) throws {
        guard allowsSystemInteraction() else { return }
        guard let keyCode = Self.keyCode(for: key.lowercased()) else {
            throw KeyboardShortcutPostingError.unsupportedKey
        }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw KeyboardShortcutPostingError.eventCreationFailed
        }
        postEvents(keyDown, keyUp)
    }

    private static func keyCode(for key: String) -> CGKeyCode? {
        switch key {
        case "escape", "esc": return 0x35
        case "tab": return 0x30
        case "space": return 0x31
        case "delete", "backspace": return 0x33
        case "left": return 0x7B
        case "right": return 0x7C
        case "down": return 0x7D
        case "up": return 0x7E
        case "home": return 0x73
        case "end": return 0x77
        case "pageup": return 0x74
        case "pagedown": return 0x79
        default: return nil
        }
    }
}
