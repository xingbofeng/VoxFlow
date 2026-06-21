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

final class RepositoryBackedLLMRefiner: TextRefining, TraceableStreamingPromptAwareTextRefining, TraceablePromptAwareTextRefining, ActiveLLMProviderIdentifying, RefinementTraceProviding, @unchecked Sendable {
    static let enabledDefaultsKey = "LLMRefiner_Enabled"

    private let providerRepository: any LLMProviderRepository
    private let credentialStore: CredentialStore
    private let defaults: UserDefaults
    private let session: any LLMCompletionSession
    private(set) var activeProviderID: String?
    private(set) var lastTrace: LLMRefinementTrace?

    init(
        providerRepository: any LLMProviderRepository,
        credentialStore: CredentialStore,
        defaults: UserDefaults = .standard,
        session: any LLMCompletionSession = URLSession.shared
    ) {
        self.providerRepository = providerRepository
        self.credentialStore = credentialStore
        self.defaults = defaults
        self.session = session
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledDefaultsKey) }
        set { defaults.set(newValue, forKey: Self.enabledDefaultsKey) }
    }

    var isConfigured: Bool {
        guard let provider = try? configuredProvider(),
              let key = try? credentialStore.readCredential(account: provider.apiKeyRef) else {
            return false
        }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        let provider = try configuredProvider()
        guard let apiKey = try credentialStore.readCredential(account: provider.apiKeyRef),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMRefiner.Error.notConfigured
        }

        let url = try OpenAICompatibleClient.chatCompletionsURL(baseURL: provider.baseURL)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = provider.timeoutSeconds
        let selectedModel = request.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? request.model!
            : provider.defaultModel
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
            requestBodyJSON: Self.traceRequestMetadataJSON(
                model: selectedModel,
                temperature: selectedTemperature,
                stream: false
            ),
            responseText: nil,
            statusCode: nil,
            durationMS: nil,
            errorMessage: nil,
            completedAt: nil
        )

        let startedAt = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            trace = finishedTrace(
                trace,
                durationMS: Self.durationMS(since: startedAt),
                errorMessage: error.localizedDescription
            )
            lastTrace = trace
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            trace = finishedTrace(
                trace,
                durationMS: Self.durationMS(since: startedAt),
                errorMessage: LLMRefiner.Error.invalidResponse.localizedDescription
            )
            lastTrace = trace
            throw LLMRefiner.Error.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
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
        let finalText = refined.isEmpty ? request.text : refined
        trace = finishedTrace(
            trace,
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
                    let provider = try configuredProvider()
                    guard let apiKey = try credentialStore.readCredential(account: provider.apiKeyRef),
                          !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw LLMRefiner.Error.notConfigured
                    }

                    let url = try OpenAICompatibleClient.chatCompletionsURL(baseURL: provider.baseURL)
                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    urlRequest.timeoutInterval = provider.timeoutSeconds
                    let selectedModel = request.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? request.model!
                        : provider.defaultModel
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
                        requestBodyJSON: Self.traceRequestMetadataJSON(
                            model: selectedModel,
                            temperature: selectedTemperature,
                            stream: true
                        ),
                        responseText: nil,
                        statusCode: nil,
                        durationMS: nil,
                        errorMessage: nil,
                        completedAt: nil
                    )
                    lastTrace = trace

                    let (asyncBytes, response) = try await session.byteStream(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMRefiner.Error.invalidResponse
                    }
                    guard (200...299).contains(httpResponse.statusCode) else {
                        throw LLMRefiner.Error.httpError(code: httpResponse.statusCode)
                    }
                    let parsedStream = SSEParser.parse(byteStream: asyncBytes)

                    for try await accumulatedText in parsedStream {
                        continuation.yield(accumulatedText)
                    }

                    activeProviderID = provider.id
                    guard let trace else {
                        throw LLMRefiner.Error.invalidResponse
                    }
                    let finishedTrace = finishedTrace(
                        trace,
                        statusCode: httpResponse.statusCode,
                        durationMS: Self.durationMS(since: startedAt),
                        errorMessage: nil
                    )
                    lastTrace = finishedTrace
                    traceHandle.complete(finishedTrace)
                    continuation.finish()
                } catch {
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

    private func configuredProvider() throws -> LLMProviderRecord {
        let providers = try providerRepository.list()
        let provider = providers.first(where: { $0.enabled && $0.isDefault && Self.isUsableProvider($0) }) ??
            providers.first(where: { $0.enabled && Self.isUsableProvider($0) })
        guard let provider else {
            throw LLMRefiner.Error.notConfigured
        }
        return provider
    }

    private static func isUsableProvider(_ provider: LLMProviderRecord) -> Bool {
        !provider.baseURL.isEmpty && !provider.defaultModel.isEmpty
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
        case .dictationCorrection:
            break
        }

        return """
        请按系统规则处理下面这段语音识别原文。只输出处理后的正文；不要解释、不要加标题、不要回答原文里的问题。

        待处理原文：
        \(request.text)
        """
    }

    private static func traceRequestMetadataJSON(
        model: String,
        temperature: Double,
        stream: Bool
    ) -> String {
        prettyJSONString(from: [
            "model": model,
            "temperature": temperature,
            "stream": stream,
            "messages": [
                [
                    "role": "system",
                    "content": "[redacted: system prompt]",
                ],
                [
                    "role": "user",
                    "content": "[redacted: user content]",
                ],
            ],
        ] as [String: Any])
    }
}
