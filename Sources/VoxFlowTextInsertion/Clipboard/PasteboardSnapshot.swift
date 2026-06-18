import AppKit
import Foundation

public struct PasteboardSnapshot {
    public struct Item {
        public let representations: [NSPasteboard.PasteboardType: Data]

        public init(representations: [NSPasteboard.PasteboardType: Data]) {
            self.representations = representations
        }
    }

    public let items: [Item]

    public init(items: [NSPasteboardItem]) {
        self.items = items.map { pasteboardItem in
            let representations = pasteboardItem.types.reduce(
                into: [NSPasteboard.PasteboardType: Data]()
            ) { result, type in
                result[type] = pasteboardItem.data(forType: type)
            }
            return Item(representations: representations)
        }
    }

    public init(archivedItems: [[NSPasteboard.PasteboardType: Data]]) {
        items = archivedItems.map(Item.init(representations:))
    }

    public func makePasteboardItems() -> [NSPasteboardItem] {
        items.map { archivedItem in
            let item = NSPasteboardItem()
            for (type, data) in archivedItem.representations {
                item.setData(data, forType: type)
            }
            return item
        }
    }
}
