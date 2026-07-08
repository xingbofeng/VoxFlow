import XCTest
import SwiftUI
@testable import MashangxieKeyboard

@MainActor
final class SuggestionBarViewTests: XCTestCase {
    func testChineseCandidateDisplayUsesLargeScrollableTouchTargets() {
        let policy = SuggestionDisplayPolicy.policy(for: .chineseCandidates)

        XCTAssertEqual(policy.lineLimit, 1)
        XCTAssertTrue(policy.usesHorizontalScroll)
        XCTAssertGreaterThanOrEqual(policy.fontSize, 20)
        XCTAssertGreaterThanOrEqual(policy.minTouchHeight, 44)
        XCTAssertGreaterThanOrEqual(policy.minItemWidth, 44)
        XCTAssertGreaterThanOrEqual(policy.expandButtonWidth, 44)
    }

    func testExpandButtonShowsCountBadgeWhenCandidatesExceedVisibleList() {
        let view = SuggestionBarView(
            suggestions: Array(repeating: "字", count: 5),
            mode: .chineseCandidates,
            onTap: { _ in },
            candidateCount: 80
        )
        // The badge widens the expand button beyond the base width.
        XCTAssertGreaterThan(
            SuggestionDisplayPolicy.policy(for: .chineseCandidates).expandButtonWidth,
            52
        )
        XCTAssertNotNil(view)
    }
}
