@preconcurrency import AVFoundation

public enum PersistentAudioConverterError: Error {
    case unsupportedFormat
    case sourceFormatChanged
    case conversionFailed(String)
}

public final class PersistentAudioConverter: AudioPCMConverting, @unchecked Sendable {
    public let targetSampleRate: Double
    public private(set) var converterCreationCount = 0
    public private(set) var convertedOutputSampleCount = 0

    private let targetFormat: AVAudioFormat
    private var sourceFormat: AVAudioFormat?
    private var converterSourceFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    public init(targetSampleRate: Double = 16_000) throws {
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw PersistentAudioConverterError.unsupportedFormat
        }
        self.targetSampleRate = targetSampleRate
        self.targetFormat = targetFormat
    }

    public func convert(_ buffer: AVAudioPCMBuffer) throws -> ContiguousArray<Float> {
        guard buffer.frameLength > 0 else { return [] }

        try ensureSessionFormat(for: buffer.format)
        let conversionInput = try makeMonoInputBufferIfNeeded(buffer)
        let converter = try ensureConverter(for: conversionInput.format)
        let outputBuffer = try makeOutputBuffer(
            forInputFrameCount: conversionInput.frameLength,
            sourceSampleRate: conversionInput.format.sampleRate
        )
        nonisolated(unsafe) var inputProvided = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputProvided = true
            outStatus.pointee = .haveData
            return conversionInput
        }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        if let error {
            throw PersistentAudioConverterError.conversionFailed(error.localizedDescription)
        }
        let samples = Self.samples(from: outputBuffer)
        convertedOutputSampleCount += samples.count
        return samples
    }

    public func finish() throws -> ContiguousArray<Float> {
        guard let converter else { return [] }

        var output = ContiguousArray<Float>()
        nonisolated(unsafe) var endOfStreamSent = false
        while true {
            let outputBuffer = try makeOutputBuffer(capacity: 4_096)
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if endOfStreamSent {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                endOfStreamSent = true
                outStatus.pointee = .endOfStream
                return nil
            }
            if let error {
                throw PersistentAudioConverterError.conversionFailed(error.localizedDescription)
            }

            let samples = Self.samples(from: outputBuffer)
            convertedOutputSampleCount += samples.count
            output.append(contentsOf: samples)
            if status == .endOfStream || status == .inputRanDry || outputBuffer.frameLength == 0 {
                break
            }
        }
        return output
    }

    private func ensureSessionFormat(for format: AVAudioFormat) throws {
        if let sourceFormat {
            guard Self.matches(sourceFormat, format) else {
                throw PersistentAudioConverterError.sourceFormatChanged
            }
        } else {
            sourceFormat = format
        }
    }

    private func ensureConverter(for format: AVAudioFormat) throws -> AVAudioConverter {
        if let converterSourceFormat {
            guard Self.matches(converterSourceFormat, format) else {
                throw PersistentAudioConverterError.sourceFormatChanged
            }
        } else {
            converterSourceFormat = format
        }

        if let converter {
            return converter
        }

        guard let converter = AVAudioConverter(from: format, to: targetFormat) else {
            throw PersistentAudioConverterError.unsupportedFormat
        }
        self.converter = converter
        converterCreationCount += 1
        return converter
    }

    private func makeOutputBuffer(
        forInputFrameCount frameCount: AVAudioFrameCount,
        sourceSampleRate: Double
    ) throws -> AVAudioPCMBuffer {
        let ratio = targetSampleRate / sourceSampleRate
        let capacity = AVAudioFrameCount(ceil(Double(frameCount) * ratio)) + 512
        return try makeOutputBuffer(capacity: max(capacity, 1))
    }

    private func makeOutputBuffer(capacity: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: capacity
        ) else {
            throw PersistentAudioConverterError.unsupportedFormat
        }
        return buffer
    }

    private static func samples(from buffer: AVAudioPCMBuffer) -> ContiguousArray<Float> {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0,
              let channel = buffer.floatChannelData?[0] else {
            return []
        }
        return ContiguousArray(UnsafeBufferPointer(start: channel, count: frameCount))
    }

    private func makeMonoInputBufferIfNeeded(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 1 else { return buffer }
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: buffer.format.sampleRate,
            channels: 1,
            interleaved: false
        ),
            let monoBuffer = AVAudioPCMBuffer(
                pcmFormat: monoFormat,
                frameCapacity: buffer.frameLength
            ),
            let sourceChannels = buffer.floatChannelData,
            let monoChannel = monoBuffer.floatChannelData?[0]
        else {
            throw PersistentAudioConverterError.unsupportedFormat
        }

        let frameCount = Int(buffer.frameLength)
        monoBuffer.frameLength = buffer.frameLength
        for frameIndex in 0..<frameCount {
            var sum: Float = 0
            for channelIndex in 0..<channelCount {
                sum += sourceChannels[channelIndex][frameIndex]
            }
            monoChannel[frameIndex] = sum / Float(channelCount)
        }
        return monoBuffer
    }

    private static func matches(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }
}
