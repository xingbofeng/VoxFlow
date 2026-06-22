import Foundation

@MainActor
final class DelayedHotKeyPressController {
    typealias Sleep = @Sendable (UInt64) async throws -> Void
    typealias Handler = @MainActor (VoiceAction) -> Void

    private let logger = AppLogger.general
    private let sleep: Sleep
    private var task: Task<Void, Never>?

    init(sleep: @escaping Sleep = { nanoseconds in
        try await Task.sleep(nanoseconds: nanoseconds)
    }) {
        self.sleep = sleep
    }

    deinit {
        task?.cancel()
    }

    func schedule(
        action: VoiceAction,
        threshold: TimeInterval,
        handler: @escaping Handler
    ) {
        logger.debug("DelayedHotKeyPressController schedule action=\(action) threshold=\(threshold)")
        cancel()
        let nanoseconds = UInt64(max(0, threshold) * 1_000_000_000)
        logger.debug("DelayedHotKeyPressController waiting ns=\(nanoseconds)")
        task = Task { @MainActor [sleep] in
            do {
                try await sleep(nanoseconds)
            } catch {
                logger.debug("DelayedHotKeyPressController schedule cancelled")
                return
            }
            guard !Task.isCancelled else { return }
            logger.debug("DelayedHotKeyPressController fire action=\(action)")
            handler(action)
        }
    }

    func cancel() {
        if task != nil {
            logger.debug("DelayedHotKeyPressController cancel")
        }
        task?.cancel()
        task = nil
    }
}
