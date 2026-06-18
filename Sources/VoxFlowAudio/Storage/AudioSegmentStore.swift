import Foundation

public enum AudioSegmentStoreError: Error {
    case couldNotCreateSegment(URL)
    case appendAfterFinish
}

public struct AudioSegmentDescriptor: Equatable, Sendable {
    public let index: Int
    public let fileURL: URL
    public let sampleRate: Int
    public let sampleCount: Int
    public let frameCount: Int
    public let startSequenceNumber: UInt64
    public let endSequenceNumber: UInt64
}

public final class AudioSegmentStore {
    private struct OpenSegment {
        let index: Int
        let fileURL: URL
        let fileHandle: FileHandle
        let sampleRate: Int
        var sampleCount: Int
        var frameCount: Int
        let startSequenceNumber: UInt64
        var endSequenceNumber: UInt64
    }

    public let directoryURL: URL
    public let maxSamplesPerSegment: Int

    private var currentSegment: OpenSegment?
    private var closedSegments: [AudioSegmentDescriptor] = []
    private var isFinished = false

    public init(
        directoryURL: URL,
        maxSamplesPerSegment: Int
    ) throws {
        precondition(maxSamplesPerSegment > 0, "AudioSegmentStore segment capacity must be positive.")
        self.directoryURL = directoryURL
        self.maxSamplesPerSegment = maxSamplesPerSegment
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    deinit {
        try? currentSegment?.fileHandle.close()
    }

    public func append(_ frame: AudioFrame) throws {
        guard !isFinished else {
            throw AudioSegmentStoreError.appendAfterFinish
        }

        if let currentSegment,
           currentSegment.sampleCount > 0,
           currentSegment.sampleCount + frame.samples.count > maxSamplesPerSegment {
            try closeCurrentSegment()
        }

        if currentSegment == nil {
            currentSegment = try openSegment(for: frame)
        }

        try write(frame.samples, to: &currentSegment)
        currentSegment?.sampleCount += frame.samples.count
        currentSegment?.frameCount += 1
        currentSegment?.endSequenceNumber = frame.sequenceNumber
    }

    public func finish() throws -> [AudioSegmentDescriptor] {
        guard !isFinished else {
            return closedSegments
        }

        try closeCurrentSegment()
        isFinished = true
        return closedSegments
    }

    private func openSegment(for frame: AudioFrame) throws -> OpenSegment {
        let index = closedSegments.count
        let fileURL = directoryURL.appendingPathComponent(
            String(format: "segment-%05d.pcmf32", index),
            isDirectory: false
        )
        guard FileManager.default.createFile(atPath: fileURL.path, contents: Data()) else {
            throw AudioSegmentStoreError.couldNotCreateSegment(fileURL)
        }
        return OpenSegment(
            index: index,
            fileURL: fileURL,
            fileHandle: try FileHandle(forWritingTo: fileURL),
            sampleRate: frame.sampleRate,
            sampleCount: 0,
            frameCount: 0,
            startSequenceNumber: frame.sequenceNumber,
            endSequenceNumber: frame.sequenceNumber
        )
    }

    private func write(
        _ samples: ContiguousArray<Float>,
        to segment: inout OpenSegment?
    ) throws {
        guard let fileHandle = segment?.fileHandle else { return }
        let data = samples.withUnsafeBufferPointer { pointer -> Data in
            guard let baseAddress = pointer.baseAddress else { return Data() }
            return Data(
                bytes: baseAddress,
                count: pointer.count * MemoryLayout<Float>.stride
            )
        }
        try fileHandle.write(contentsOf: data)
    }

    private func closeCurrentSegment() throws {
        guard let segment = currentSegment else { return }
        try segment.fileHandle.close()
        closedSegments.append(
            AudioSegmentDescriptor(
                index: segment.index,
                fileURL: segment.fileURL,
                sampleRate: segment.sampleRate,
                sampleCount: segment.sampleCount,
                frameCount: segment.frameCount,
                startSequenceNumber: segment.startSequenceNumber,
                endSequenceNumber: segment.endSequenceNumber
            )
        )
        currentSegment = nil
    }
}
