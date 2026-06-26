import Foundation

/// 问 AI 专用 OpenAI-compatible chat service。
///
/// 复用 `LLMProviderRepository`、`CredentialStore`、`OpenAICompatibleClient.chatCompletionsURL`、
/// `LLMCompletionSession`、`SSEParser`，但请求体仅包含多轮 user/assistant 消息，
/// 不注入纠错 system prompt，也不使用 `TextRefinementRequest`。
final class OpenAICompatibleChatService: AIChatServicing, @unchecked Sendable {
    private let providerRepository: any LLMProviderRepository
    private let credentialStore: any CredentialStore
    private let session: any LLMCompletionSession

    init(
        providerRepository: any LLMProviderRepository,
        credentialStore: any CredentialStore,
        session: any LLMCompletionSession = URLSession.shared
    ) {
        self.providerRepository = providerRepository
        self.credentialStore = credentialStore
        self.session = session
    }

    var isConfigured: Bool {
        guard let provider = try? configuredProvider(),
              let key = try? credentialStore.readCredential(account: provider.apiKeyRef),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }

    func streamResponse(messages: [AIChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let provider = try configuredProvider()
                    guard let apiKey = try credentialStore.readCredential(account: provider.apiKeyRef),
                          !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        AppLogger.network.warning("问 AI 无可用 API Key：provider=\(provider.id)")
                        throw LLMRefiner.Error.notConfigured
                    }

                    let url = try OpenAICompatibleClient.chatCompletionsURL(baseURL: provider.baseURL)
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.timeoutInterval = provider.timeoutSeconds
                    request.httpBody = try Self.makeRequestBody(
                        messages: messages,
                        model: provider.defaultModel,
                        temperature: provider.temperature
                    )
                    AppLogger.network.debug("问 AI 发起流式请求：provider=\(provider.id), model=\(provider.defaultModel)")

                    let (asyncBytes, response) = try await session.byteStream(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMRefiner.Error.invalidResponse
                    }
                    guard (200...299).contains(httpResponse.statusCode) else {
                        AppLogger.network.warning("问 AI 失败码：code=\(httpResponse.statusCode)")
                        throw LLMRefiner.Error.httpError(code: httpResponse.statusCode)
                    }

                    let parsed = SSEParser.parse(byteStream: asyncBytes)
                    for try await accumulatedText in parsed {
                        continuation.yield(accumulatedText)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// 构造多轮 chat 请求体。仅包含 user/assistant 消息，不注入 system prompt。
    static func makeRequestBody(
        messages: [AIChatMessage],
        model: String,
        temperature: Double
    ) throws -> Data {
        let payload: [[String: Any]] = messages.map { message in
            ["role": message.role.rawValue, "content": message.content]
        }
        let body: [String: Any] = [
            "model": model,
            "messages": payload,
            "temperature": temperature,
            "stream": true,
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func configuredProvider() throws -> LLMProviderRecord {
        let providers = try providerRepository.list()
        let provider = providers.first(where: { $0.enabled && $0.isDefault && $0.hasRequiredLLMConfiguration })
            ?? providers.first(where: { $0.enabled && $0.hasRequiredLLMConfiguration })
        guard let provider else {
            AppLogger.network.warning("问 AI 未找到可用 LLM provider")
            throw LLMRefiner.Error.notConfigured
        }
        return provider
    }
}
