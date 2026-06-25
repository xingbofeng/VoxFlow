import Foundation
import VoxFlowAudio

public protocol ASRSession: Sendable {
    var sessionID: ASRSessionID { get }
    var revision: UInt64 { get }
    var events: AsyncStream<ASREvent> { get }

    func configurePrompt(_ prompt: String?) async throws
    func start() async throws
    func accept(_ frame: AudioFrame) async throws
    func finish() async throws
    func cancel() async
}

public extension ASRSession {
    func configurePrompt(_ prompt: String?) async throws {}
}

public final class ASREventStream: @unchecked Sendable {
    public let stream: AsyncStream<ASREvent>

    private let lock = NSLock()
    private var continuation: AsyncStream<ASREvent>.Continuation?

    public init(
        bufferingPolicy: AsyncStream<ASREvent>.Continuation.BufferingPolicy = .unbounded
    ) {
        var capturedContinuation: AsyncStream<ASREvent>.Continuation?
        stream = AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            capturedContinuation = continuation
        }
        continuation = capturedContinuation
    }

    public func yield(_ event: ASREvent) {
        lock.lock()
        let currentContinuation = continuation
        lock.unlock()

        currentContinuation?.yield(event)
    }

    public func finish() {
        lock.lock()
        let currentContinuation = continuation
        continuation = nil
        lock.unlock()

        currentContinuation?.finish()
    }
}
