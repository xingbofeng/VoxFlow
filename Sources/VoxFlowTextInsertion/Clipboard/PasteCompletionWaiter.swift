import AppKit

public enum PasteCompletionWaitResult: Equatable, Sendable {
    case pasteboardChanged
    case pasteboardUnchangedAfterTimeout
}

public struct PasteCompletionWaiter {
    public let pollIntervalNanoseconds: UInt64
    public let maxPollCount: Int

    public init(
        pollIntervalNanoseconds: UInt64 = 10_000_000,
        maxPollCount: Int = 20
    ) {
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.maxPollCount = max(0, maxPollCount)
    }

    @MainActor
    public func waitForPasteWindow(
        on pasteboard: NSPasteboard,
        transaction: PasteboardTransaction,
        sleep: (UInt64) async -> Void = { delay in
            try? await Task.sleep(nanoseconds: delay)
        }
    ) async -> PasteCompletionWaitResult {
        for _ in 0..<maxPollCount {
            guard transaction.isCurrent(on: pasteboard) else {
                return .pasteboardChanged
            }
            await sleep(pollIntervalNanoseconds)
        }

        return transaction.isCurrent(on: pasteboard)
            ? .pasteboardUnchangedAfterTimeout
            : .pasteboardChanged
    }
}
