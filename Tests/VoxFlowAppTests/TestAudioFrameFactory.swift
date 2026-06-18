import Foundation
import VoxFlowAudio

func makeTestAudioFrame(
    sampleCount: Int,
    sampleRate: Int = 16_000,
    waveformDivisor: Float = 40,
    amplitude: Float = 0.1
) -> AudioFrame {
    let samples = (0..<sampleCount).map { index in
        sin(Float(index) / waveformDivisor) * amplitude
    }
    return makeTestAudioFrame(samples: samples, sampleRate: sampleRate)
}

func makeTestAudioFrame(
    samples: [Float],
    sampleRate: Int = 16_000
) -> AudioFrame {
    AudioFrame(
        sequenceNumber: 0,
        startSample: 0,
        samples: ContiguousArray(samples),
        sampleRate: sampleRate,
        capturedAt: .now
    )
}
