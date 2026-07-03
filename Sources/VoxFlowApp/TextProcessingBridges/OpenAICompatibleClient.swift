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
        let normalized = try normalizedBaseURL(baseURL)
        if let githubURL = githubModelsChatCompletionsURL(baseURL: normalized) {
            return githubURL
        }
        return try LLMRefiner.chatCompletionsURL(baseURL: normalized)
    }

    private static func githubModelsChatCompletionsURL(baseURL: String) -> URL? {
        guard var components = URLComponents(string: baseURL),
              components.host?.lowercased() == "models.github.ai" else {
            return nil
        }
        var path = components.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        guard path == "/inference" else {
            return nil
        }
        components.path = "/inference/chat/completions"
        return components.url
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
        Self.setAuthorizationHeader(apiKey: apiKey, request: &request)
        Self.setProviderHeaders(baseURL: baseURL, request: &request)
        request.timeoutInterval = timeoutSeconds
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [["role": "user", "content": "Reply exactly OK."]],
            "temperature": 0.0,
            "max_tokens": 32,
            "stream": false,
        ])

        let startedAt = Date()
        let (data, response) = try await session.data(for: request)
        AppLogger.network.debug("连通性测试收到响应：status=\((response as? HTTPURLResponse)?.statusCode ?? -1), bytes=\(data.count)")
        try validate(response: response, data: data, baseURL: baseURL)
        _ = try LLMRefiner.parseChatCompletion(data)
        AppLogger.network.info("连通性测试成功")
        return LLMProviderConnectionResult(
            message: L10n.localize("llm.connection.success", comment: "LLM connection success message"),
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
        Self.setAuthorizationHeader(apiKey: apiKey, request: &request)
        Self.setProviderHeaders(baseURL: baseURL, request: &request)
        request.timeoutInterval = timeoutSeconds

        let (data, response) = try await session.data(for: request)
        AppLogger.network.debug("模型列表返回：status=\((response as? HTTPURLResponse)?.statusCode ?? -1), bytes=\(data.count)")
        try validate(response: response, data: data, baseURL: baseURL)
        return try Self.parseModels(data)
    }

    static func setAuthorizationHeader(apiKey: String, request: inout URLRequest) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
    }

    static func setProviderHeaders(baseURL: String, request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let normalizedURL = try? normalizedBaseURL(baseURL),
              let host = URLComponents(string: normalizedURL)?.host?.lowercased() else {
            return
        }
        if host == "models.github.ai" {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        }
        if host == "openrouter.ai" {
            request.setValue("https://mashangxie.app", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("VoxFlow", forHTTPHeaderField: "X-Title")
        }
    }

    private static var userAgent: String {
        let version = AppVersionInfo.current().version
            .unicodeScalars
            .map { scalar -> Character in
                CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "-" || scalar == "_"
                    ? Character(scalar)
                    : "-"
            }
        let sanitized = String(version)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        return "VoxFlow/\(sanitized.isEmpty ? "dev" : sanitized)"
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
        return response.data.map { model in
            normalizedModelID(model.id)
        }
    }

    static func normalizedModelID(_ modelID: String) -> String {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("models/") {
            return String(trimmed.dropFirst("models/".count))
        }
        return trimmed
    }

    private func validate(response: URLResponse, data: Data, baseURL: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.network.error("响应不是 HTTPURLResponse")
            throw LLMRefiner.Error.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            AppLogger.network.warning("LLM API 非成功响应：code=\(httpResponse.statusCode)")
            if let message = Self.apiErrorMessage(from: data) {
                throw LLMRefiner.Error.apiError(
                    code: httpResponse.statusCode,
                    message: Self.actionableErrorMessage(
                        baseURL: baseURL,
                        statusCode: httpResponse.statusCode,
                        message: message
                    )
                )
            }
            throw LLMRefiner.Error.httpError(code: httpResponse.statusCode)
        }
    }

    static func apiErrorMessage(from data: Data) -> String? {
        guard let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = errorJSON["error"] else {
            return nil
        }
        if let message = error as? String {
            return message
        }
        if let error = error as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return nil
    }

    static func actionableErrorMessage(baseURL: String, statusCode: Int, message: String) -> String {
        let lowercasedMessage = message.lowercased()
        guard let normalizedURL = try? normalizedBaseURL(baseURL),
              let host = URLComponents(string: normalizedURL)?.host?.lowercased() else {
            return message
        }
        if host == "router.huggingface.co",
           lowercasedMessage.contains("inference providers") &&
           lowercasedMessage.contains("permissions") {
            return L10n.localize("llm.refiner.error.huggingface_inference_permission", comment: "")
        }
        if host == "models.github.ai",
           lowercasedMessage.contains("no access to model") {
            return L10n.localize("llm.refiner.error.github_models_access", comment: "")
        }
        if host == "opencode.ai",
           lowercasedMessage.contains("insufficient balance") {
            return L10n.localize("llm.refiner.error.opencode_balance", comment: "")
        }
        return message
    }
}
