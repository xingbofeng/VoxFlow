import AppKit

public struct PasteboardTransaction {
    public let originalSnapshot: PasteboardSnapshot
    public let replacementChangeCount: Int

    public static func begin(
        on pasteboard: NSPasteboard,
        replacementText: String
    ) -> PasteboardTransaction {
        let originalSnapshot = PasteboardSnapshot(items: pasteboard.pasteboardItems ?? [])
        pasteboard.clearContents()
        pasteboard.setString(replacementText, forType: .string)
        return PasteboardTransaction(
            originalSnapshot: originalSnapshot,
            replacementChangeCount: pasteboard.changeCount
        )
    }

    @discardableResult
    public func restoreOriginalIfUnchanged(on pasteboard: NSPasteboard) -> Bool {
        guard isCurrent(on: pasteboard) else {
            return false
        }

        pasteboard.clearContents()
        let items = originalSnapshot.makePasteboardItems()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
        return true
    }

    public func isCurrent(on pasteboard: NSPasteboard) -> Bool {
        pasteboard.changeCount == replacementChangeCount
    }
}
