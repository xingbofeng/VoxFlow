import Foundation

protocol OpenAICompatibleHTTPSession: AnyObject, Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: OpenAICompatibleHTTPSession {}

struct LLMProviderConnectionResult: Equatable {
    let message: String
    let latencyMS: Int
}

protocol LLMProviderConnecting: Sendable {
    func testConnection(
        baseURL: String,
        apiKey: String,
        model: String,
        timeoutSeconds: Double
    ) async throws -> LLMProviderConnectionResult

    func listModels(
        baseURL: String,
        apiKey: String,
        timeoutSeconds: Double
    ) async throws -> [String]
}

final class OpenAICompatibleClient: LLMProviderConnecting, @unchecked Sendable {
    private let session: any OpenAICompatibleHTTPSession

    init(session: any OpenAICompatibleHTTPSession = URLSession.shared) {
        self.session = session
    }

    static func normalizedBaseURL(_ baseURL: String) throws -> String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil,
              components.query == nil,
              components.fragment == nil else {
            throw LLMRefiner.Error.invalidURL
        }

        var path = components.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        if path.hasSuffix("/chat/completions") {
            path.removeLast("/chat/completions".count)
        }
        if path == "/" {
            path = ""
        }
        components.path = path

        guard let url = components.url else {
            throw LLMRefiner.Error.invalidURL
        }
        return url.absoluteString
    }

    static func chatCompletionsURL(baseURL: String) throws -> URL {
        try LLMRefiner.chatCompletionsURL(baseURL: normalizedBaseURL(baseURL))
    }

    static func modelsURL(baseURL: String) throws -> URL {
        let normalized = try normalizedBaseURL(baseURL)
        guard var components = URLComponents(string: normalized) else {
            throw LLMRefiner.Error.invalidURL
        }
        var path = components.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        if path == "/" {
            path = ""
        }
        if path.hasSuffix("/v1") {
            components.path = path + "/models"
        } else {
            components.path = path + "/v1/models"
        }
        guard let url = components.url else {
            throw LLMRefiner.Error.invalidURL
        }
        return url
    }

    func testConnection(
        baseURL: String,
        apiKey: String,
        model: String,
        timeoutSeconds: Double
    ) async throws -> LLMProviderConnectionResult {
        AppLogger.network.debug("开始连通性测试：baseURL=\(baseURL), model=\(model)")
        let url = try Self.chatCompletionsURL(baseURL: baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeoutSeconds
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [["role": "user", "content": "Hello, respond with just OK."]],
            "temperature": 0.0,
            "max_tokens": 8,
            "stream": false,
        ])

        let startedAt = Date()
        let (data, response) = try await session.data(for: request)
        AppLogger.network.debug("连通性测试收到响应：status=\((response as? HTTPURLResponse)?.statusCode ?? -1), bytes=\(data.count)")
        try validate(response: response, data: data)
        _ = try LLMRefiner.parseChatCompletion(data)
        AppLogger.network.info("连通性测试成功")
        return LLMProviderConnectionResult(
            message: "连接成功",
            latencyMS: max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
        )
    }

    func listModels(
        baseURL: String,
        apiKey: String,
        timeoutSeconds: Double
    ) async throws -> [String] {
        AppLogger.network.debug("开始拉取模型列表：baseURL=\(baseURL)")
        let url = try Self.modelsURL(baseURL: baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeoutSeconds

        let (data, response) = try await session.data(for: request)
        AppLogger.network.debug("模型列表返回：status=\((response as? HTTPURLResponse)?.statusCode ?? -1), bytes=\(data.count)")
        try validate(response: response, data: data)
        return try Self.parseModels(data)
    }

    static func parseModels(_ data: Data) throws -> [String] {
        struct Response: Decodable {
            struct Model: Decodable {
                let id: String
            }

            let data: [Model]
        }

        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw LLMRefiner.Error.invalidResponse
        }
        return response.data.map(\.id)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.network.error("响应不是 HTTPURLResponse")
            throw LLMRefiner.Error.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            AppLogger.network.warning("LLM API 非成功响应：code=\(httpResponse.statusCode)")
            if let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJSON["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw LLMRefiner.Error.apiError(code: httpResponse.statusCode, message: message)
            }
            throw LLMRefiner.Error.httpError(code: httpResponse.statusCode)
        }
    }
}
