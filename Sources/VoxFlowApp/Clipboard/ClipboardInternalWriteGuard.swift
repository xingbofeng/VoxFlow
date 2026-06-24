import AppKit

final class ClipboardInternalWriteGuard {
    private var internalChangeCounts: Set<Int> = []
    private let maxTrackedChangeCounts: Int

    init(maxTrackedChangeCounts: Int = 32) {
        self.maxTrackedChangeCounts = maxTrackedChangeCounts
    }

    /// Adapted from Stash ClipboardMonitor.swift (MIT): https://github.com/hex/Stash
    /// Records pasteboard writes performed by VoxFlow so the clipboard monitor can skip them.
    func markInternalWrite(changeCount: Int) {
        internalChangeCounts.insert(changeCount)
        trimTrackedChangeCounts()
    }

    func shouldIgnore(
        changeCount: Int,
        types: [NSPasteboard.PasteboardType]
    ) -> Bool {
        internalChangeCounts.contains(changeCount)
            || types.contains(.voxFlowInternalMarker)
    }

    @discardableResult
    func writeInternalString(
        _ text: String,
        to pasteboard: NSPasteboard
    ) -> Bool {
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, .voxFlowInternalMarker], owner: nil)
        let wroteText = pasteboard.setString(text, forType: .string)
        let wroteMarker = pasteboard.setString("1", forType: .voxFlowInternalMarker)
        if wroteText || wroteMarker {
            markInternalWrite(changeCount: pasteboard.changeCount)
        }
        return wroteText
    }

    private func trimTrackedChangeCounts() {
        guard internalChangeCounts.count > maxTrackedChangeCounts else { return }
        let overflow = internalChangeCounts.count - maxTrackedChangeCounts
        for changeCount in internalChangeCounts.sorted().prefix(overflow) {
            internalChangeCounts.remove(changeCount)
        }
    }
}
