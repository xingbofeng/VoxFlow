import XCTest
@testable import VoxFlowR2T2Core

final class MelTests: XCTestCase {
    func testTokenCountMatchesTheReferenceFormula() {
        // 100 frames → 13 tokens; 75 → 10; 800 → 104; 674 (6.74 s) → 88 (the sample clip).
        XCTAssertEqual(qwen3ASRAudioTokenCount(frames: 100), 13)
        XCTAssertEqual(qwen3ASRAudioTokenCount(frames: 75), 10)
        XCTAssertEqual(qwen3ASRAudioTokenCount(frames: 800), 104)
        XCTAssertEqual(qwen3ASRAudioTokenCount(frames: 674), 88)
        XCTAssertEqual(qwen3ASRAudioTokenCount(frames: 1), 1)
    }
    func testFrameGeometry() {
        let m = WhisperLogMel()
        let (frames, data) = m.features([Float](repeating: 0.01, count: 16000))
        XCTAssertEqual(frames, 100)                // 1 s → 100 frames after the dropped one
        XCTAssertEqual(data.count, 100 * 128)
        XCTAssertTrue(data.allSatisfy { $0.isFinite })
    }
}
