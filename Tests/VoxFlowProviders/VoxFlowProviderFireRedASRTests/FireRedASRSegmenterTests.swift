import Foundation
@testable import VoxFlowProviderFireRedASR
import XCTest

final class FireRedASRSegmenterTests: XCTestCase {
    private let sampleRate = 16_000

    func testEmptyAudioProducesNoSegments() {
        XCTAssertTrue(FireRedASRSegmenter.segments(samples: [], sampleRate: sampleRate).isEmpty)
    }

    func testShortAudioIsASingleNonHardCutSegment() {
        let samples = Self.loud(count: 10 * sampleRate)
        let segments = FireRedASRSegmenter.segments(samples: samples, sampleRate: sampleRate)

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].range, 0..<samples.count)
        XCTAssertFalse(segments[0].isHardCut)
    }

    func testAudioExactlyAtTheLimitIsNotSplit() {
        let samples = Self.loud(count: FireRedASRSegmenter.maximumSegmentSeconds * sampleRate)
        let segments = FireRedASRSegmenter.segments(samples: samples, sampleRate: sampleRate)

        XCTAssertEqual(segments.count, 1)
        XCTAssertFalse(segments[0].isHardCut)
    }

    func testLongAudioIsCutOnSilenceAndNeverExceedsTheLimit() {
        // 144 s 音频，在 ~47 s 与 ~94.5 s 各放一段静音，两处都落在各自窗口的搜索区内。
        let totalSeconds = 144
        var samples = Self.loud(count: totalSeconds * sampleRate)
        Self.silence(&samples, seconds: 46.5..<48.0, sampleRate: sampleRate)
        Self.silence(&samples, seconds: 94.0..<95.5, sampleRate: sampleRate)

        let segments = FireRedASRSegmenter.segments(samples: samples, sampleRate: sampleRate)

        XCTAssertEqual(segments.count, 3)
        XCTAssertTrue(segments.allSatisfy { !$0.isHardCut }, "静音切点应该被找到，不应发生降级")
        let limit = FireRedASRSegmenter.maximumSegmentSeconds * sampleRate
        XCTAssertTrue(segments.allSatisfy { $0.range.count <= limit })
        XCTAssertEqual(segments.first?.range.lowerBound, 0)
        XCTAssertEqual(segments.last?.range.upperBound, samples.count)
        // 段首尾相接，不丢样本也不重复。
        for (previous, next) in zip(segments, segments.dropFirst()) {
            XCTAssertEqual(previous.range.upperBound, next.range.lowerBound)
        }
    }

    func testLongAudioWithoutAnySilenceFallsBackToHardCutAndSaysSo() {
        let samples = Self.loud(count: 130 * sampleRate)
        let segments = FireRedASRSegmenter.segments(samples: samples, sampleRate: sampleRate)

        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments.map(\.range.count), [800_000, 800_000, 480_000])
        // 前两段是被迫硬切的；最后一段本来就短于门限，不算切。
        XCTAssertEqual(segments.map(\.isHardCut), [true, true, false])
        XCTAssertEqual(segments.last?.range.upperBound, samples.count)
    }

    func testQuietestFrameBoundaryPrefersTheSilentFrame() {
        var samples = Self.loud(count: 1_000)
        Self.silence(&samples, seconds: 0.02..<0.04, sampleRate: 1_000)

        let boundary = FireRedASRSegmenter.quietestFrameBoundary(
            in: samples,
            searchStart: 0,
            searchEnd: 1_000,
            frameLength: 20
        )

        XCTAssertEqual(boundary, 20)
    }

    func testQuietestFrameBoundaryReturnsNilWhenNothingIsQuiet() {
        let samples = Self.loud(count: 1_000)
        XCTAssertNil(
            FireRedASRSegmenter.quietestFrameBoundary(
                in: samples,
                searchStart: 0,
                searchEnd: 1_000,
                frameLength: 20
            )
        )
    }

    // MARK: - Helpers

    private static func loud(count: Int, amplitude: Float = 0.5) -> [Float] {
        [Float](repeating: amplitude, count: count)
    }

    private static func silence(
        _ samples: inout [Float],
        seconds: Range<Double>,
        sampleRate: Int
    ) {
        let lower = max(Int(seconds.lowerBound * Double(sampleRate)), 0)
        let upper = min(Int(seconds.upperBound * Double(sampleRate)), samples.count)
        guard lower < upper else { return }
        for index in lower..<upper {
            samples[index] = 0
        }
    }
}
