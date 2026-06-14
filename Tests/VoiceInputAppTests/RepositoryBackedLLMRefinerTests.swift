import XCTest
@testable import VoiceInputApp

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
    let response: Data

    init(response: Data) {
        self.response = response
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
}
