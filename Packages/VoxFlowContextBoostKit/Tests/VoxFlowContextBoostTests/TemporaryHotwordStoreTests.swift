import XCTest
@testable import VoxFlowContextBoost

final class TemporaryHotwordStoreTests: XCTestCase {
    func testTopKReturnsUnexpiredHotwordsForMatchingScope() async {
        let store = TemporaryHotwordStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let qwen = hotword("Qwen3-ASR", score: 8, expiresAt: now.addingTimeInterval(120))
        let whisper = hotword("WhisperKit", score: 6, expiresAt: now.addingTimeInterval(120))
        await store.put(
            [whisper, qwen],
            scope: .application(bundleID: "com.example.editor"),
            now: now
        )

        let result = await store.topK(
            scope: .application(bundleID: "com.example.editor"),
            limit: 2,
            now: now
        )

        XCTAssertEqual(result.map(\.text), ["Qwen3-ASR", "WhisperKit"])
    }

    func testTopKFallsBackToGlobalScopeWhenApplicationScopeHasNoHotwords() async {
        let store = TemporaryHotwordStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        await store.put(
            [hotword("Claude Code", score: 5, expiresAt: now.addingTimeInterval(120))],
            scope: .global,
            now: now
        )

        let result = await store.topK(
            scope: .application(bundleID: "com.example.editor"),
            limit: 1,
            now: now
        )

        XCTAssertEqual(result.map(\.text), ["Claude Code"])
    }

    func testExpiredHotwordsAreNotReturnedAndCanBePurged() async {
        let store = TemporaryHotwordStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        await store.put(
            [
                hotword("Expired", score: 9, expiresAt: now.addingTimeInterval(-1)),
                hotword("Fresh", score: 4, expiresAt: now.addingTimeInterval(120)),
            ],
            scope: .global,
            now: now
        )

        await store.purgeExpired(now: now)
        let result = await store.topK(scope: .global, limit: 5, now: now)

        XCTAssertEqual(result.map(\.text), ["Fresh"])
    }

    private func hotword(
        _ text: String,
        score: Double,
        expiresAt: Date
    ) -> TemporaryHotword {
        TemporaryHotword(
            text: text,
            normalizedText: text.lowercased(),
            score: score,
            source: .ocrShape,
            evidence: [
                HotwordEvidence(reason: "test", weight: score)
            ],
            expiresAt: expiresAt
        )
    }
}
