import XCTest
@testable import VoxFlowApp

final class PaletteFileSearchQueryTests: XCTestCase {
    func testEmptyQueryUsesRecentOnlyBudget() {
        let plan = PaletteFileSearchQuery.plan(for: "   ")

        XCTAssertEqual(plan.normalizedQuery, "")
        XCTAssertEqual(plan.strategy, .recentOnly)
        XCTAssertEqual(plan.limit, 20)
        XCTAssertEqual(plan.timeoutMilliseconds, 0)
    }

    func testSingleCharacterQueryUsesPrefixThenContainsBudget() {
        let plan = PaletteFileSearchQuery.plan(for: " 1 ")

        XCTAssertEqual(plan.normalizedQuery, "1")
        XCTAssertEqual(plan.strategy, .prefixThenContains)
        XCTAssertEqual(plan.limit, 30)
        XCTAssertEqual(plan.timeoutMilliseconds, 1_000)
    }

    func testMultiCharacterQueryUsesContainsBudget() {
        let plan = PaletteFileSearchQuery.plan(for: " README ")

        XCTAssertEqual(plan.normalizedQuery, "README")
        XCTAssertEqual(plan.strategy, .contains)
        XCTAssertEqual(plan.limit, 50)
        XCTAssertEqual(plan.timeoutMilliseconds, 1_000)
    }

    func testChineseSingleCharacterUsesSingleCharacterBudget() {
        let plan = PaletteFileSearchQuery.plan(for: "图")

        XCTAssertEqual(plan.normalizedQuery, "图")
        XCTAssertEqual(plan.strategy, .prefixThenContains)
        XCTAssertEqual(plan.limit, 30)
    }
}
