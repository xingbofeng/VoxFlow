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

    func testAskAIActionRoutesToAskAIContext() {
        let route = SelectionActionDispatcher().route(action: .askAI, selectedText: "解释这段代码")

        XCTAssertEqual(route, .askAIContext(text: "解释这段代码"))
    }

    func testAskAIContextRouteIsNotAgentContext() {
        let route = SelectionActionDispatcher().route(action: .askAI, selectedText: "这段是什么意思")

        XCTAssertNotEqual(route, .agentContext(text: "这段是什么意思"))
        XCTAssertEqual(route, .askAIContext(text: "这段是什么意思"))
    }

    func testSelectionActionCardPresentationIncludesAskAIDefault() {
        let presentation = SelectionActionCardPresentation(selectedText: "hello")

        XCTAssertEqual(presentation.actions, [.translate, .summarize, .agent, .askAI])
    }
}
