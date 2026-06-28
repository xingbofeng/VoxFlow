import Foundation
import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

/// Tests for HotwordHitCounter — non-overlapping occurrence counting,
/// case-insensitivity, CJK, multi-word overlap, and final-text-only semantics.
///
/// Covers tasks 4.1, 4.2, 4.6 from redesign-vocabulary-hotwords-learning.
final class HotwordHitCounterTests: XCTestCase {
    private var queue: DatabaseQueue!
    private var repository: SQLiteCorrectionTargetRepository!
    private var counter: HotwordHitCounter!

    override func setUpWithError() throws {
        try super.setUpWithError()
        queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        repository = SQLiteCorrectionTargetRepository(databaseQueue: queue)
        counter = HotwordHitCounter(repository: repository)
    }

    override func tearDown() {
        counter = nil
        repository = nil
        queue = nil
        super.tearDown()
    }

    // MARK: - Task 4.2: Non-overlapping count

    func testCountsNonOverlappingOccurrences() throws {
        try repository.save(makeHotword(text: "VoxFlow"))
        let summary = counter.recordHits(in: "VoxFlow is great, VoxFlow rocks")
        XCTAssertEqual(summary.totalOccurrences, 2)
        XCTAssertEqual(summary.hits.first?.count, 2)

        let updated = try repository.listHotwords().first!
        XCTAssertEqual(updated.hitCount, 2)
        XCTAssertNotNil(updated.lastHitAt)
    }

    func testCaseInsensitiveMatching() throws {
        try repository.save(makeHotword(text: "Qwen3-ASR"))
        let summary = counter.recordHits(in: "qwen3-asr and QWEN3-ASR and Qwen3-Asr")
        XCTAssertEqual(summary.totalOccurrences, 3)
    }

    func testCJKHotwordCountedCorrectly() throws {
        try repository.save(makeHotword(text: "字幕学习"))
        let summary = counter.recordHits(in: "今天字幕学习了很多，字幕学习真好")
        XCTAssertEqual(summary.totalOccurrences, 2)
    }

    // MARK: - Task 4.6: Multi-word overlap

    func testOverlappingOccurrencesDoNotDoubleCount() {
        let count = HotwordHitCounter.countNonOverlappingOccurrences(
            of: "aa",
            in: "aaaa"
        )
        // "aaaa" contains "aa" at position 0 and position 2 (non-overlapping)
        XCTAssertEqual(count, 2)
    }

    func testNestedHotwordsCountedIndependently() throws {
        try repository.save(makeHotword(text: "VoxFlow"))
        try repository.save(makeHotword(text: "VoxFlow App"))
        let summary = counter.recordHits(in: "VoxFlow App is the VoxFlow App I use")
        // Both "VoxFlow" and "VoxFlow App" should be counted
        // "VoxFlow" appears in "VoxFlow App" too — this is expected per spec
        // (non-overlapping only applies within a single term's scan)
        XCTAssertTrue(summary.hits.contains { $0.term == "VoxFlow App" && $0.count == 2 })
    }

    // MARK: - Task 35: Final text only, not raw

    func testEmptyFinalTextReturnsEmptySummary() {
        let summary = counter.recordHits(in: "")
        XCTAssertEqual(summary, .empty)
    }

    func testNoHotwordsReturnsEmptySummary() {
        let summary = counter.recordHits(in: "some text")
        XCTAssertEqual(summary, .empty)
    }

    func testHitCountAccumulatesAcrossCalls() throws {
        try repository.save(makeHotword(text: "ContextBoost"))
        _ = counter.recordHits(in: "ContextBoost here")
        _ = counter.recordHits(in: "ContextBoost again and ContextBoost once more")
        let updated = try repository.listHotwords().first!
        XCTAssertEqual(updated.hitCount, 3)
    }

    func testUnmatchedHotwordNotCounted() throws {
        try repository.save(makeHotword(text: "PostgreSQL"))
        let summary = counter.recordHits(in: "I use MySQL today")
        XCTAssertEqual(summary.totalOccurrences, 0)
        let updated = try repository.listHotwords().first!
        XCTAssertEqual(updated.hitCount, 0)
        XCTAssertNil(updated.lastHitAt)
    }

    // MARK: - Task 4.4: Sorting (verified via repository)

    func testHotwordsSortedByHitCountAfterRecording() throws {
        try repository.save(makeHotword(text: "Low"))
        try repository.save(makeHotword(text: "High"))
        try repository.save(makeHotword(text: "Mid"))

        _ = counter.recordHits(in: "High High High")
        _ = counter.recordHits(in: "Mid Mid")
        _ = counter.recordHits(in: "Low")

        let sorted = try repository.listHotwords()
        XCTAssertEqual(sorted.map(\.text), ["High", "Mid", "Low"])
    }

    // MARK: - Helpers

    private func makeHotword(text: String) -> CorrectionTargetTerm {
        CorrectionTargetTerm(text: text, lifecycle: .active, source: .manual)
    }
}
