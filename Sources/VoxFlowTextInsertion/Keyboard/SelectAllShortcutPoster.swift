import AppKit

public enum SelectAllShortcutPostingError: Error, Equatable {
    case eventCreationFailed
}

/// Selects everything in the focused input area (⌘A) so that the next
/// insertion replaces the field's contents instead of appending at the caret.
@MainActor
public protocol SelectAllShortcutPosting: AnyObject {
    func postSelectAllShortcut() throws
}

@MainActor
public final class SystemSelectAllShortcutPoster: SelectAllShortcutPosting {
    /// Virtual key code of "A" on the ANSI layout.
    private static let aKeyCode: CGKeyCode = 0x00

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

    public func postSelectAllShortcut() throws {
        guard allowsSystemInteraction() else { return }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let aDown = CGEvent(keyboardEventSource: source, virtualKey: Self.aKeyCode, keyDown: true),
              let aUp = CGEvent(keyboardEventSource: source, virtualKey: Self.aKeyCode, keyDown: false) else {
            throw SelectAllShortcutPostingError.eventCreationFailed
        }
        aDown.flags = .maskCommand
        aUp.flags = .maskCommand
        postEvents(aDown, aUp)
    }
}
