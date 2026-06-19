import Foundation
import VoxFlowAudio

enum ASRSmokeAudio {
    static func loadFrames(
        for sample: ASRSmokeSample,
        frameSampleCount: Int = 1_600,
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> [AudioFrame] {
        let url = resolveAudioURL(sample.audioPath, currentDirectory: currentDirectory)
        let wav = try PCM16WAV(data: Data(contentsOf: url))
        precondition(wav.sampleRate == 16_000, "ASR smoke WAV files must be 16 kHz")
        precondition(wav.channelCount == 1, "ASR smoke WAV files must be mono")

        return stride(from: 0, to: wav.samples.count, by: frameSampleCount).enumerated().map { index, offset in
            let end = min(offset + frameSampleCount, wav.samples.count)
            return AudioFrame(
                sequenceNumber: UInt64(index + 1),
                startSample: UInt64(offset),
                samples: ContiguousArray(wav.samples[offset..<end]),
                sampleRate: wav.sampleRate,
                capturedAt: ContinuousClock.now
            )
        }
    }

    private static func resolveAudioURL(
        _ path: String,
        currentDirectory: URL
    ) -> URL {
        let directURL = currentDirectory.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: directURL.path) {
            return directURL
        }
        return currentDirectory
            .appendingPathComponent("TestResources")
            .appendingPathComponent("ASRSmoke")
            .appendingPathComponent("Audio")
            .appendingPathComponent(path)
    }
}

private struct PCM16WAV {
    let sampleRate: Int
    let channelCount: Int
    let samples: [Float]

    init(data: Data) throws {
        guard data.count >= 44,
              data.asciiString(at: 0, length: 4) == "RIFF",
              data.asciiString(at: 8, length: 4) == "WAVE" else {
            throw ASRSmokeAudioError.invalidWAVHeader
        }

        var offset = 12
        var sampleRate: Int?
        var channelCount: Int?
        var bitsPerSample: Int?
        var audioFormat: Int?
        var dataRange: Range<Int>?

        while offset + 8 <= data.count {
            let chunkID = data.asciiString(at: offset, length: 4)
            let chunkSize = Int(data.uint32LE(at: offset + 4))
            let chunkStart = offset + 8
            let chunkEnd = chunkStart + chunkSize
            guard chunkEnd <= data.count else {
                throw ASRSmokeAudioError.invalidWAVChunk
            }

            switch chunkID {
            case "fmt ":
                guard chunkSize >= 16 else {
                    throw ASRSmokeAudioError.invalidFormatChunk
                }
                audioFormat = Int(data.uint16LE(at: chunkStart))
                channelCount = Int(data.uint16LE(at: chunkStart + 2))
                sampleRate = Int(data.uint32LE(at: chunkStart + 4))
                bitsPerSample = Int(data.uint16LE(at: chunkStart + 14))
            case "data":
                dataRange = chunkStart..<chunkEnd
            default:
                break
            }

            offset = chunkEnd + (chunkSize % 2)
        }

        guard audioFormat == 1,
              bitsPerSample == 16,
              let sampleRate,
              let channelCount,
              channelCount == 1,
              let dataRange else {
            throw ASRSmokeAudioError.unsupportedWAVFormat
        }

        self.sampleRate = sampleRate
        self.channelCount = channelCount
        var samples: [Float] = []
        samples.reserveCapacity(dataRange.count / 2)
        var sampleOffset = dataRange.lowerBound
        while sampleOffset + 1 < dataRange.upperBound {
            let sample = Int16(bitPattern: data.uint16LE(at: sampleOffset))
            samples.append(Float(sample) / Float(Int16.max))
            sampleOffset += 2
        }
        self.samples = samples
    }
}

private enum ASRSmokeAudioError: Error {
    case invalidWAVHeader
    case invalidWAVChunk
    case invalidFormatChunk
    case unsupportedWAVFormat
}

private extension Data {
    func asciiString(at offset: Int, length: Int) -> String {
        String(decoding: self[offset..<(offset + length)], as: UTF8.self)
    }

    func uint16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(uint16LE(at: offset)) | (UInt32(uint16LE(at: offset + 2)) << 16)
    }
}
