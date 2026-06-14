import Foundation

protocol LLMCompletionSession: AnyObject, Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: LLMCompletionSession {}

protocol ActiveLLMProviderIdentifying {
    var activeProviderID: String? { get }
}

final class RepositoryBackedLLMRefiner: TextRefining, PromptAwareTextRefining, ActiveLLMProviderIdentifying, RefinementTraceProviding, @unchecked Sendable {
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
        let body: [String: Any] = [
            "model": selectedModel,
            "messages": [
                ["role": "system", "content": request.systemPrompt],
                ["role": "user", "content": request.text],
            ],
            "temperature": selectedTemperature,
            "stream": false,
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        lastTrace = LLMRefinementTrace(
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
            completedAt: nil
        )

        let startedAt = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            finishTrace(
                durationMS: Self.durationMS(since: startedAt),
                errorMessage: error.localizedDescription
            )
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            finishTrace(
                durationMS: Self.durationMS(since: startedAt),
                errorMessage: LLMRefiner.Error.invalidResponse.localizedDescription
            )
            throw LLMRefiner.Error.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            finishTrace(
                statusCode: httpResponse.statusCode,
                durationMS: Self.durationMS(since: startedAt),
                errorMessage: LLMRefiner.Error.httpError(code: httpResponse.statusCode).localizedDescription
            )
            throw LLMRefiner.Error.httpError(code: httpResponse.statusCode)
        }
        activeProviderID = provider.id
        let refined = try LLMRefiner.parseChatCompletion(data)
        let finalText = refined.isEmpty ? request.text : refined
        finishTrace(
            responseText: finalText,
            statusCode: httpResponse.statusCode,
            durationMS: Self.durationMS(since: startedAt),
            errorMessage: nil
        )
        return finalText
    }

    func clearLastTrace() {
        lastTrace = nil
    }

    private func configuredProvider() throws -> LLMProviderRecord {
        guard let provider = try providerRepository.list().first(where: { $0.enabled && $0.isDefault }),
              !provider.baseURL.isEmpty,
              !provider.defaultModel.isEmpty else {
            throw LLMRefiner.Error.notConfigured
        }
        return provider
    }

    private func finishTrace(
        responseText: String? = nil,
        statusCode: Int? = nil,
        durationMS: Int,
        errorMessage: String?
    ) {
        guard var trace = lastTrace else {
            return
        }
        trace.responseText = responseText
        trace.statusCode = statusCode
        trace.durationMS = durationMS
        trace.errorMessage = errorMessage
        trace.completedAt = Date()
        lastTrace = trace
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
}
