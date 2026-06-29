import XCTest
import VoxFlowPromptKit
@testable import VoxFlowApp

/// Tests for task 2.3: confirm the AI style router emits a `StyleRouteTrace`
/// capturing candidates, response, selection, fallback reason and latency,
/// and that the trace flows through `TextProcessingTrace.safeForPersistence`
/// without retaining raw router response.
final class StyleRouteTraceTests: XCTestCase {

    func testClassifyWithTraceRecordsCandidatesResponseAndSelection() async throws {
        let refiner = StubRefiner(response: "builtin.coding", isEnabled: true, isConfigured: true)
        let classifier = LLMApplicationStyleClassifier(refiner: refiner)
        let styles = [
            Self.makeStyle(id: "builtin.chat", enabled: true),
            Self.makeStyle(id: "builtin.coding", enabled: true),
        ]
        let outcome = try await classifier.classifyWithTrace(
            target: DictationTarget(bundleID: "com.apple.dt.Xcode", appName: "Xcode"),
            styles: styles
        )
        XCTAssertEqual(outcome.styleID, "builtin.coding")
        XCTAssertEqual(outcome.trace.candidateStyleIDs, ["builtin.chat", "builtin.coding"])
        XCTAssertEqual(outcome.trace.routerResponse, "builtin.coding")
        XCTAssertEqual(outcome.trace.selectedStyleID, "builtin.coding")
        XCTAssertNil(outcome.trace.fallbackReason)
        XCTAssertEqual(outcome.trace.routerVersion, "1.0.0")
        XCTAssertNotNil(outcome.trace.durationMS)
        XCTAssertFalse(outcome.trace.renderedPromptHash.isEmpty)
    }

    func testClassifyWithTraceRecordsFallbackOnInvalidResponse() async throws {
        let refiner = StubRefiner(response: "我认为应该选择 2", isEnabled: true, isConfigured: true)
        let classifier = LLMApplicationStyleClassifier(refiner: refiner)
        let styles = [Self.makeStyle(id: "builtin.chat", enabled: true)]
        let outcome = try await classifier.classifyWithTrace(
            target: DictationTarget(bundleID: "com.apple.Notes", appName: "Notes"),
            styles: styles
        )
        XCTAssertNil(outcome.styleID)
        XCTAssertNil(outcome.trace.selectedStyleID)
        XCTAssertEqual(outcome.trace.fallbackReason, "invalid_response")
        XCTAssertEqual(outcome.trace.routerResponse, "我认为应该选择 2")
    }

    func testClassifyWithTraceRecordsFallbackOnRequestFailure() async throws {
        let refiner = StubRefiner(response: "", isEnabled: true, isConfigured: true, error: NSError(domain: "net", code: 1))
        let classifier = LLMApplicationStyleClassifier(refiner: refiner)
        let styles = [Self.makeStyle(id: "builtin.chat", enabled: true)]
        let outcome = try await classifier.classifyWithTrace(
            target: DictationTarget(bundleID: "com.apple.Notes", appName: "Notes"),
            styles: styles
        )
        XCTAssertNil(outcome.styleID)
        XCTAssertEqual(outcome.trace.fallbackReason, "request_failed")
        XCTAssertNil(outcome.trace.routerResponse)
        XCTAssertNotNil(outcome.trace.durationMS)
    }

    func testClassifyWithTraceRecordsFallbackWhenRefinerNotReady() async throws {
        let refiner = StubRefiner(response: "", isEnabled: false, isConfigured: false)
        let classifier = LLMApplicationStyleClassifier(refiner: refiner)
        let styles = [Self.makeStyle(id: "builtin.chat", enabled: true)]
        let outcome = try await classifier.classifyWithTrace(
            target: DictationTarget(bundleID: "com.apple.Notes", appName: "Notes"),
            styles: styles
        )
        XCTAssertNil(outcome.styleID)
        XCTAssertEqual(outcome.trace.fallbackReason, "refiner_not_ready")
        XCTAssertEqual(outcome.trace.candidateStyleIDs, ["builtin.chat"])
    }

    func testSafeForPersistenceDropsRawRouterResponse() {
        let route = StyleRouteTrace(
            candidateStyleIDs: ["builtin.chat"],
            routerResponse: "raw model output that might echo user content",
            selectedStyleID: "builtin.chat",
            fallbackReason: nil,
            routerVersion: "1.0.0",
            renderedPromptHash: "h",
            durationMS: 5
        )
        let safe = route.safeForPersistence()
        XCTAssertNil(safe.routerResponse)
        XCTAssertEqual(safe.selectedStyleID, "builtin.chat")
        XCTAssertEqual(safe.candidateStyleIDs, ["builtin.chat"])
        XCTAssertEqual(safe.routerVersion, "1.0.0")
        XCTAssertEqual(safe.durationMS, 5)
    }

    // MARK: - Fixtures

    private static func makeStyle(id: String, enabled: Bool) -> StyleProfileRecord {
        StyleProfileRecord(
            id: id,
            name: id,
            category: "test",
            subtitle: nil,
            mode: "default",
            prompt: "prompt",
            sampleInput: nil,
            sampleOutput: nil,
            llmProviderID: nil,
            model: nil,
            temperature: 0.3,
            enabled: enabled,
            builtIn: false,
            isDefault: false,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private final class StubRefiner: PromptAwareTextRefining, @unchecked Sendable {
    var isEnabled: Bool
    var isConfigured: Bool
    private let response: String
    private let error: Error?

    init(response: String, isEnabled: Bool, isConfigured: Bool, error: Error? = nil) {
        self.response = response
        self.isEnabled = isEnabled
        self.isConfigured = isConfigured
        self.error = error
    }

    func refine(_ text: String) async throws -> String { response }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        if let error { throw error }
        return response
    }
}
