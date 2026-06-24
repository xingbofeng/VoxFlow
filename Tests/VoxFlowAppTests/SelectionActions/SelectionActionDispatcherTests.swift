import XCTest
@testable import VoxFlowApp

final class SelectionActionDispatcherTests: XCTestCase {
    func testTranslateActionRoutesToTextTransformTranslation() {
        let route = SelectionActionDispatcher().route(action: .translate, selectedText: "hello")

        XCTAssertEqual(route, .textTransform(.translation, text: "hello"))
    }

    func testSummarizeActionRoutesToTextTransformSummary() {
        let route = SelectionActionDispatcher().route(action: .summarize, selectedText: "long note")

        XCTAssertEqual(route, .textTransform(.summary, text: "long note"))
    }

    func testAgentActionRoutesToAgentContext() {
        let route = SelectionActionDispatcher().route(action: .agent, selectedText: "fix this")

        XCTAssertEqual(route, .agentContext(text: "fix this"))
    }
}
