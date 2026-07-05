import XCTest
@testable import VoxFlowASRRuntime

final class CloudRealtimeASRTranscriptAssemblerTests: XCTestCase {
    func testCombineStablePrefixWithLiveText() {
        XCTAssertEqual(
            CloudRealtimeASRTranscriptAssembler.combine(stablePrefix: "你好", liveText: "世界"),
            "你好世界"
        )
    }

    func testCombineLiveTextPrefixMatchesReturnsLiveText() {
        XCTAssertEqual(
            CloudRealtimeASRTranscriptAssembler.combine(stablePrefix: "你好", liveText: "你好世界"),
            "你好世界"
        )
    }

    func testCombineEmptyStablePrefixReturnsLiveText() {
        XCTAssertEqual(
            CloudRealtimeASRTranscriptAssembler.combine(stablePrefix: "", liveText: "世界"),
            "世界"
        )
    }

    func testJoinedStablePrefixSortsByIndex() {
        let segments = [2: "C", 1: "B", 0: "A"]
        XCTAssertEqual(CloudRealtimeASRTranscriptAssembler.joinedStablePrefix(segments), "ABC")
    }

    func testPCM16EncodingRoundtripMonosilence() {
        let samples: ContiguousArray<Float> = [0, 0, 0, 0]
        let data = PCM16Encoding.pcm16Data(samples: samples)
        XCTAssertEqual(data.count, samples.count * 2)
        // All-zero samples produce all-zero bytes.
        XCTAssertEqual(data, Data(repeating: 0, count: samples.count * 2))
    }
}
