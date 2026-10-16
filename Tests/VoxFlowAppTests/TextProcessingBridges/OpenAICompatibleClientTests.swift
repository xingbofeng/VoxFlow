import XCTest
@testable import VoxFlowApp

final class OpenAICompatibleClientTests: XCTestCase {
    func testNormalizesBaseURLAndBuildsChatEndpoint() throws {
        XCTAssertEqual(
            try OpenAICompatibleClient.normalizedBaseURL(" https://api.example.com/v1/ "),
            "https://api.example.com/v1"
        )
        XCTAssertEqual(
            try OpenAICompatibleClient.chatCompletionsURL(baseURL: "https://api.example.com/v1").absoluteString,
            "https://api.example.com/v1/chat/completions"
        )
    }

    func testConnectionSendsBearerTokenAndParsesSuccess() async throws {
        let session = StubOpenAISession(
            data: Data(#"{"choices":[{"message":{"content":"OK"}}]}"#.utf8),
            statusCode: 200
        )
        let client = OpenAICompatibleClient(session: session)

        let result = try await client.testConnection(
            baseURL: "https://api.example.com",
            apiKey: "secret",
            model: "model-a",
            timeoutSeconds: 3
        )

        XCTAssertEqual(result.message, "连接成功")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertTrue(session.lastRequest?.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("VoxFlow/") == true)
        XCTAssertEqual(session.lastRequest?.url?.absoluteString, "https://api.example.com/v1/chat/completions")
    }

    func testModelListParsesModelIDs() async throws {
        let session = StubOpenAISession(
            data: Data(#"{"data":[{"id":"models/gemini-2.5-flash"},{"id":"openai/gpt-oss-120b"}]}"#.utf8),
            statusCode: 200
        )
        let client = OpenAICompatibleClient(session: session)

        let models = try await client.listModels(
            baseURL: "https://api.example.com/v1",
            apiKey: "secret",
            timeoutSeconds: 3
        )

        XCTAssertEqual(models, ["gemini-2.5-flash", "openai/gpt-oss-120b"])
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.absoluteString, "https://api.example.com/v1/models")
    }

    func testOpenRouterRequestsIncludeRecommendedHeaders() async throws {
        let session = StubOpenAISession(
            data: Data(#"{"data":[{"id":"openai/gpt-oss-120b:free"}]}"#.utf8),
            statusCode: 200
        )
        let client = OpenAICompatibleClient(session: session)

        _ = try await client.listModels(
            baseURL: "https://openrouter.ai/api/v1",
            apiKey: "secret",
            timeoutSeconds: 3
        )

        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "HTTP-Referer"), "https://mashangxie.app")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "X-Title"), "VoxFlow")
    }

    func testGitHubModelsUsesInferenceEndpointAndHeaders() async throws {
        XCTAssertEqual(
            try OpenAICompatibleClient.chatCompletionsURL(baseURL: "https://models.github.ai/inference").absoluteString,
            "https://models.github.ai/inference/chat/completions"
        )
        let session = StubOpenAISession(
            data: Data(#"{"choices":[{"message":{"content":"OK"}}]}"#.utf8),
            statusCode: 200
        )
        let client = OpenAICompatibleClient(session: session)

        _ = try await client.testConnection(
            baseURL: "https://models.github.ai/inference",
            apiKey: "secret",
            model: "openai/gpt-4.1",
            timeoutSeconds: 3
        )

        XCTAssertEqual(session.lastRequest?.url?.absoluteString, "https://models.github.ai/inference/chat/completions")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(session.lastRequest?.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
    }

    func testProviderSpecificErrorsAreActionable() async throws {
        let githubClient = OpenAICompatibleClient(
            session: StubOpenAISession(
                data: Data(#"{"error":{"message":"No access to model: openai/gpt-4.1"}}"#.utf8),
                statusCode: 403
            )
        )
        do {
            _ = try await githubClient.testConnection(
                baseURL: "https://models.github.ai/inference",
                apiKey: "secret",
                model: "openai/gpt-4.1",
                timeoutSeconds: 3
            )
            XCTFail("Expected GitHub Models access error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("GitHub Models"))
            XCTAssertTrue(error.localizedDescription.contains("模型访问权限"))
        }

        let huggingFaceClient = OpenAICompatibleClient(
            session: StubOpenAISession(
                data: Data(#"{"error":"This authentication method does not have sufficient permissions to call Inference Providers on behalf of user Counterxing"}"#.utf8),
                statusCode: 403
            )
        )
        do {
            _ = try await huggingFaceClient.testConnection(
                baseURL: "https://router.huggingface.co/v1",
                apiKey: "secret",
                model: "Qwen/Qwen3-Coder-Next",
                timeoutSeconds: 3
            )
            XCTFail("Expected Hugging Face permission error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Hugging Face token"))
            XCTAssertTrue(error.localizedDescription.contains("Inference Providers"))
        }

        let opencodeClient = OpenAICompatibleClient(
            session: StubOpenAISession(
                data: Data(#"{"error":{"message":"Insufficient balance. Manage your billing here."}}"#.utf8),
                statusCode: 401
            )
        )
        do {
            _ = try await opencodeClient.testConnection(
                baseURL: "https://opencode.ai/zen/v1",
                apiKey: "secret",
                model: "mimo-v2.5-free",
                timeoutSeconds: 3
            )
            XCTFail("Expected OpenCode balance error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("OpenCode Zen"))
            XCTAssertTrue(error.localizedDescription.contains("余额不足"))
        }
    }

    func testArrearsErrorIsReportedAsAccountBalance() async throws {
        // 真实报文：DeepSeek 系模型在腾讯 tokenhub 欠费时返回 402，正文带 "API Key" 字样，
        // 上层曾据此把它误判成「未配置 API 密钥」。
        let client = OpenAICompatibleClient(
            session: StubOpenAISession(
                data: Data(#"{"error":{"message":"The account associated with the API Key is in arrears and the accessed service ID has been isolated. Please top up the account and re-enable the service in the console."}}"#.utf8),
                statusCode: 402
            )
        )
        do {
            _ = try await client.testConnection(
                baseURL: "https://tokenhub.tencentmaas.com/v1",
                apiKey: "secret",
                model: "deepseek-v4-flash-202605",
                timeoutSeconds: 3
            )
            XCTFail("Expected account balance error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("余额不足"))
            XCTAssertFalse(error.localizedDescription.contains("API Key"))
        }
    }

    func testPaymentRequiredWithoutStandardErrorBodyStillExplainsAccountBalance() async throws {
        for body in [Data(), Data("Payment required".utf8), Data(#"{"message":"quota depleted"}"#.utf8)] {
            let client = OpenAICompatibleClient(session: StubOpenAISession(data: body, statusCode: 402))
            do {
                _ = try await client.testConnection(
                    baseURL: "https://provider.example/v1", apiKey: "secret", model: "model", timeoutSeconds: 3
                )
                XCTFail("Expected payment-required error")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains(L10n.localize("llm.refiner.error.account_balance")))
            }
        }
    }

    func testNormalizesGoogleModelPrefix() {
        XCTAssertEqual(OpenAICompatibleClient.normalizedModelID(" models/gemini-2.5-flash "), "gemini-2.5-flash")
        XCTAssertEqual(OpenAICompatibleClient.normalizedModelID("openai/gpt-oss-120b"), "openai/gpt-oss-120b")
    }

    func testChatCompletionParserAcceptsReasoningFallbackAndContentBlocks() throws {
        XCTAssertEqual(
            try LLMRefiner.parseChatCompletion(Data(#"{"choices":[{"message":{"content":null,"reasoning_content":"OK"}}]}"#.utf8)),
            "OK"
        )
        XCTAssertEqual(
            try LLMRefiner.parseChatCompletion(Data(#"{"choices":[{"message":{"content":[{"type":"text","text":"O"},{"type":"text","text":"K"}]}}]}"#.utf8)),
            "OK"
        )
    }
}

private final class StubOpenAISession: OpenAICompatibleHTTPSession, @unchecked Sendable {
    let data: Data
    let statusCode: Int
    private(set) var lastRequest: URLRequest?

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
