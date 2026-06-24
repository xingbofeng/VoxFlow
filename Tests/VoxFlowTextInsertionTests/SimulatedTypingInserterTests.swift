import VoxFlowTextInsertion
import XCTest

@MainActor
final class SimulatedTypingInserterTests: XCTestCase {
    func testUnicodeEncoderPreservesExtendedGraphemeClusters() {
        let text = "a👨‍👩‍👧‍👦e\u{301}"

        let clusters = UnicodeTypingEncoder().graphemeClusters(in: text)

        XCTAssertEqual(clusters, ["a", "👨‍👩‍👧‍👦", "e\u{301}"])
    }

    func testSimulatedTypingPostsUnicodeClustersInOrder() async {
        let poster = CapturingTypingEventPoster()
        let inserter = SimulatedTypingInserter(
            eventPoster: poster,
            permissionChecker: { true },
            interClusterDelayNanoseconds: 0
        )

        let result = await inserter.insert("你a👨‍👩‍👧‍👦")

        XCTAssertEqual(result, .success)
        XCTAssertEqual(poster.postedTexts, ["你", "a", "👨‍👩‍👧‍👦"])
    }

    func testCancellationStopsBeforeRemainingClustersAndReturnsCancelled() async {
        let cancellationToken = TypingCancellationToken()
        let poster = CapturingTypingEventPoster {
            cancellationToken.cancel()
        }
        let inserter = SimulatedTypingInserter(
            eventPoster: poster,
            permissionChecker: { true },
            cancellationMonitor: cancellationToken,
            interClusterDelayNanoseconds: 0
        )

        let result = await inserter.insert("abc")

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(poster.postedTexts, ["a"])
    }

    func testPermissionFailureReturnsPermissionDeniedWithoutPosting() async {
        let poster = CapturingTypingEventPoster()
        let inserter = SimulatedTypingInserter(
            eventPoster: poster,
            permissionChecker: { false },
            interClusterDelayNanoseconds: 0
        )

        let result = await inserter.insert("hello")

        XCTAssertEqual(result, .permissionDenied)
        XCTAssertTrue(poster.postedTexts.isEmpty)
    }

    func testEventPostFailureReturnsEventCreationFailed() async {
        let poster = CapturingTypingEventPoster(shouldPost: false)
        let inserter = SimulatedTypingInserter(
            eventPoster: poster,
            permissionChecker: { true },
            interClusterDelayNanoseconds: 0
        )

        let result = await inserter.insert("hello")

        XCTAssertEqual(result, .eventCreationFailed)
        XCTAssertEqual(poster.postedTexts, ["h"])
    }
}

@MainActor
private final class CapturingTypingEventPoster: SimulatedTypingEventPosting {
    private let shouldPost: Bool
    private let afterPost: () -> Void
    private(set) var postedTexts: [String] = []

    init(
        shouldPost: Bool = true,
        afterPost: @escaping () -> Void = {}
    ) {
        self.shouldPost = shouldPost
        self.afterPost = afterPost
    }

    func post(_ text: String) -> Bool {
        postedTexts.append(text)
        afterPost()
        return shouldPost
    }
}
