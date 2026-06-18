import Foundation

public enum AudioEndpointEvent: Equatable, Sendable {
    case speechStarted(sequenceNumber: UInt64)
    case speechEnded(sequenceNumber: UInt64, trailingSilenceSamples: Int)
}

public struct AudioEndpointDetector: Sendable {
    public let speechThreshold: Float
    public let trailingSilenceSamples: Int

    private var isInSpeech = false
    private var trailingSilenceSampleCount = 0

    public init(
        speechThreshold: Float,
        trailingSilenceSamples: Int
    ) {
        precondition(trailingSilenceSamples > 0, "Trailing silence threshold must be positive.")
        self.speechThreshold = speechThreshold
        self.trailingSilenceSamples = trailingSilenceSamples
    }

    public mutating func process(_ frame: AudioFrame) -> [AudioEndpointEvent] {
        let isSpeech = Self.rootMeanSquareEnergy(frame.samples) >= speechThreshold

        if isSpeech {
            trailingSilenceSampleCount = 0
            if !isInSpeech {
                isInSpeech = true
                return [.speechStarted(sequenceNumber: frame.sequenceNumber)]
            }
            return []
        }

        guard isInSpeech else { return [] }
        trailingSilenceSampleCount += frame.samples.count
        if trailingSilenceSampleCount >= trailingSilenceSamples {
            isInSpeech = false
            let silenceSamples = trailingSilenceSampleCount
            trailingSilenceSampleCount = 0
            return [
                .speechEnded(
                    sequenceNumber: frame.sequenceNumber,
                    trailingSilenceSamples: silenceSamples
                )
            ]
        }
        return []
    }

    private static func rootMeanSquareEnergy(_ samples: ContiguousArray<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return sqrt(sum / Float(samples.count))
    }
}
