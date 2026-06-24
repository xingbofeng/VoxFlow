import AppKit

public enum PasteShortcutPostingError: Error, Equatable {
    case eventCreationFailed
}

@MainActor
public protocol PasteShortcutPosting: AnyObject {
    func postPasteShortcut() throws
}

@MainActor
public final class SystemPasteShortcutPoster: PasteShortcutPosting {
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

    public func postPasteShortcut() throws {
        guard allowsSystemInteraction() else { return }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            throw PasteShortcutPostingError.eventCreationFailed
        }
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        postEvents(vDown, vUp)
    }
}
