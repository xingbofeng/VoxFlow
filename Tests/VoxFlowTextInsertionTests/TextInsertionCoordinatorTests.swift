import VoxFlowDomain
import VoxFlowTextInsertion
import XCTest

@MainActor
final class TextInsertionCoordinatorTests: XCTestCase {
    func testAutomaticAndFastPasteUseFastPasteInserter() async {
        let fastPaste = CapturingTextInserter(result: .success)
        let simulatedTyping = CapturingTextInserter(result: .success)
        let coordinator = TextInsertionCoordinator(
            fastPasteInserter: fastPaste,
            simulatedTypingInserter: simulatedTyping
        )

        let automaticResult = await coordinator.insert("automatic text", mode: .automatic)
        let fastPasteResult = await coordinator.insert("fast paste text", mode: .fastPaste)

        XCTAssertEqual(automaticResult, .success)
        XCTAssertEqual(fastPasteResult, .success)

        XCTAssertEqual(fastPaste.insertedTexts, ["automatic text", "fast paste text"])
        XCTAssertTrue(simulatedTyping.insertedTexts.isEmpty)
    }

    func testSimulatedTypingUsesSimulatedTypingInserterWhenAvailable() async {
        let fastPaste = CapturingTextInserter(result: .success)
        let simulatedTyping = CapturingTextInserter(result: .cancelled)
        let coordinator = TextInsertionCoordinator(
            fastPasteInserter: fastPaste,
            simulatedTypingInserter: simulatedTyping
        )

        let result = await coordinator.insert("typed text", mode: .simulatedTyping)

        XCTAssertEqual(result, .cancelled)
        XCTAssertTrue(fastPaste.insertedTexts.isEmpty)
        XCTAssertEqual(simulatedTyping.insertedTexts, ["typed text"])
    }

    func testSimulatedTypingFallsBackToFastPasteForMultilineText() async {
        let fastPaste = CapturingTextInserter(result: .success)
        let simulatedTyping = CapturingTextInserter(result: .success)
        let coordinator = TextInsertionCoordinator(
            fastPasteInserter: fastPaste,
            simulatedTypingInserter: simulatedTyping
        )

        let result = await coordinator.insert("第一行\n第二行", mode: .simulatedTyping)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(fastPaste.insertedTexts, ["第一行\n第二行"])
        XCTAssertTrue(simulatedTyping.insertedTexts.isEmpty)
    }

    func testSimulatedTypingWithoutInserterReturnsUnavailableWithoutFastPasteFallback() async {
        let fastPaste = CapturingTextInserter(result: .success)
        let coordinator = TextInsertionCoordinator(fastPasteInserter: fastPaste)

        let result = await coordinator.insert("typed text", mode: .simulatedTyping)

        XCTAssertEqual(result, .unavailable(reason: "Simulated typing is not available yet"))
        XCTAssertTrue(fastPaste.insertedTexts.isEmpty)
    }
}

@MainActor
private final class CapturingTextInserter: TextInserting {
    private let result: TextInsertionResult
    private(set) var insertedTexts: [String] = []

    init(result: TextInsertionResult) {
        self.result = result
    }

    func insert(_ text: String) async -> TextInsertionResult {
        insertedTexts.append(text)
        return result
    }
}
