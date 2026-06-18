public actor AudioCaptureActor {
    private let channel: AudioFrameChannel
    private let currentInstant: @Sendable () -> ContinuousClock.Instant
    private var nextSequenceNumber: UInt64 = 0
    private var nextStartSample: UInt64 = 0

    public init(
        channel: AudioFrameChannel,
        currentInstant: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.channel = channel
        self.currentInstant = currentInstant
    }

    public func append(
        samples: ContiguousArray<Float>,
        sampleRate: Int
    ) async -> AudioFrameChannelSendResult {
        let frame = nextFrame(samples: samples, sampleRate: sampleRate)
        return await channel.send(frame)
    }

    public func appendAfterDrain(
        samples: ContiguousArray<Float>,
        sampleRate: Int
    ) async -> AudioFrameChannelSendResult {
        let frame = nextFrame(samples: samples, sampleRate: sampleRate)
        return await channel.sendAfterDrain(frame)
    }

    private func nextFrame(
        samples: ContiguousArray<Float>,
        sampleRate: Int
    ) -> AudioFrame {
        let sequenceNumber = nextSequenceNumber
        let startSample = nextStartSample
        nextSequenceNumber += 1
        nextStartSample += UInt64(samples.count)

        return AudioFrame(
            sequenceNumber: sequenceNumber,
            startSample: startSample,
            samples: samples,
            sampleRate: sampleRate,
            capturedAt: currentInstant()
        )
    }

    public func finish() async {
        await channel.finish()
    }
}
