import Foundation
import XCTest
import VoxFlowAudio

final class AudioSegmentStoreTests: XCTestCase {
    func testSegmentStoreWritesFramesIntoDiskSegments() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxFlowAudioSegmentStore-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let store = try AudioSegmentStore(
            directoryURL: directoryURL,
            maxSamplesPerSegment: 4
        )

        try store.append(Self.frame(sequenceNumber: 0, samples: [0.1, 0.2]))
        try store.append(Self.frame(sequenceNumber: 1, samples: [0.3, 0.4, 0.5]))
        try store.append(Self.frame(sequenceNumber: 2, samples: [0.6]))
        let segments = try store.finish()

        XCTAssertEqual(segments.map(\.index), [0, 1])
        XCTAssertEqual(segments.map(\.sampleCount), [2, 4])
        XCTAssertEqual(segments.map(\.frameCount), [1, 2])
        XCTAssertEqual(segments.map(\.startSequenceNumber), [0, 1])
        XCTAssertEqual(segments.map(\.endSequenceNumber), [0, 2])
        XCTAssertEqual(
            try segments.map { try FileManager.default.attributesOfItem(atPath: $0.fileURL.path)[.size] as? Int },
            [2 * MemoryLayout<Float>.size, 4 * MemoryLayout<Float>.size]
        )
    }

    private static func frame(
        sequenceNumber: UInt64,
        samples: ContiguousArray<Float>
    ) -> AudioFrame {
        AudioFrame(
            sequenceNumber: sequenceNumber,
            startSample: sequenceNumber * 16,
            samples: samples,
            sampleRate: 16_000,
            capturedAt: ContinuousClock.now
        )
    }
}
