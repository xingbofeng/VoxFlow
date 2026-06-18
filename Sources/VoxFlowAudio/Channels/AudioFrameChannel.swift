public enum AudioFrameChannelSendResult: Equatable, Sendable {
    case enqueued
    case dropped
}

public struct AudioFrameChannelSnapshot: Equatable, Sendable {
    public let capacity: Int
    public let bufferedFrameCount: Int
    public let droppedFrameCount: UInt64
}

public actor AudioFrameChannel {
    private let capacity: Int
    private var buffer: [AudioFrame] = []
    private var continuations: [CheckedContinuation<AudioFrame?, Never>] = []
    private var pendingSends: [(AudioFrame, CheckedContinuation<AudioFrameChannelSendResult, Never>)] = []
    private var isFinished = false
    private var droppedFrameCount: UInt64 = 0

    public init(capacity: Int) {
        precondition(capacity > 0, "AudioFrameChannel capacity must be positive.")
        self.capacity = capacity
    }

    public func send(_ frame: AudioFrame) -> AudioFrameChannelSendResult {
        guard !isFinished else {
            droppedFrameCount += 1
            return .dropped
        }

        if !continuations.isEmpty {
            let continuation = continuations.removeFirst()
            continuation.resume(returning: frame)
            return .enqueued
        }

        guard buffer.count < capacity else {
            droppedFrameCount += 1
            return .dropped
        }

        buffer.append(frame)
        return .enqueued
    }

    public func sendAfterDrain(_ frame: AudioFrame) async -> AudioFrameChannelSendResult {
        guard !isFinished else {
            droppedFrameCount += 1
            return .dropped
        }

        if !continuations.isEmpty {
            let continuation = continuations.removeFirst()
            continuation.resume(returning: frame)
            return .enqueued
        }

        if buffer.count < capacity {
            buffer.append(frame)
            return .enqueued
        }

        return await withCheckedContinuation { continuation in
            pendingSends.append((frame, continuation))
        }
    }

    public func next() async -> AudioFrame? {
        if !buffer.isEmpty {
            let frame = buffer.removeFirst()
            enqueuePendingSendIfPossible()
            return frame
        }

        if isFinished {
            return nil
        }

        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    public func finish() {
        isFinished = true
        let waitingContinuations = continuations
        continuations.removeAll()
        for continuation in waitingContinuations {
            continuation.resume(returning: nil)
        }

        let waitingSends = pendingSends
        pendingSends.removeAll()
        droppedFrameCount += UInt64(waitingSends.count)
        for (_, continuation) in waitingSends {
            continuation.resume(returning: .dropped)
        }
    }

    public func snapshot() -> AudioFrameChannelSnapshot {
        AudioFrameChannelSnapshot(
            capacity: capacity,
            bufferedFrameCount: buffer.count,
            droppedFrameCount: droppedFrameCount
        )
    }

    private func enqueuePendingSendIfPossible() {
        guard !isFinished,
              buffer.count < capacity,
              !pendingSends.isEmpty else {
            return
        }

        let (frame, continuation) = pendingSends.removeFirst()
        buffer.append(frame)
        continuation.resume(returning: .enqueued)
    }
}
