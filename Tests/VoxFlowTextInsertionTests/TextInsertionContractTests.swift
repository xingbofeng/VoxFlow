import XCTest
@testable import VoxFlowTextInsertion

final class TextInsertionContractTests: XCTestCase {
    @MainActor
    func testResultCasesAreStableForOutputMapping() {
        XCTAssertEqual(TextInsertionResult.success, .success)
        XCTAssertEqual(TextInsertionResult.permissionDenied, .permissionDenied)
        XCTAssertEqual(TextInsertionResult.eventCreationFailed, .eventCreationFailed)
        XCTAssertEqual(TextInsertionResult.cancelled, .cancelled)
        XCTAssertEqual(
            TextInsertionResult.unavailable(reason: "missing mode"),
            .unavailable(reason: "missing mode")
        )
    }

    @MainActor
    func testTextInsertingProtocolReturnsInsertionResult() async {
        let inserter = CapturingTextInserter(result: .eventCreationFailed)

        let result = await inserter.insert("hello")

        XCTAssertEqual(result, .eventCreationFailed)
        XCTAssertEqual(inserter.insertedTexts, ["hello"])
    }

    @MainActor
    func testFastPasteTextInserterIsPublicTextInsertingImplementation() {
        let inserter: any TextInserting = FastPasteTextInserter()

        XCTAssertTrue(inserter is FastPasteTextInserter)
    }

    @MainActor
    func testFastPasteTextInserterDisablesSystemInteractionDuringTests() async {
        let inserter = FastPasteTextInserter()

        let result = await inserter.insert("final")

        XCTAssertEqual(
            result,
            .unavailable(reason: "Fast paste system interaction is disabled during tests")
        )
    }

    func testTextInsertionRuntimeEnvironmentDetectsXCTestFromXCTestArguments() {
        XCTAssertTrue(
            TextInsertionRuntimeEnvironment.isRunningUnderXCTest(
                environment: [:],
                arguments: ["/tmp/VoxFlowTextInsertionTests.xctest"],
                bundlePaths: [],
                classExists: { _ in false }
            )
        )
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
