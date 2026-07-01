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
    private let codexClient: any CodexPromptCompleting

    init(
        providerRepository: any LLMProviderRepository,
        credentialStore: any CredentialStore,
        session: any LLMCompletionSession = URLSession.shared,
        codexClient: any CodexPromptCompleting = CodexPromptCompletionClient()
    ) {
        self.providerRepository = providerRepository
        self.credentialStore = credentialStore
        self.session = session
        self.codexClient = codexClient
    }

    var isConfigured: Bool {
        guard let provider = try? configuredProvider() else {
            return false
        }
        if provider.isCodexLLMProvider {
            return codexClient.isAvailable
        }
        guard let key = try? credentialStore.readCredential(account: provider.apiKeyRef),
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
                    if provider.isCodexLLMProvider {
                        let output = try await codexClient.complete(
                            prompt: Self.codexPrompt(messages: messages),
                            model: provider.defaultModel,
                            timeoutSeconds: provider.timeoutSeconds
                        )
                        continuation.yield(output)
                        continuation.finish()
                        return
                    }
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
        let provider = providers.first(where: { LLMProviderAvailability.isUsableProvider($0) && $0.isDefault })
            ?? providers.first(where: LLMProviderAvailability.isUsableProvider)
        guard let provider else {
            AppLogger.network.warning("问 AI 未找到可用 LLM provider")
            throw LLMRefiner.Error.notConfigured
        }
        return provider
    }

    private static func codexPrompt(messages: [AIChatMessage]) -> String {
        let transcript = messages.map { message in
            switch message.role {
            case .user:
                return "用户：\(message.content)"
            case .assistant:
                return "助手：\(message.content)"
            }
        }.joined(separator: "\n\n")
        return """
        你是 VoxFlow 的问 AI 文本助手。请根据下面的对话继续回答用户。

        \(transcript)
        """
    }
}
