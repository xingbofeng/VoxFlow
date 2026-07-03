import AppKit

final class ClipboardInternalWriteGuard {
    private struct RecentTextOutput {
        let normalizedText: String
        let sourceAppName: String?
        let sourceAppBundleID: String?
        let expiresAt: Date
    }

    private var internalChangeCounts: Set<Int> = []
    private var recentTextOutputs: [RecentTextOutput] = []
    private let maxTrackedChangeCounts: Int
    private let recentTextOutputTTL: TimeInterval

    init(
        maxTrackedChangeCounts: Int = 32,
        recentTextOutputTTL: TimeInterval = 5
    ) {
        self.maxTrackedChangeCounts = maxTrackedChangeCounts
        self.recentTextOutputTTL = recentTextOutputTTL
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

    func markRecentTextOutput(
        _ text: String,
        sourceAppName: String?,
        sourceAppBundleID: String?,
        now: Date = Date()
    ) {
        let normalized = Self.normalizedTextFingerprint(text)
        guard !normalized.isEmpty else { return }
        removeExpiredRecentTextOutputs(now: now)
        recentTextOutputs.append(
            RecentTextOutput(
                normalizedText: normalized,
                sourceAppName: sourceAppName,
                sourceAppBundleID: sourceAppBundleID,
                expiresAt: now.addingTimeInterval(recentTextOutputTTL)
            )
        )
    }

    func shouldIgnoreRecentTextOutput(
        _ text: String,
        sourceAppName: String?,
        sourceAppBundleID: String?,
        now: Date = Date()
    ) -> Bool {
        removeExpiredRecentTextOutputs(now: now)
        let normalized = Self.normalizedTextFingerprint(text)
        guard !normalized.isEmpty else { return false }
        return recentTextOutputs.contains { output in
            output.normalizedText == normalized
                && sourceMatches(
                    output: output,
                    sourceAppName: sourceAppName,
                    sourceAppBundleID: sourceAppBundleID
                )
        }
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

    private func removeExpiredRecentTextOutputs(now: Date) {
        recentTextOutputs.removeAll { $0.expiresAt <= now }
    }

    private func sourceMatches(
        output: RecentTextOutput,
        sourceAppName: String?,
        sourceAppBundleID: String?
    ) -> Bool {
        if let outputBundleID = output.sourceAppBundleID,
           let sourceAppBundleID {
            return outputBundleID == sourceAppBundleID
        }
        if let outputName = output.sourceAppName,
           let sourceAppName {
            return outputName == sourceAppName
        }
        return output.sourceAppBundleID == nil && output.sourceAppName == nil
    }

    private static func normalizedTextFingerprint(_ text: String) -> String {
        text.unicodeScalars.reduce(into: "") { result, scalar in
            guard CharacterSet.alphanumerics.contains(scalar) else { return }
            result.append(String(scalar).lowercased())
        }
    }
}
