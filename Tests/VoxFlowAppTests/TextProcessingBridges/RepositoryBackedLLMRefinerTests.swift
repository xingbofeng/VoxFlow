import XCTest
@testable import VoxFlowApp

final class RepositoryBackedLLMRefinerTests: XCTestCase {
    func testRefineUsesEnabledDefaultProviderConfiguration() async throws {
        let credentials = TestCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(credentialStore: credentials)
        )
        let provider = makeProvider(isDefault: true)
        try environment.llmProviderRepository.save(provider)
        try credentials.saveCredential("secret", account: provider.apiKeyRef)
        let session = CapturingCompletionSession(
            response: Self.completionResponse("修正后")
        )
        let defaults = UserDefaults(suiteName: "RepositoryBackedLLMRefinerTests")!
        defaults.removePersistentDomain(forName: "RepositoryBackedLLMRefinerTests")
        defaults.set(true, forKey: RepositoryBackedLLMRefiner.enabledDefaultsKey)
        let refiner = RepositoryBackedLLMRefiner(
            providerRepository: environment.llmProviderRepository,
            credentialStore: credentials,
            defaults: defaults,
            session: session
        )

        let result = try await refiner.refine(
            TextRefinementRequest(
                text: "原文",
                systemPrompt: "系统提示",
                model: "style-model",
                temperature: 0.9
            )
        )

        XCTAssertEqual(result, "修正后")
        let request = try XCTUnwrap(session.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(request.timeoutInterval, 13)
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        )
        XCTAssertEqual(body["model"] as? String, "style-model")
        XCTAssertEqual(body["temperature"] as? Double, 0.9)
        XCTAssertNil(body["max_tokens"])
        XCTAssertEqual(refiner.lastTrace?.providerID, "global")
        XCTAssertEqual(refiner.lastTrace?.providerName, "OpenAI")
        XCTAssertEqual(refiner.lastTrace?.endpoint, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(refiner.lastTrace?.model, "style-model")
        XCTAssertEqual(refiner.lastTrace?.temperature, 0.9)
        XCTAssertEqual(refiner.lastTrace?.statusCode, 200)
        XCTAssertEqual(refiner.lastTrace?.responseText, "修正后")
        XCTAssertEqual(refiner.lastTrace?.errorMessage, nil)
        XCTAssertTrue(refiner.lastTrace?.requestBodyJSON.contains("\"messages\"") == true)
    }

    func testRefineStreamUsesInjectedSessionAndRequestsStreaming() async throws {
        let credentials = TestCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(credentialStore: credentials)
        )
        let provider = makeProvider(isDefault: true)
        try environment.llmProviderRepository.save(provider)
        try credentials.saveCredential("secret", account: provider.apiKeyRef)
        let session = CapturingCompletionSession(
            response: Self.completionResponse("unused"),
            streamChunks: [
                #"data: {"choices":[{"delta":{"content":"修"}}]}"# + "\n\n",
                #"data: {"choices":[{"delta":{"content":"正"}}]}"# + "\n\n",
                "data: [DONE]\n\n",
            ]
        )
        let defaults = UserDefaults(suiteName: "RepositoryBackedLLMRefinerTests.stream")!
        defaults.removePersistentDomain(forName: "RepositoryBackedLLMRefinerTests.stream")
        defaults.set(true, forKey: RepositoryBackedLLMRefiner.enabledDefaultsKey)
        let refiner = RepositoryBackedLLMRefiner(
            providerRepository: environment.llmProviderRepository,
            credentialStore: credentials,
            defaults: defaults,
            session: session
        )

        var snapshots: [String] = []
        for try await snapshot in refiner.refineStream(
            TextRefinementRequest(
                text: "原文",
                systemPrompt: "系统提示",
                model: nil,
                temperature: nil
            )
        ) {
            snapshots.append(snapshot)
        }

        XCTAssertEqual(snapshots, ["修", "修正"])
        XCTAssertTrue(session.usedStreamingEndpoint)
        let request = try XCTUnwrap(session.streamRequests.first)
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        )
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual(refiner.lastTrace?.responseText, "修正")
    }

    func testNoEnabledDefaultProviderIsNotConfigured() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let defaults = UserDefaults(suiteName: "RepositoryBackedLLMRefinerTests.empty")!
        defaults.removePersistentDomain(forName: "RepositoryBackedLLMRefinerTests.empty")
        defaults.set(true, forKey: RepositoryBackedLLMRefiner.enabledDefaultsKey)
        let refiner = RepositoryBackedLLMRefiner(
            providerRepository: environment.llmProviderRepository,
            credentialStore: environment.credentialStore,
            defaults: defaults
        )

        XCTAssertFalse(refiner.isConfigured)
    }

    private func makeProvider(isDefault: Bool) -> LLMProviderRecord {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return LLMProviderRecord(
            id: "global",
            displayName: "OpenAI",
            providerType: "openaiCompatible",
            baseURL: "https://api.example.com/v1",
            defaultModel: "global-model",
            apiKeyRef: "global-key",
            temperature: 0.25,
            timeoutSeconds: 13,
            enabled: true,
            isDefault: isDefault,
            lastHealthStatus: nil,
            lastHealthMessage: nil,
            lastLatencyMS: nil,
            createdAt: date,
            updatedAt: date
        )
    }

    private static func completionResponse(_ text: String) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": text]]]
        ])
    }
}

private final class TestCredentialStore: CredentialStore {
    private var values: [String: String] = [:]

    func readCredential(account: String) throws -> String? { values[account] }
    func saveCredential(_ value: String, account: String) throws { values[account] = value }
    func deleteCredential(account: String) throws { values.removeValue(forKey: account) }
}

private final class CapturingCompletionSession: LLMCompletionSession, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private(set) var streamRequests: [URLRequest] = []
    let response: Data
    let streamChunks: [String]

    var usedStreamingEndpoint: Bool {
        !streamRequests.isEmpty
    }

    init(response: Data, streamChunks: [String] = []) {
        self.response = response
        self.streamChunks = streamChunks
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return (
            response,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }

    func byteStream(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse) {
        streamRequests.append(request)
        let chunks = streamChunks
        let stream = AsyncThrowingStream<UInt8, Error> { continuation in
            Task {
                for chunk in chunks {
                    for byte in chunk.utf8 {
                        continuation.yield(byte)
                    }
                }
                continuation.finish()
            }
        }
        return (
            stream,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}
