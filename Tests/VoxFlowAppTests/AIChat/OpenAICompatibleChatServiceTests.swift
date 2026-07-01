import XCTest
@testable import VoxFlowApp

final class OpenAICompatibleChatServiceTests: XCTestCase {
    // MARK: - Request body

    func testRequestBodyExcludesSystemPromptAndIncludesMultiTurnMessages() throws {
        let messages = [
            AIChatMessage(role: .user, content: "Q1"),
            AIChatMessage(role: .assistant, content: "A1"),
            AIChatMessage(role: .user, content: "Q2"),
        ]

        let data = try OpenAICompatibleChatService.makeRequestBody(
            messages: messages,
            model: "gpt-4o",
            temperature: 0.7
        )
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(body?["model"] as? String, "gpt-4o")
        XCTAssertEqual(body?["temperature"] as? Double, 0.7)
        XCTAssertEqual(body?["stream"] as? Bool, true)

        let payload = body?["messages"] as? [[String: Any]]
        XCTAssertEqual(payload?.count, 3)
        XCTAssertEqual(payload?.map { $0["role"] as? String }, ["user", "assistant", "user"])
        XCTAssertEqual(payload?.map { $0["content"] as? String }, ["Q1", "A1", "Q2"])
        // 不含任何 system 角色
        XCTAssertFalse(payload?.contains { $0["role"] as? String == "system" } ?? true)
    }

    func testRequestBodyDoesNotIncludeConservativeSystemPromptText() throws {
        let messages = [AIChatMessage(role: .user, content: "解释 SwiftUI @StateObject")]
        let data = try OpenAICompatibleChatService.makeRequestBody(messages: messages, model: "m", temperature: 0)
        let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = body?["messages"] as? [[String: Any]] ?? []
        // 只有一条 user 消息，无 system，且不含纠错 prompt 关键字
        XCTAssertEqual(payload.count, 1)
        XCTAssertEqual(payload.first?["role"] as? String, "user")
        let allContent = payload.compactMap { $0["content"] as? String }.joined()
        XCTAssertFalse(allContent.contains("纠错"))
        XCTAssertFalse(allContent.contains("PromptBuilder"))
    }

    // MARK: - isConfigured

    func testIsConfiguredFalseWhenNoProvider() {
        let service = OpenAICompatibleChatService(
            providerRepository: FakeLLMProviderRepository([]),
            credentialStore: FakeCredentialStore(key: "k")
        )
        XCTAssertFalse(service.isConfigured)
    }

    func testIsConfiguredFalseWhenNoAPIKey() {
        let service = OpenAICompatibleChatService(
            providerRepository: FakeLLMProviderRepository([makeProvider()]),
            credentialStore: FakeCredentialStore(key: nil)
        )
        XCTAssertFalse(service.isConfigured)
    }

    func testIsConfiguredTrueWhenProviderAndKeyExist() {
        let service = OpenAICompatibleChatService(
            providerRepository: FakeLLMProviderRepository([makeProvider()]),
            credentialStore: FakeCredentialStore(key: "sk-test")
        )
        XCTAssertTrue(service.isConfigured)
    }

    func testIsConfiguredTrueWhenOnlyCodexRuntimeProviderExists() {
        let service = OpenAICompatibleChatService(
            providerRepository: FakeLLMProviderRepository([makeCodexProvider()]),
            credentialStore: FakeCredentialStore(key: nil),
            codexClient: FakeCodexPromptClient(response: "ok")
        )

        XCTAssertTrue(service.isConfigured)
    }

    func testStreamResponseUsesCodexCLIForCodexProvider() async throws {
        let codexClient = FakeCodexPromptClient(response: "Codex answer")
        let service = OpenAICompatibleChatService(
            providerRepository: FakeLLMProviderRepository([makeCodexProvider()]),
            credentialStore: FakeCredentialStore(key: nil),
            codexClient: codexClient
        )

        var collected: [String] = []
        for try await text in service.streamResponse(messages: [AIChatMessage(role: .user, content: "hi")]) {
            collected.append(text)
        }

        XCTAssertEqual(collected, ["Codex answer"])
        XCTAssertEqual(codexClient.requests.first?.model, "gpt-5.5")
        XCTAssertTrue(codexClient.requests.first?.prompt.contains("hi") == true)
    }

    // MARK: - Streaming

