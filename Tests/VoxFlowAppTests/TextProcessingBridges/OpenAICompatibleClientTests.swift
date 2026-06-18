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
        XCTAssertEqual(session.lastRequest?.url?.absoluteString, "https://api.example.com/v1/chat/completions")
    }

    func testModelListParsesModelIDs() async throws {
        let session = StubOpenAISession(
            data: Data(#"{"data":[{"id":"model-a"},{"id":"model-b"}]}"#.utf8),
            statusCode: 200
        )
        let client = OpenAICompatibleClient(session: session)

        let models = try await client.listModels(
            baseURL: "https://api.example.com/v1",
            apiKey: "secret",
            timeoutSeconds: 3
        )

        XCTAssertEqual(models, ["model-a", "model-b"])
        XCTAssertEqual(session.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(session.lastRequest?.url?.absoluteString, "https://api.example.com/v1/models")
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
