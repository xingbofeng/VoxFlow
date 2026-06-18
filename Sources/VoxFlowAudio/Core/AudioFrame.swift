public struct AudioFrame: Sendable {
    public let sequenceNumber: UInt64
    public let startSample: UInt64
    public let samples: ContiguousArray<Float>
    public let sampleRate: Int
    public let capturedAt: ContinuousClock.Instant

    public init(
        sequenceNumber: UInt64,
        startSample: UInt64,
        samples: ContiguousArray<Float>,
        sampleRate: Int,
        capturedAt: ContinuousClock.Instant
    ) {
        self.sequenceNumber = sequenceNumber
        self.startSample = startSample
        self.samples = samples
        self.sampleRate = sampleRate
        self.capturedAt = capturedAt
    }
}