    func testStreamResponseYieldsAccumulatedText() async throws {
        let session = FakeLLMCompletionSession()
        session.data = Data("""
        data: {"choices":[{"delta":{"content":"Hello"}}]}\n\n\
        data: {"choices":[{"delta":{"content":" World"}}]}\n\n\
        data: [DONE]\n\n
        """.utf8)

        let service = OpenAICompatibleChatService(
            providerRepository: FakeLLMProviderRepository([makeProvider()]),
            credentialStore: FakeCredentialStore(key: "sk-test"),
            session: session
        )

        var collected: [String] = []
        for try await text in service.streamResponse(messages: [AIChatMessage(role: .user, content: "hi")]) {
            collected.append(text)
        }
        XCTAssertEqual(collected, ["Hello", "Hello World"])
    }

    func testStreamResponseThrowsNotConfiguredWhenNoProvider() async {
        let service = OpenAICompatibleChatService(
            providerRepository: FakeLLMProviderRepository([]),
            credentialStore: FakeCredentialStore(key: "sk-test")
        )

        do {
            for try await _ in service.streamResponse(messages: [AIChatMessage(role: .user, content: "hi")]) {}
            XCTFail("应抛出 notConfigured")
        } catch LLMRefiner.Error.notConfigured {
            // 期望
        } catch {
            XCTFail("期望 notConfigured，实际：\(error)")
        }
    }

    func testStreamResponseThrowsHTTPErrorOnNon200() async {
        let session = FakeLLMCompletionSession()
        session.statusCode = 401
        let service = OpenAICompatibleChatService(
            providerRepository: FakeLLMProviderRepository([makeProvider()]),
            credentialStore: FakeCredentialStore(key: "sk-test"),
            session: session
        )

        do {
            for try await _ in service.streamResponse(messages: [AIChatMessage(role: .user, content: "hi")]) {}
            XCTFail("应抛出 httpError")
        } catch LLMRefiner.Error.httpError(let code) {
            XCTAssertEqual(code, 401)
        } catch {
            XCTFail("期望 httpError，实际：\(error)")
        }
    }

    // MARK: - Helpers

    private func makeProvider() -> LLMProviderRecord {
        LLMProviderRecord(
            id: "p1",
            displayName: "Test",
            providerType: "openai",
            baseURL: "https://api.example.com",
            defaultModel: "gpt-4o",
            apiKeyRef: "test-key",
            temperature: 0.7,
            timeoutSeconds: 30,
            enabled: true,
            isDefault: true,
            lastHealthStatus: nil,
            lastHealthMessage: nil,
            lastLatencyMS: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func makeCodexProvider() -> LLMProviderRecord {
        LLMProviderRecord(
            id: AgentProviderRegistry.codex.providerID,
            displayName: "Codex",
            providerType: AgentProviderRegistry.codex.providerID,
            baseURL: "local://codex",
            defaultModel: "gpt-5.5",
            apiKeyRef: "codex-local-runtime",
            temperature: 0,
            timeoutSeconds: 120,
            enabled: true,
            isDefault: true,
            lastHealthStatus: nil,
            lastHealthMessage: nil,
            lastLatencyMS: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - Fakes

private final class FakeLLMProviderRepository: LLMProviderRepository, @unchecked Sendable {
    private let providers: [LLMProviderRecord]
    init(_ providers: [LLMProviderRecord]) { self.providers = providers }
    func save(_ provider: LLMProviderRecord) throws {}
    func provider(id: String) throws -> LLMProviderRecord? { providers.first { $0.id == id } }
    func list() throws -> [LLMProviderRecord] { providers }
    func delete(id: String) throws {}
}

private final class FakeCredentialStore: CredentialStore, @unchecked Sendable {
    private let key: String?
    init(key: String?) { self.key = key }
    func readCredential(account: String) throws -> String? { key }
    func saveCredential(_ value: String, account: String) throws {}
    func deleteCredential(account: String) throws {}
}

private final class FakeLLMCompletionSession: LLMCompletionSession, @unchecked Sendable {
    var data = Data()
    var statusCode = 200

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        (data, response())
    }

    func byteStream(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse) {
        let data = self.data
        let stream: AsyncThrowingStream<UInt8, Error> = AsyncThrowingStream { continuation in
            for byte in data {
                continuation.yield(byte)
            }
            continuation.finish()
        }
        return (stream, response())
    }

    private func response() -> URLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}

private final class FakeCodexPromptClient: CodexPromptCompleting, @unchecked Sendable {
    struct Request: Equatable {
        let prompt: String
        let model: String?
        let timeoutSeconds: Double
    }

    let isAvailable: Bool
    let response: String
    private(set) var requests: [Request] = []

    init(isAvailable: Bool = true, response: String) {
        self.isAvailable = isAvailable
        self.response = response
    }

    func complete(prompt: String, model: String?, timeoutSeconds: Double) async throws -> String {
        requests.append(Request(prompt: prompt, model: model, timeoutSeconds: timeoutSeconds))
        return response
    }
}
