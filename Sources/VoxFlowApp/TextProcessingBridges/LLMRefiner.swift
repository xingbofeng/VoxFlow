import Foundation

/// LLM-based text refiner using OpenAI-compatible API.
/// Conservatively corrects speech recognition errors, especially for CJK-English mixed content.
final class LLMRefiner: @unchecked Sendable {
    // MARK: - Keys

    private let defaults: UserDefaults
    private let credentialStore: CredentialStore
    private let keyEnabled = "LLMRefiner_Enabled"
    private let keyBaseURL = "LLMRefiner_BaseURL"
    private let keyModel = "LLMRefiner_Model"
    private let apiKeyAccount = "llm-api-key"

    init(
        defaults: UserDefaults = .standard,
        credentialStore: CredentialStore = AppLocalCredentialStore.liveDefault()
    ) {
        self.defaults = defaults
        self.credentialStore = credentialStore
    }

    // MARK: - Settings

    var isEnabled: Bool {
        get { defaults.bool(forKey: keyEnabled) }
        set { defaults.set(newValue, forKey: keyEnabled) }
    }

    var baseURL: String? {
        get { defaults.string(forKey: keyBaseURL) }
        set { set(newValue, forKey: keyBaseURL) }
    }

    var apiKey: String? {
        get {
            guard let value = try? credentialStore.readCredential(account: apiKeyAccount),
                  !value.isEmpty else {
                return nil
            }
            return value
        }
        set {
            try? setAPIKey(newValue)
        }
    }

    var model: String? {
        get { defaults.string(forKey: keyModel) }
        set { set(newValue, forKey: keyModel) }
    }

    var isConfigured: Bool {
        guard let baseURL = baseURL, !baseURL.isEmpty,
              let apiKey = apiKey, !apiKey.isEmpty,
              let model = model, !model.isEmpty else {
            return false
        }
        guard let url = URL(string: baseURL), url.scheme != nil else {
            return false
        }
        return true
    }

    private func set(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func setAPIKey(_ value: String?) throws {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            try credentialStore.deleteCredential(account: apiKeyAccount)
            return
        }

        try credentialStore.saveCredential(trimmed, account: apiKeyAccount)
    }

    // MARK: - System Prompt

    private let systemPrompt = PromptBuilder.conservativeSystemPrompt

    // MARK: - API Call

    static func chatCompletionsURL(baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil,
              components.query == nil,
              components.fragment == nil else {
            throw Error.invalidURL
        }

        var path = components.path
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        if path == "/" {
            path = ""
        }

        if path.hasSuffix("/chat/completions") {
            components.path = path
        } else if path.hasSuffix("/v1") {
            components.path = path + "/chat/completions"
        } else {
            components.path = path + "/v1/chat/completions"
        }

        guard let url = components.url else {
            throw Error.invalidURL
        }
        return url
    }

    static func parseChatCompletion(_ data: Data) throws -> String {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }

                let message: Message
            }

            let choices: [Choice]
        }

        guard let content = try? JSONDecoder().decode(Response.self, from: data)
            .choices.first?.message.content else {
            throw Error.invalidResponse
        }
        return content
    }

    func refine(_ text: String) async throws -> String {
        try await refine(
            TextRefinementRequest(
                text: text,
                systemPrompt: systemPrompt,
                model: nil,
                temperature: nil
            )
        )
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        guard isConfigured,
              let baseURL = baseURL,
              let apiKey = apiKey,
              let configuredModel = model else {
            throw Error.notConfigured
        }

        let selectedModel = request.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? request.model!
            : configuredModel
        let chatURL = try Self.chatCompletionsURL(baseURL: baseURL)

        var urlRequest = URLRequest(url: chatURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = 15.0

        let body: [String: Any] = [
            "model": selectedModel,
            "messages": [
                ["role": "system", "content": request.systemPrompt],
                ["role": "user", "content": request.text]
            ],
            "temperature": request.temperature ?? 0.0,
            "stream": false
        ]

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to extract error message
            if let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJSON["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw Error.apiError(code: httpResponse.statusCode, message: message)
            }
            throw Error.httpError(code: httpResponse.statusCode)
        }

        let refined = try Self.parseChatCompletion(data)

        // If LLM returned empty or almost empty, fall back to original
        guard !refined.isEmpty else {
            return request.text
        }

        return refined
    }

    // MARK: - Test Connection

    func testConnection(
        baseURL: String,
        apiKey: String,
        model: String
    ) async -> Result<String, Error> {
        guard let chatURL = try? Self.chatCompletionsURL(baseURL: baseURL) else {
            return .failure(Error.invalidURL)
        }

        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10.0

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": "Hello, respond with just the word 'OK'."]
            ],
            "temperature": 0.0,
            "max_tokens": 10,
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return .failure(Error.invalidRequestBody)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(Error.invalidResponse)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                if let errorJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorJSON["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    return .failure(Error.apiError(code: httpResponse.statusCode, message: message))
                }
                return .failure(Error.httpError(code: httpResponse.statusCode))
            }

            _ = try Self.parseChatCompletion(data)
            return .success("连接成功！API 正常工作。")
        } catch let error as Error {
            return .failure(error)
        } catch {
            return .failure(Error.networkError(error))
        }
    }

    // MARK: - Errors

    enum Error: Swift.Error, LocalizedError {
        case notConfigured
        case invalidURL
        case invalidRequestBody
        case invalidResponse
        case httpError(code: Int)
        case apiError(code: Int, message: String)
        case networkError(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "LLM 未配置，请先设置 API 参数。"
            case .invalidURL:
                return "API Base URL 无效。"
            case .invalidRequestBody:
                return "请求体构建失败。"
            case .invalidResponse:
                return "服务器返回了无效响应。"
            case .httpError(let code):
                return "HTTP 错误：\(code)"
            case .apiError(let code, let message):
                return "API 错误 (\(code))：\(message)"
            case .networkError(let error):
                return "网络错误：\(error.localizedDescription)"
            }
        }
    }
}
