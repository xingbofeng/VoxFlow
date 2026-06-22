import XCTest
@testable import VoxFlowContextBoost

final class HotwordRankerTests: XCTestCase {
    func testRanksByScoreThenStableTextOrder() {
        let ranker = HotwordRanker()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let result = ranker.rank(
            [
                hotword("WhisperKit", score: 5, now: now),
                hotword("Alpha", score: 7, now: now),
                hotword("Apollo", score: 7, now: now),
            ],
            limit: 3
        )

        XCTAssertEqual(result.map(\.text), ["Alpha", "Apollo", "WhisperKit"])
    }

    func testMergesDuplicateNormalizedHotwords() {
        let ranker = HotwordRanker()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let result = ranker.rank(
            [
                hotword("Qwen3-ASR", normalized: "qwen3-asr", score: 4, now: now, reason: "shape"),
                hotword("qwen3-asr", normalized: "qwen3-asr", score: 6, now: now, reason: "rake"),
            ],
            limit: 8
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "qwen3-asr")
        XCTAssertEqual(result[0].score, 10)
        XCTAssertEqual(result[0].evidence.map(\.reason).sorted(), ["rake", "shape"])
    }

    func testDefaultLimitIsEightAndHardCapIsTwelve() {
        let ranker = HotwordRanker()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let hotwords = (0..<20).map { index in
            hotword("Term\(index)", score: Double(100 - index), now: now)
        }

        XCTAssertEqual(ranker.rank(hotwords).count, 8)
        XCTAssertEqual(ranker.rank(hotwords, limit: 30).count, 12)
    }

    private func hotword(
        _ text: String,
        normalized: String? = nil,
        score: Double,
        now: Date,
        reason: String = "test"
    ) -> TemporaryHotword {
        TemporaryHotword(
            text: text,
            normalizedText: normalized ?? text.lowercased(),
            score: score,
            source: .ocrKeyphrase,
            evidence: [HotwordEvidence(reason: reason, weight: score)],
            expiresAt: now.addingTimeInterval(120)
        )
    }
}
