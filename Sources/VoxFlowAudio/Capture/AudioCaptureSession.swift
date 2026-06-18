@preconcurrency import AVFoundation

public protocol AudioPCMConverting: AnyObject, Sendable {
    var targetSampleRate: Double { get }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> ContiguousArray<Float>
    func finish() throws -> ContiguousArray<Float>
}

public actor AudioCaptureSession {
    private let converter: AudioPCMConverting
    private let captureActor: AudioCaptureActor

    public init(
        channel: AudioFrameChannel,
        converter: AudioPCMConverting,
        currentInstant: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.converter = converter
        captureActor = AudioCaptureActor(
            channel: channel,
            currentInstant: currentInstant
        )
    }

    public func append(_ buffer: AVAudioPCMBuffer) async throws -> AudioFrameChannelSendResult? {
        let samples = try converter.convert(buffer)
        guard !samples.isEmpty else { return nil }
        return await captureActor.append(
            samples: samples,
            sampleRate: Int(converter.targetSampleRate)
        )
    }

    public func finish() async throws -> AudioFrameChannelSendResult? {
        let tailSamples = try converter.finish()
        let tailResult: AudioFrameChannelSendResult?
        if tailSamples.isEmpty {
            tailResult = nil
        } else {
            tailResult = await captureActor.appendAfterDrain(
                samples: tailSamples,
                sampleRate: Int(converter.targetSampleRate)
            )
        }
        await captureActor.finish()
        return tailResult
    }
}
