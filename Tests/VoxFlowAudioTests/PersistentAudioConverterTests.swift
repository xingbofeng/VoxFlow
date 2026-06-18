import AVFoundation
import XCTest
import VoxFlowAudio

final class PersistentAudioConverterTests: XCTestCase {
    func testConverterReusesOneAVAudioConverterForASession() throws {
        let converter = try PersistentAudioConverter()
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))

        let first = try converter.convert(Self.sineBuffer(format: format, frameCount: 4_800))
        let second = try converter.convert(Self.sineBuffer(format: format, frameCount: 4_800))

        XCTAssertGreaterThan(first.count, 0)
        XCTAssertGreaterThan(second.count, 0)
        XCTAssertEqual(converter.converterCreationCount, 1)
    }

    func testConverterSupportsCommonInputRatesTo16kMono() throws {
        for sampleRate in [48_000.0, 44_100.0, 32_000.0] {
            let converter = try PersistentAudioConverter()
            let duration = 0.25
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
            let frameCount = Int(sampleRate * duration)

            var output = try converter.convert(Self.sineBuffer(format: format, frameCount: frameCount))
            output.append(contentsOf: try converter.finish())

            let expectedCount = Int(16_000.0 * duration)
            XCTAssertEqual(
                output.count,
                expectedCount,
                accuracy: 320,
                "Unexpected 16k output count for \(sampleRate) Hz input"
            )
        }
    }

    func testConverterDownmixesStereoToMono() throws {
        let converter = try PersistentAudioConverter()
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 2))
        let buffer = try Self.stereoConstantBuffer(
            format: format,
            frameCount: 1_600,
            left: 0.25,
            right: 0.75
        )

        let output = try converter.convert(buffer)

        XCTAssertGreaterThan(output.count, 0)
        let average = output.reduce(Float(0), +) / Float(output.count)
        XCTAssertEqual(average, 0.5, accuracy: 0.05)
    }

    func testChunkedConversionMatchesWholeBufferConversion() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let totalFrameCount = 48_000
        let chunkFrameCount = 4_800

        let wholeConverter = try PersistentAudioConverter()
        var wholeOutput = try wholeConverter.convert(
            Self.sineBuffer(format: format, frameCount: totalFrameCount)
        )
        wholeOutput.append(contentsOf: try wholeConverter.finish())

        let chunkedConverter = try PersistentAudioConverter()
        var chunkedOutput = ContiguousArray<Float>()
        for startFrame in stride(from: 0, to: totalFrameCount, by: chunkFrameCount) {
            chunkedOutput.append(
                contentsOf: try chunkedConverter.convert(
                    Self.sineBuffer(
                        format: format,
                        frameCount: chunkFrameCount,
                        startFrame: startFrame
                    )
                )
            )
        }
        chunkedOutput.append(contentsOf: try chunkedConverter.finish())

        XCTAssertEqual(chunkedOutput.count, wholeOutput.count, accuracy: 8)
        XCTAssertLessThan(
            Self.rootMeanSquareDifference(chunkedOutput, wholeOutput),
            0.05
        )
    }

    func testTenMinuteChunkedConversionKeepsSampleCountDriftWithinOneFrame() throws {
        let sourceSampleRate = 48_000.0
        let targetSampleRate = 16_000.0
        let durationSeconds = 10 * 60
        let chunkFrameCount = 4_800
        let totalFrameCount = Int(sourceSampleRate) * durationSeconds
        let expectedOutputCount = Int(targetSampleRate) * durationSeconds
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sourceSampleRate, channels: 1))
        let converter = try PersistentAudioConverter(targetSampleRate: targetSampleRate)
        var convertedSampleCount = 0

        for startFrame in stride(from: 0, to: totalFrameCount, by: chunkFrameCount) {
            let remaining = totalFrameCount - startFrame
            let frameCount = min(chunkFrameCount, remaining)
            convertedSampleCount += try converter.convert(
                Self.sineBuffer(
                    format: format,
                    frameCount: frameCount,
                    startFrame: startFrame
                )
            ).count
        }
        convertedSampleCount += try converter.finish().count

        XCTAssertEqual(convertedSampleCount, expectedOutputCount, accuracy: 1)
        XCTAssertEqual(converter.convertedOutputSampleCount, convertedSampleCount)
    }

    private static func sineBuffer(
        format: AVAudioFormat,
        frameCount: Int,
        startFrame: Int = 0
    ) throws -> AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            )
        )
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channelCount = Int(format.channelCount)
        let frequency: Float = 440
        for channelIndex in 0..<channelCount {
            let channel = try XCTUnwrap(buffer.floatChannelData?[channelIndex])
            for frameIndex in 0..<frameCount {
                let absoluteFrameIndex = startFrame + frameIndex
                channel[frameIndex] = sin(
                    2 * .pi * frequency * Float(absoluteFrameIndex) / Float(format.sampleRate)
                )
            }
        }
        return buffer
    }

    private static func stereoConstantBuffer(
        format: AVAudioFormat,
        frameCount: Int,
        left: Float,
        right: Float
    ) throws -> AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            )
        )
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let leftChannel = try XCTUnwrap(buffer.floatChannelData?[0])
        let rightChannel = try XCTUnwrap(buffer.floatChannelData?[1])
        for frameIndex in 0..<frameCount {
            leftChannel[frameIndex] = left
            rightChannel[frameIndex] = right
        }
        return buffer
    }

    private static func rootMeanSquareDifference(
        _ lhs: ContiguousArray<Float>,
        _ rhs: ContiguousArray<Float>
    ) -> Float {
        let count = min(lhs.count, rhs.count)
        guard count > 0 else { return .infinity }
        var sum: Float = 0
        for index in 0..<count {
            let difference = lhs[index] - rhs[index]
            sum += difference * difference
        }
        return sqrt(sum / Float(count))
    }
}
