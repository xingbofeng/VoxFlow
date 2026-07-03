import Foundation

protocol LLMCompletionSession: AnyObject, Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func byteStream(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse)
}

extension URLSession: LLMCompletionSession {
    func byteStream(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse) {
        let (bytes, response) = try await self.bytes(for: request)
        let stream = AsyncThrowingStream<UInt8, Error> { continuation in
            let task = Task {
                do {
                    for try await byte in bytes {
                        continuation.yield(byte)
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
        return (stream, response)
    }
}

protocol ActiveLLMProviderIdentifying {
    var activeProviderID: String? { get }
}

final class RepositoryBackedLLMRefiner: TextRefining, AgentComposeConfiguring, TraceableStreamingPromptAwareTextRefining, TraceablePromptAwareTextRefining, ActiveLLMProviderIdentifying, RefinementTraceProviding, @unchecked Sendable {
    static let enabledDefaultsKey = "LLMRefiner_Enabled"
    static let agentProviderIDSettingsKey = "agent.compose.provider.id"

    private let providerRepository: any LLMProviderRepository
    private let credentialStore: CredentialStore
    private let settingsRepository: (any SettingsRepository)?
    private let defaults: UserDefaults
    private let session: any LLMCompletionSession
    private(set) var activeProviderID: String?
    private(set) var lastTrace: LLMRefinementTrace?

    init(
        providerRepository: any LLMProviderRepository,
        credentialStore: CredentialStore,
        settingsRepository: (any SettingsRepository)? = nil,
        defaults: UserDefaults = .standard,
        session: any LLMCompletionSession = URLSession.shared
    ) {
        self.providerRepository = providerRepository
        self.credentialStore = credentialStore
        self.settingsRepository = settingsRepository
        self.defaults = defaults
        self.session = session
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledDefaultsKey) }
        set { defaults.set(newValue, forKey: Self.enabledDefaultsKey) }
    }

    var isConfigured: Bool {
        guard let provider = try? configuredProvider(for: .dictationCorrection) else {
            return false
        }
        return isProviderConfigured(provider)
    }

    var isAgentComposeConfigured: Bool {
        guard let provider = try? configuredProvider(for: .agentCompose) else {
            return false
        }
        return isProviderConfigured(provider)
    }

    func refine(_ text: String) async throws -> String {
        try await refine(
            TextRefinementRequest(
                text: text,
                systemPrompt: PromptBuilder.conservativeSystemPrompt,
                model: nil,
                temperature: nil
            )
        )
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        let result = try await refineWithTrace(request)
        return result.text
    }

    func refineWithTrace(_ request: TextRefinementRequest) async throws -> TextRefinementTraceResult {
        AppLogger.network.debug("RepositoryBackedLLMRefiner 开始纠错：purpose=\(request.purpose), textLen=\(request.text.count)")
        let provider = try configuredProvider(for: request.purpose)
        guard provider.isOpenAICompatibleProvider else {
            AppLogger.network.warning("Agent provider 不再作为文本补全通道：providerId=\(provider.id)")
            throw LLMRefiner.Error.notConfigured
        }
        let apiKey = try credentialStore.readCredential(account: provider.apiKeyRef) ?? ""
        guard !provider.requiresAPIKey || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            AppLogger.network.warning("LLM provider 无可用 API Key：providerId=\(provider.id)")
            throw LLMRefiner.Error.notConfigured
        }
        AppLogger.network.debug("LLM provider 就绪：id=\(provider.id), model=\(provider.defaultModel)")

        let url = try OpenAICompatibleClient.chatCompletionsURL(baseURL: provider.baseURL)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        OpenAICompatibleClient.setAuthorizationHeader(apiKey: apiKey, request: &urlRequest)
        OpenAICompatibleClient.setProviderHeaders(baseURL: provider.baseURL, request: &urlRequest)
        urlRequest.timeoutInterval = provider.timeoutSeconds
        let selectedModel = OpenAICompatibleClient.normalizedModelID(
            request.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? request.model!
                : provider.defaultModel
        )
        let selectedTemperature = request.temperature ?? provider.temperature
        let userMessage = Self.userMessage(for: request)
        let body: [String: Any] = [
            "model": selectedModel,
            "messages": [
                ["role": "system", "content": request.systemPrompt],
                ["role": "user", "content": userMessage],
            ],
            "temperature": selectedTemperature,
            "stream": false,
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        var trace = LLMRefinementTrace(
            providerID: provider.id,
            providerName: provider.displayName,
            endpoint: url.absoluteString,
            model: selectedModel,
            temperature: selectedTemperature,
            timeoutSeconds: provider.timeoutSeconds,
            requestBodyJSON: Self.prettyJSONString(from: body),
            responseText: nil,
            statusCode: nil,
            durationMS: nil,
            errorMessage: nil,
            completedAt: nil,
            promptMetadata: request.promptMetadata
        )

        let startedAt = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            AppLogger.network.error("LLM 修正请求失败：provider=\(provider.id), error=\(error.localizedDescription)")
            trace = finishedTrace(
                trace,
                durationMS: Self.durationMS(since: startedAt),
                errorMessage: error.localizedDescription
            )
            lastTrace = trace
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            AppLogger.network.error("LLM 响应类型无效：provider=\(provider.id)")
            trace = finishedTrace(
                trace,
                durationMS: Self.durationMS(since: startedAt),
                errorMessage: LLMRefiner.Error.invalidResponse.localizedDescription
            )
            lastTrace = trace
            throw LLMRefiner.Error.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            AppLogger.network.warning("LLM 返回失败码：provider=\(provider.id), code=\(httpResponse.statusCode)")
            trace = finishedTrace(
                trace,
                statusCode: httpResponse.statusCode,
                durationMS: Self.durationMS(since: startedAt),
                errorMessage: LLMRefiner.Error.httpError(code: httpResponse.statusCode).localizedDescription
            )
            lastTrace = trace
            throw LLMRefiner.Error.httpError(code: httpResponse.statusCode)
        }
        activeProviderID = provider.id
        let refined = try LLMRefiner.parseChatCompletion(data)
        AppLogger.network.debug("LLM 返回文本长度：provider=\(provider.id), len=\(refined.count)")
        let finalText = refined.isEmpty ? request.text : refined
        trace = finishedTrace(
            trace,
            responseText: refined,
            statusCode: httpResponse.statusCode,
            durationMS: Self.durationMS(since: startedAt),
            errorMessage: nil
        )
        lastTrace = trace
        return TextRefinementTraceResult(text: finalText, providerID: provider.id, trace: trace)
    }

    func clearLastTrace() {
        lastTrace = nil
    }

    /// Streaming variant of refine() for agent compose.
    /// Returns accumulated text snapshots via AsyncThrowingStream so the HUD can show real-time generation.
    func refineStream(_ request: TextRefinementRequest) -> AsyncThrowingStream<String, Error> {
        refineStreamWithTrace(request).stream
    }

    func refineStreamWithTrace(_ request: TextRefinementRequest) -> TextRefinementStreamTraceResult {
        let traceHandle = TextRefinementTraceHandle()
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                var trace: LLMRefinementTrace?
                let startedAt = Date()
                do {
                    AppLogger.network.debug("RepositoryBackedLLMRefiner 开始流式纠错：textLen=\(request.text.count)")
                    let provider = try configuredProvider(for: request.purpose)
                    guard provider.isOpenAICompatibleProvider else {
                        AppLogger.network.warning("Agent provider 不再作为流式文本补全通道：providerId=\(provider.id)")
                        throw LLMRefiner.Error.notConfigured
                    }
                    let apiKey = try credentialStore.readCredential(account: provider.apiKeyRef) ?? ""
                    guard !provider.requiresAPIKey || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        AppLogger.network.warning("流式 LLM 无可用 API Key：provider=\(provider.id)")
                        throw LLMRefiner.Error.notConfigured
                    }

                    let url = try OpenAICompatibleClient.chatCompletionsURL(baseURL: provider.baseURL)
                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    OpenAICompatibleClient.setAuthorizationHeader(apiKey: apiKey, request: &urlRequest)
                    OpenAICompatibleClient.setProviderHeaders(baseURL: provider.baseURL, request: &urlRequest)
                    urlRequest.timeoutInterval = provider.timeoutSeconds
                    let selectedModel = OpenAICompatibleClient.normalizedModelID(
                        request.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                            ? request.model!
                            : provider.defaultModel
                    )
                    let selectedTemperature = request.temperature ?? provider.temperature
                    let userMessage = Self.userMessage(for: request)
                    let body: [String: Any] = [
                        "model": selectedModel,
                        "messages": [
                            ["role": "system", "content": request.systemPrompt],
                            ["role": "user", "content": userMessage],
                        ],
                        "temperature": selectedTemperature,
                        "stream": true,
                    ]
                    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
                    trace = LLMRefinementTrace(
                        providerID: provider.id,
                        providerName: provider.displayName,
                        endpoint: url.absoluteString,
                        model: selectedModel,
                        temperature: selectedTemperature,
                        timeoutSeconds: provider.timeoutSeconds,
                        requestBodyJSON: Self.prettyJSONString(from: body),
                        responseText: nil,
                        statusCode: nil,
                        durationMS: nil,
                        errorMessage: nil,
                        completedAt: nil,
                        promptMetadata: request.promptMetadata
                    )
                    lastTrace = trace

                    let (asyncBytes, response) = try await session.byteStream(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        AppLogger.network.error("流式 LLM 响应类型无效：provider=\(provider.id)")
                        throw LLMRefiner.Error.invalidResponse
                    }
                    guard (200...299).contains(httpResponse.statusCode) else {
                        AppLogger.network.warning("流式 LLM 返回失败码：provider=\(provider.id), code=\(httpResponse.statusCode)")
                        throw LLMRefiner.Error.httpError(code: httpResponse.statusCode)
                    }
                    let parsedStream = SSEParser.parse(byteStream: asyncBytes)

                    var latestAccumulatedText = ""
                    for try await accumulatedText in parsedStream {
                        latestAccumulatedText = accumulatedText
                        continuation.yield(accumulatedText)
                    }

                    activeProviderID = provider.id
                    guard let trace else {
                        AppLogger.network.error("流式 LLM trace 丢失：provider=\(provider.id)")
                        throw LLMRefiner.Error.invalidResponse
                    }
                    let finishedTrace = finishedTrace(
                        trace,
                        responseText: latestAccumulatedText,
                        statusCode: httpResponse.statusCode,
                        durationMS: Self.durationMS(since: startedAt),
                        errorMessage: nil
                    )
                    lastTrace = finishedTrace
                    traceHandle.complete(finishedTrace)
                    continuation.finish()
                    AppLogger.network.info("流式 LLM 完成：provider=\(provider.id), bytes=\(latestAccumulatedText.count)")
                } catch {
                    let providerID = trace?.providerID ?? "unknown"
                    AppLogger.network.error("流式 LLM 失败：provider=\(providerID), error=\(error.localizedDescription)")
                    if let trace {
                        let finishedTrace = finishedTrace(
                            trace,
                            durationMS: Self.durationMS(since: startedAt),
                            errorMessage: error.localizedDescription
                        )
                        lastTrace = finishedTrace
                        traceHandle.complete(finishedTrace)
                    } else {
                        traceHandle.fail(error)
                    }
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
        return TextRefinementStreamTraceResult(stream: stream, providerID: nil, trace: traceHandle)
    }

    private func configuredProvider(for purpose: TextRefinementPurpose) throws -> LLMProviderRecord {
        let providers = try providerRepository.list()
        AppLogger.network.debug("读取 provider 列表：count=\(providers.count)")
        let provider: LLMProviderRecord?
        if purpose == .agentCompose,
           let settingsRepository {
            provider = try configuredAgentProvider(from: providers, settingsRepository: settingsRepository)
        } else {
            provider = Self.defaultUsableProvider(from: providers)
        }
        guard let provider else {
            AppLogger.network.warning("未找到可用 LLM provider（未启用或缺少配置）")
            throw LLMRefiner.Error.notConfigured
        }
        AppLogger.network.debug("选中 provider：id=\(provider.id), name=\(provider.displayName), model=\(provider.defaultModel)")
        return provider
    }

    private func configuredAgentProvider(
        from providers: [LLMProviderRecord],
        settingsRepository: any SettingsRepository
    ) throws -> LLMProviderRecord? {
        guard let selectedID = try Self.agentProviderID(settingsRepository: settingsRepository) else {
            return nil
        }
        return providers.first {
            $0.enabled &&
                Self.isUsableAgentRuntimeProvider($0) &&
                ($0.id.caseInsensitiveCompare(selectedID) == .orderedSame ||
                 $0.providerType.caseInsensitiveCompare(selectedID) == .orderedSame)
        }
    }

    static func agentProviderID(settingsRepository: any SettingsRepository) throws -> String? {
        guard let valueJSON = try settingsRepository.value(forKey: agentProviderIDSettingsKey),
              let data = valueJSON.data(using: .utf8) else {
            return nil
        }
        let decoded = try JSONDecoder().decode(String.self, from: data)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }

    private func isProviderConfigured(_ provider: LLMProviderRecord) -> Bool {
        if provider.isLocalAgentProvider {
            return provider.enabled && provider.hasRequiredLLMConfiguration
        }
        if !provider.requiresAPIKey {
            return provider.enabled && provider.hasRequiredLLMConfiguration
        }
        guard let key = try? credentialStore.readCredential(account: provider.apiKeyRef) else {
            return false
        }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isUsableProvider(_ provider: LLMProviderRecord) -> Bool {
        provider.isOpenAICompatibleProvider && provider.hasRequiredLLMConfiguration
    }

    private static func defaultUsableProvider(from providers: [LLMProviderRecord]) -> LLMProviderRecord? {
        providers.first(where: { $0.enabled && $0.isDefault && Self.isUsableProvider($0) }) ??
            providers.first(where: { $0.enabled && Self.isUsableProvider($0) })
    }

    private static func isUsableAgentRuntimeProvider(_ provider: LLMProviderRecord) -> Bool {
        provider.isLocalAgentProvider &&
            provider.hasRequiredLLMConfiguration
    }

    private func finishTrace(
        responseText: String? = nil,
        statusCode: Int? = nil,
        durationMS: Int,
        errorMessage: String?
    ) {
        guard let trace = lastTrace else {
            return
        }
        lastTrace = finishedTrace(
            trace,
            responseText: responseText,
            statusCode: statusCode,
            durationMS: durationMS,
            errorMessage: errorMessage
        )
    }

    private func finishedTrace(
        _ trace: LLMRefinementTrace,
        responseText: String? = nil,
        statusCode: Int? = nil,
        durationMS: Int,
        errorMessage: String?
    ) -> LLMRefinementTrace {
        var finished = trace
        finished.responseText = responseText
        finished.statusCode = statusCode
        finished.durationMS = durationMS
        finished.errorMessage = errorMessage
        finished.completedAt = Date()
        return finished
    }

    private static func durationMS(since start: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(start) * 1000))
    }

    private static func prettyJSONString(from object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private static func userMessage(for request: TextRefinementRequest) -> String {
        switch request.purpose {
        case .agentCompose:
            return request.text
        case .directTask:
            return request.text
        case .dictationCorrection:
            break
        }

        return """
        待处理原文：
        \(request.text)
        """
    }

}
