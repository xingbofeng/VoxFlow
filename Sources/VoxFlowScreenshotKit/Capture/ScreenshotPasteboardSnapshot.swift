import AppKit
import Foundation

public struct ScreenshotPasteboardSnapshot: Sendable {
    public struct Item: Sendable {
        public let representations: [String: Data]

        public init(representations: [String: Data]) {
            self.representations = representations
        }
    }

    public let items: [Item]

    public static func capture(from pasteboard: NSPasteboard = .general) -> ScreenshotPasteboardSnapshot {
        ScreenshotPasteboardSnapshot(items: pasteboard.pasteboardItems ?? [])
    }

    public init(items: [NSPasteboardItem]) {
        self.items = items.map { item in
            let representations = item.types.reduce(into: [String: Data]()) { result, type in
                result[type.rawValue] = item.data(forType: type)
            }
            return Item(representations: representations)
        }
    }

    public init(archivedItems: [[String: Data]]) {
        items = archivedItems.map(Item.init(representations:))
    }

    public func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let pasteboardItems = makePasteboardItems()
        if !pasteboardItems.isEmpty {
            pasteboard.writeObjects(pasteboardItems)
        }
    }

    public func makePasteboardItems() -> [NSPasteboardItem] {
        items.map { archivedItem in
            let item = NSPasteboardItem()
            for (rawType, data) in archivedItem.representations {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawType))
            }
            return item
        }
    }
}

@MainActor
public final class ScreenshotClipboardGuard {
    private let pasteboard: NSPasteboard
    private let snapshot: ScreenshotPasteboardSnapshot
    private var isResolved = false

    private init(pasteboard: NSPasteboard, snapshot: ScreenshotPasteboardSnapshot) {
        self.pasteboard = pasteboard
        self.snapshot = snapshot
    }

    public static func begin(on pasteboard: NSPasteboard = .general) -> ScreenshotClipboardGuard {
        ScreenshotClipboardGuard(
            pasteboard: pasteboard,
            snapshot: ScreenshotPasteboardSnapshot.capture(from: pasteboard)
        )
    }

    public func restoreOnCancel() {
        guard !isResolved else { return }
        snapshot.restore(to: pasteboard)
        isResolved = true
    }

    public func keepOnSuccess() {
        isResolved = true
    }
}
