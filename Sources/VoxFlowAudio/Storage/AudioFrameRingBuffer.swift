public enum AudioFrameRingBufferAppendResult: Equatable, Sendable {
    case stored
    case dropped
}

public struct AudioFrameRingBufferSnapshot: Equatable, Sendable {
    public let capacitySamples: Int
    public let bufferedSampleCount: Int
    public let evictedFrameCount: UInt64
    public let droppedFrameCount: UInt64
}

public struct AudioFrameRingBuffer: Sendable {
    public let capacitySamples: Int
    public private(set) var frames: [AudioFrame] = []
    public private(set) var bufferedSampleCount = 0
    public private(set) var evictedFrameCount: UInt64 = 0
    public private(set) var droppedFrameCount: UInt64 = 0

    public init(capacitySamples: Int) {
        precondition(capacitySamples > 0, "AudioFrameRingBuffer capacity must be positive.")
        self.capacitySamples = capacitySamples
    }

    public var snapshot: AudioFrameRingBufferSnapshot {
        AudioFrameRingBufferSnapshot(
            capacitySamples: capacitySamples,
            bufferedSampleCount: bufferedSampleCount,
            evictedFrameCount: evictedFrameCount,
            droppedFrameCount: droppedFrameCount
        )
    }

    @discardableResult
    public mutating func append(_ frame: AudioFrame) -> AudioFrameRingBufferAppendResult {
        let sampleCount = frame.samples.count
        guard sampleCount <= capacitySamples else {
            droppedFrameCount += 1
            return .dropped
        }

        frames.append(frame)
        bufferedSampleCount += sampleCount
        evictOldFramesUntilWithinCapacity()
        return .stored
    }

    private mutating func evictOldFramesUntilWithinCapacity() {
        while bufferedSampleCount > capacitySamples,
              let oldestFrame = frames.first {
            bufferedSampleCount -= oldestFrame.samples.count
            evictedFrameCount += 1
            frames.removeFirst()
        }
    }
}
