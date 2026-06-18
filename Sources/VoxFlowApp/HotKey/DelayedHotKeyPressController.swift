import Foundation

@MainActor
final class DelayedHotKeyPressController {
    typealias Sleep = @Sendable (UInt64) async throws -> Void
    typealias Handler = @MainActor (VoiceAction) -> Void

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
        cancel()
        let nanoseconds = UInt64(max(0, threshold) * 1_000_000_000)
        task = Task { @MainActor [sleep] in
            do {
                try await sleep(nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            handler(action)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
