import XCTest
@testable import VoxFlowApp

final class BatchApplicationClassifierTests: XCTestCase {

    // MARK: - Helpers

    private func makeApp(bundleID: String, name: String, category: AppSystemCategory = .userApplication) -> InstalledApplication {
        InstalledApplication(
            id: bundleID,
            name: name,
            bundleID: bundleID,
            iconPath: nil,
            path: "/Applications/\(name).app",
            systemCategory: category
        )
    }

    private func makeStyle(id: String, name: String, enabled: Bool = true) -> StyleProfileRecord {
        StyleProfileRecord(
            id: id,
            name: name,
            category: "general",
            subtitle: nil,
            mode: "text",
            prompt: "prompt",
            sampleInput: nil,
            sampleOutput: nil,
            llmProviderID: nil,
            model: nil,
            temperature: 0.2,
            enabled: enabled,
            builtIn: true,
            isDefault: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // MARK: - Tests

    func testBatchClassificationSendsMarkdownTableAndSearchInstructions() async throws {
        let refiner = MockPromptAwareRefiner(response: #"{"com.test.app": "builtin.coding"}"#)
        let classifier = LLMBatchApplicationClassifier(refiner: refiner, timeoutSeconds: 5)

        let apps = [makeApp(bundleID: "com.test.app", name: "TestApp")]
        let styles = [makeStyle(id: "builtin.coding", name: "Coding")]

        _ = try await classifier.classifyBatch(apps: apps, enabledStyles: styles)

        let request = refiner.lastRequest
        XCTAssertNotNil(request)
        XCTAssertTrue(request!.text.contains("| App Name | Bundle ID | System Category | Search Query |"))
        XCTAssertTrue(request!.text.contains("| TestApp | com.test.app | userApplication | TestApp com.test.app macOS app what is it used for |"))
        XCTAssertTrue(request!.systemPrompt.contains("search"))
        XCTAssertTrue(request!.systemPrompt.lowercased().contains("web search"))
        XCTAssertTrue(request!.systemPrompt.contains("If search is unavailable"))
        XCTAssertTrue(request!.systemPrompt.contains("without a real text-entry workflow"))
        XCTAssertFalse(request!.systemPrompt.contains("prompt"))
    }

    func testBatchClassificationReturnsValidStyleIDs() async throws {
        let refiner = MockPromptAwareRefiner(response: #"{"com.app.a": "builtin.chat", "com.app.b": "builtin.coding"}"#)
        let classifier = LLMBatchApplicationClassifier(refiner: refiner, timeoutSeconds: 5)

        let apps = [
            makeApp(bundleID: "com.app.a", name: "AppA"),
            makeApp(bundleID: "com.app.b", name: "AppB"),
        ]
        let styles = [
            makeStyle(id: "builtin.chat", name: "Chat"),
            makeStyle(id: "builtin.coding", name: "Coding"),
        ]

        let results = try await classifier.classifyBatch(apps: apps, enabledStyles: styles)

        XCTAssertEqual(results.count, 2)
        let resultMap = Dictionary(results.map { ($0.bundleID, $0.styleID) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(resultMap["com.app.a"], "builtin.chat")
        XCTAssertEqual(resultMap["com.app.b"], "builtin.coding")
    }

    func testBatchClassificationRunsWhenRefinementToggleIsDisabled() async throws {
        let refiner = MockPromptAwareRefiner(
            response: #"{"com.test.app": "builtin.coding"}"#,
            isEnabled: false,
            isConfigured: true
        )
        let classifier = LLMBatchApplicationClassifier(refiner: refiner, timeoutSeconds: 5)

        let results = try await classifier.classifyBatch(
            apps: [makeApp(bundleID: "com.test.app", name: "TestApp")],
            enabledStyles: [makeStyle(id: "builtin.coding", name: "Coding")]
        )

        XCTAssertEqual(results, [
            BatchClassificationResult(bundleID: "com.test.app", styleID: "builtin.coding"),
        ])
        XCTAssertNotNil(refiner.lastRequest)
    }

    func testBatchClassificationSkipsWhenProviderIsNotConfigured() async throws {
        let refiner = MockPromptAwareRefiner(
            response: #"{"com.test.app": "builtin.coding"}"#,
            isEnabled: true,
            isConfigured: false
        )
        let classifier = LLMBatchApplicationClassifier(refiner: refiner, timeoutSeconds: 5)

        let results = try await classifier.classifyBatch(
            apps: [makeApp(bundleID: "com.test.app", name: "TestApp")],
            enabledStyles: [makeStyle(id: "builtin.coding", name: "Coding")]
        )

        XCTAssertTrue(results.isEmpty)
        XCTAssertNil(refiner.lastRequest)
    }

    func testInvalidStyleIDsAreDiscarded() async throws {
        let refiner = MockPromptAwareRefiner(response: #"{"com.app.a": "nonexistent.style", "com.app.b": "builtin.coding"}"#)
        let classifier = LLMBatchApplicationClassifier(refiner: refiner, timeoutSeconds: 5)

        let apps = [
            makeApp(bundleID: "com.app.a", name: "AppA"),
            makeApp(bundleID: "com.app.b", name: "AppB"),
        ]
        let styles = [makeStyle(id: "builtin.coding", name: "Coding")]

        let results = try await classifier.classifyBatch(apps: apps, enabledStyles: styles)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.bundleID, "com.app.b")
        XCTAssertEqual(results.first?.styleID, "builtin.coding")
    }

    func testClassificationFailurePreservesRegistryResults() async throws {
        let refiner = MockFailingRefiner()
        let classifier = LLMBatchApplicationClassifier(refiner: refiner, timeoutSeconds: 5)

        let apps = [makeApp(bundleID: "com.test.app", name: "Test")]
        let styles = [makeStyle(id: "builtin.coding", name: "Coding")]

        do {
            _ = try await classifier.classifyBatch(apps: apps, enabledStyles: styles)
            XCTFail("Expected error")
        } catch {
            // Failure should not affect registry-based results handled elsewhere
            XCTAssertTrue(error is BatchClassificationError || error is MockRefinerError)
        }
    }

    func testTimeoutHandledGracefully() async throws {
        let refiner = MockSlowRefiner(delay: 10)
        let classifier = LLMBatchApplicationClassifier(refiner: refiner, timeoutSeconds: 0.1)

        let apps = [makeApp(bundleID: "com.test.app", name: "Test")]
        let styles = [makeStyle(id: "builtin.coding", name: "Coding")]

        do {
            _ = try await classifier.classifyBatch(apps: apps, enabledStyles: styles)
            XCTFail("Expected timeout error")
        } catch {
            XCTAssertTrue(error is BatchClassificationError)
        }
    }

    func testPartialResultsHandled() async throws {
        let jsonResponse = #"{"com.app.a": "builtin.chat", "com.app.b": "invalid.id", "com.app.c": "builtin.coding"}"#
        let refiner = MockPromptAwareRefiner(response: jsonResponse)
        let classifier = LLMBatchApplicationClassifier(refiner: refiner, timeoutSeconds: 5)

        let apps = [
            makeApp(bundleID: "com.app.a", name: "A"),
            makeApp(bundleID: "com.app.b", name: "B"),
            makeApp(bundleID: "com.app.c", name: "C"),
        ]
        let styles = [
            makeStyle(id: "builtin.chat", name: "Chat"),
            makeStyle(id: "builtin.coding", name: "Coding"),
        ]

        let results = try await classifier.classifyBatch(apps: apps, enabledStyles: styles)

        XCTAssertEqual(results.count, 2)
        let resultMap = Dictionary(results.map { ($0.bundleID, $0.styleID) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(resultMap["com.app.a"], "builtin.chat")
        XCTAssertNil(resultMap["com.app.b"])
        XCTAssertEqual(resultMap["com.app.c"], "builtin.coding")
    }
}

// MARK: - Mocks

private final class MockPromptAwareRefiner: PromptAwareTextRefining, @unchecked Sendable {
    let response: String
    let enabled: Bool
    let configured: Bool
    var lastRequest: TextRefinementRequest?

    init(
        response: String,
        isEnabled: Bool = true,
        isConfigured: Bool = true
    ) {
        self.response = response
        self.enabled = isEnabled
        self.configured = isConfigured
    }

    func refine(_ text: String) async throws -> String {
        response
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        lastRequest = request
        return response
    }

    var isEnabled: Bool { enabled }
    var isConfigured: Bool { configured }
}

private enum MockRefinerError: Error {
    case failed
}

private final class MockFailingRefiner: PromptAwareTextRefining, @unchecked Sendable {
    func refine(_ text: String) async throws -> String {
        throw MockRefinerError.failed
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        throw MockRefinerError.failed
    }

    var isEnabled: Bool { true }
    var isConfigured: Bool { true }
}

private final class MockSlowRefiner: PromptAwareTextRefining, @unchecked Sendable {
    let delay: TimeInterval

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func refine(_ text: String) async throws -> String {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return "{}"
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return "{}"
    }

    var isEnabled: Bool { true }
    var isConfigured: Bool { true }
}
