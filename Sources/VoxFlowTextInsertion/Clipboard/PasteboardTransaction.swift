import AppKit

public struct PasteboardTransaction {
    public let originalSnapshot: PasteboardSnapshot
    public let replacementChangeCount: Int
    private let markInternalChangeCount: (Int) -> Void
    private static let internalMarkerType = NSPasteboard.PasteboardType("com.voxflow.pasteboard.internal")

    public static func begin(
        on pasteboard: NSPasteboard,
        replacementText: String,
        markInternalChangeCount: @escaping (Int) -> Void = { _ in }
    ) -> PasteboardTransaction {
        let originalSnapshot = PasteboardSnapshot(items: pasteboard.pasteboardItems ?? [])
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, internalMarkerType], owner: nil)
        pasteboard.setString(replacementText, forType: .string)
        pasteboard.setString("1", forType: internalMarkerType)
        markInternalChangeCount(pasteboard.changeCount)
        return PasteboardTransaction(
            originalSnapshot: originalSnapshot,
            replacementChangeCount: pasteboard.changeCount,
            markInternalChangeCount: markInternalChangeCount
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
        markInternalChangeCount(pasteboard.changeCount)
        return true
    }

    public func isCurrent(on pasteboard: NSPasteboard) -> Bool {
        pasteboard.changeCount == replacementChangeCount
    }
}
