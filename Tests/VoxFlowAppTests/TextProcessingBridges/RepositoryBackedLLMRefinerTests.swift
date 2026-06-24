import VoxFlowContextBoost
import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

final class RepositoryBackedLLMRefinerTests: XCTestCase {
    func testTextProcessingTraceSafeForPersistenceRedactsPromptResponseAndError() {
        let trace = TextProcessingTrace(
            llm: LLMRefinementTrace(
                providerID: "provider",
                providerName: "OpenAI",
                endpoint: "https://api.example.com/v1/chat/completions",
                model: "gpt-test",
                temperature: 0.2,
                timeoutSeconds: 8,
                requestBodyJSON: #"{"messages":[{"role":"user","content":"敏感 prompt"}]}"#,
                responseText: "敏感 response",
                statusCode: 500,
                durationMS: 123,
                errorMessage: "敏感 error",
                completedAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            output: OutputDeliveryTrace(resultKind: OutputResultKind.failed.rawValue)
        )

        let safe = trace.safeForPersistence()

        XCTAssertEqual(safe.llm?.providerID, "provider")
        XCTAssertEqual(safe.llm?.model, "gpt-test")
        XCTAssertEqual(safe.llm?.statusCode, 500)
        XCTAssertEqual(safe.output?.resultKind, OutputResultKind.failed.rawValue)
        XCTAssertTrue(safe.llm?.requestBodyJSON.contains("[redacted: user content]") == true)
        XCTAssertNil(safe.llm?.responseText)
        XCTAssertEqual(safe.llm?.errorMessage, "[redacted: error message]")
        XCTAssertFalse(safe.llm?.requestBodyJSON.contains("敏感 prompt") == true)
    }

    func testTextProcessingTraceSafeForPersistenceRedactsContextBoostHotwordText() {
        let trace = TextProcessingTrace(
            contextBoost: ContextBoostTrace(
                appName: "Claude Code",
                bundleID: "com.anthropic.claudefordesktop",
                hotwords: ["Qwen3-ASR", "Project Apollo"],
                hotwordDetails: [
                    ContextBoostHotwordTrace(
                        text: "Qwen3-ASR",
                        score: 7,
                        source: "ocrShape",
                        evidenceReasons: ["shape_candidate"]
                    ),
                ],
                source: "current_window_ocr",
                ttlSeconds: 120,
                ocrCharacterCount: 256,
                candidateCount: 14,
                appliedToLLMPrompt: true,
                failureReason: "no_ocr_context"
            )
        )

        let safe = trace.safeForPersistence()

        XCTAssertEqual(safe.contextBoost?.appName, "Claude Code")
        XCTAssertEqual(safe.contextBoost?.hotwords, [])
        XCTAssertEqual(safe.contextBoost?.hotwordDetails, [])
        XCTAssertEqual(safe.contextBoost?.ocrCharacterCount, 256)
        XCTAssertEqual(safe.contextBoost?.candidateCount, 14)
        XCTAssertEqual(safe.contextBoost?.failureReason, "no_ocr_context")
    }

    func testTextProcessingTraceSafeForPersistenceKeepsVoiceCorrectionEvidence() {
        let event = CorrectionEvent(
            ruleID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            original: "Q问",
            replacement: "Qwen",
            range: CorrectionTextRange(location: 0, length: 2),
            scope: .global,
            source: .manual
        )
        let trace = TextProcessingTrace(
            voiceCorrection: VoiceCorrectionTrace(
                candidateEvents: [event],
                appliedEvents: [event],
                warnings: ["snapshotUnavailable"],
                failureReason: "敏感错误"
            )
        )

        let safe = trace.safeForPersistence()

        XCTAssertEqual(safe.voiceCorrection?.candidateEvents, [event])
        XCTAssertEqual(safe.voiceCorrection?.appliedEvents, [event])
        XCTAssertEqual(safe.voiceCorrection?.warnings, ["snapshotUnavailable"])
        XCTAssertEqual(safe.voiceCorrection?.failureReason, "[redacted: failure reason]")
    }

    func testRedactedSuccessfulTraceStillReportsSucceededFromStatusCode() {
        let trace = LLMRefinementTrace(
            providerID: "provider",
            providerName: "OpenAI",
            endpoint: "https://api.example.com/v1/chat/completions",
            model: "gpt-test",
            temperature: 0.2,
            timeoutSeconds: 8,
            requestBodyJSON: #"{"messages":[{"role":"user","content":"敏感 prompt"}]}"#,
            responseText: "敏感 response",
            statusCode: 200,
            durationMS: 123,
            errorMessage: nil,
            completedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let safe = trace.safeForPersistence()

        XCTAssertNil(safe.responseText)
        XCTAssertTrue(safe.succeeded)
    }

    func testRefineUsesEnabledDefaultProviderConfiguration() async throws {
        let credentials = TestCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(credentialStore: credentials)
        )
        let provider = makeProvider(isDefault: true)
        try environment.llmProviderRepository.save(provider)
        try credentials.saveCredential("secret", account: provider.apiKeyRef)
        let session = CapturingCompletionSession(
            response: Self.completionResponse("修正后")
        )
        let defaults = UserDefaults(suiteName: "RepositoryBackedLLMRefinerTests")!
        defaults.removePersistentDomain(forName: "RepositoryBackedLLMRefinerTests")
        defaults.set(true, forKey: RepositoryBackedLLMRefiner.enabledDefaultsKey)
        let refiner = RepositoryBackedLLMRefiner(
            providerRepository: environment.llmProviderRepository,
            credentialStore: credentials,
            defaults: defaults,
            session: session
        )

        let result = try await refiner.refine(
            TextRefinementRequest(
                text: "原文",
                systemPrompt: "系统提示",
                model: "style-model",
                temperature: 0.9
            )
        )

        XCTAssertEqual(result, "修正后")
        let request = try XCTUnwrap(session.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(request.timeoutInterval, 13)
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        )
        XCTAssertEqual(body["model"] as? String, "style-model")
        XCTAssertEqual(body["temperature"] as? Double, 0.9)
        XCTAssertNil(body["max_tokens"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.last?["role"] as? String, "user")
        let userContent = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(userContent.contains("待处理原文："))
        XCTAssertTrue(userContent.contains("原文"))
        XCTAssertFalse(userContent == "原文")
        XCTAssertEqual(refiner.lastTrace?.providerID, "global")
        XCTAssertEqual(refiner.lastTrace?.providerName, "OpenAI")
        XCTAssertEqual(refiner.lastTrace?.endpoint, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(refiner.lastTrace?.model, "style-model")
        XCTAssertEqual(refiner.lastTrace?.temperature, 0.9)
        XCTAssertEqual(refiner.lastTrace?.statusCode, 200)
        XCTAssertEqual(refiner.lastTrace?.responseText, "修正后")
        XCTAssertEqual(refiner.lastTrace?.errorMessage, nil)
        XCTAssertTrue(refiner.lastTrace?.requestBodyJSON.contains("系统提示") == true)
        XCTAssertTrue(refiner.lastTrace?.requestBodyJSON.contains("原文") == true)
        XCTAssertFalse(refiner.lastTrace?.safeForPersistence().requestBodyJSON.contains("原文") == true)
        XCTAssertNil(refiner.lastTrace?.safeForPersistence().responseText)
    }

    func testRefineRequestBodyIncludesContextBoostTopKInSystemPrompt() async throws {
        let credentials = TestCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(credentialStore: credentials)
        )
        let provider = makeProvider(isDefault: true)
        try environment.llmProviderRepository.save(provider)
        try credentials.saveCredential("secret", account: provider.apiKeyRef)
        let session = CapturingCompletionSession(
            response: Self.completionResponse("Qwen3-ASR 支持这个流程")
        )
        let defaults = UserDefaults(suiteName: "RepositoryBackedLLMRefinerTests.contextBoostRequest")!
        defaults.removePersistentDomain(forName: "RepositoryBackedLLMRefinerTests.contextBoostRequest")
        defaults.set(true, forKey: RepositoryBackedLLMRefiner.enabledDefaultsKey)
        let refiner = RepositoryBackedLLMRefiner(
            providerRepository: environment.llmProviderRepository,
            credentialStore: credentials,
            defaults: defaults,
            session: session
        )
        let prompt = PromptBuilder().build(
            style: nil,
            temporaryHotwords: [
                Self.hotword("Qwen3-ASR", score: 12),
                Self.hotword("Hyperframe", score: 10),
                Self.hotword("speech-swift", score: 8),
            ]
        )

        _ = try await refiner.refine(
            TextRefinementRequest(
                text: "去问这个模型支持吗",
                systemPrompt: prompt.systemPrompt,
                model: nil,
                temperature: nil
            )
        )

        let request = try XCTUnwrap(session.requests.first)
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        )
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let systemContent = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(systemContent.contains("临时屏幕上下文词，仅本次有效"))
        XCTAssertTrue(systemContent.contains(#""temporary_terms":["Qwen3-ASR","Hyperframe","speech-swift"]"#))
        XCTAssertFalse(systemContent.contains("完整 OCR 文本"))
    }

    func testRefineWithTraceReturnsRequestLocalTrace() async throws {
        let credentials = TestCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(credentialStore: credentials)
        )
        let provider = makeProvider(isDefault: true)
        try environment.llmProviderRepository.save(provider)
        try credentials.saveCredential("secret", account: provider.apiKeyRef)
        let session = CapturingCompletionSession(
            response: Self.completionResponse("修正后")
        )
        let defaults = UserDefaults(suiteName: "RepositoryBackedLLMRefinerTests.localTrace")!
        defaults.removePersistentDomain(forName: "RepositoryBackedLLMRefinerTests.localTrace")
        defaults.set(true, forKey: RepositoryBackedLLMRefiner.enabledDefaultsKey)
        let refiner = RepositoryBackedLLMRefiner(
            providerRepository: environment.llmProviderRepository,
            credentialStore: credentials,
            defaults: defaults,
            session: session
        )

        let result = try await refiner.refineWithTrace(
            TextRefinementRequest(
                text: "原文",
                systemPrompt: "系统提示",
                model: "request-local-model",
                temperature: 0.8
            )
        )

        XCTAssertEqual(result.text, "修正后")
        XCTAssertEqual(result.providerID, "global")
        XCTAssertEqual(result.trace.providerID, "global")
        XCTAssertEqual(result.trace.model, "request-local-model")
        XCTAssertEqual(result.trace.temperature, 0.8)
        XCTAssertEqual(result.trace.statusCode, 200)
        XCTAssertNil(result.trace.errorMessage)
        XCTAssertNotNil(result.trace.completedAt)
    }

    func testRefineStreamUsesInjectedSessionAndRequestsStreaming() async throws {
        let credentials = TestCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(credentialStore: credentials)
        )
        let provider = makeProvider(isDefault: true)
        try environment.llmProviderRepository.save(provider)
        try credentials.saveCredential("secret", account: provider.apiKeyRef)
        let session = CapturingCompletionSession(
            response: Self.completionResponse("unused"),
            streamChunks: [
                #"data: {"choices":[{"delta":{"content":"修"}}]}"# + "\n\n",
                #"data: {"choices":[{"delta":{"content":"正"}}]}"# + "\n\n",
                "data: [DONE]\n\n",
            ]
        )
        let defaults = UserDefaults(suiteName: "RepositoryBackedLLMRefinerTests.stream")!
        defaults.removePersistentDomain(forName: "RepositoryBackedLLMRefinerTests.stream")
        defaults.set(true, forKey: RepositoryBackedLLMRefiner.enabledDefaultsKey)
        let refiner = RepositoryBackedLLMRefiner(
            providerRepository: environment.llmProviderRepository,
            credentialStore: credentials,
            defaults: defaults,
            session: session
        )

        var snapshots: [String] = []
        for try await snapshot in refiner.refineStream(
            TextRefinementRequest(
                text: "原文",
                systemPrompt: "系统提示",
                model: nil,
                temperature: nil
            )
        ) {
            snapshots.append(snapshot)
        }

        XCTAssertEqual(snapshots, ["修", "修正"])
        XCTAssertTrue(session.usedStreamingEndpoint)
        let request = try XCTUnwrap(session.streamRequests.first)
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        )
        XCTAssertEqual(body["stream"] as? Bool, true)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let userContent = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(userContent.contains("待处理原文："))
        XCTAssertFalse(userContent == "原文")
        XCTAssertEqual(refiner.lastTrace?.responseText, "修正")
        XCTAssertTrue(refiner.lastTrace?.requestBodyJSON.contains("原文") == true)
    }

    func testRefineStreamWithTraceReturnsRequestLocalTrace() async throws {
        let credentials = TestCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(credentialStore: credentials)
        )
        let provider = makeProvider(isDefault: true)
        try environment.llmProviderRepository.save(provider)
        try credentials.saveCredential("secret", account: provider.apiKeyRef)
        let session = CapturingCompletionSession(
            response: Self.completionResponse("unused"),
            streamChunks: [
                #"data: {"choices":[{"delta":{"content":"修"}}]}"# + "\n\n",
                #"data: {"choices":[{"delta":{"content":"正"}}]}"# + "\n\n",
                "data: [DONE]\n\n",
            ]
        )
        let defaults = UserDefaults(suiteName: "RepositoryBackedLLMRefinerTests.streamLocalTrace")!
        defaults.removePersistentDomain(forName: "RepositoryBackedLLMRefinerTests.streamLocalTrace")
        defaults.set(true, forKey: RepositoryBackedLLMRefiner.enabledDefaultsKey)
        let refiner = RepositoryBackedLLMRefiner(
            providerRepository: environment.llmProviderRepository,
            credentialStore: credentials,
            defaults: defaults,
            session: session
        )

        let result = refiner.refineStreamWithTrace(
            TextRefinementRequest(
                text: "原文",
                systemPrompt: "系统提示",
                model: "stream-model",
                temperature: 0.8
            )
        )
        var snapshots: [String] = []
        for try await snapshot in result.stream {
            snapshots.append(snapshot)
        }
        let trace = try await result.trace.value()

        XCTAssertEqual(snapshots, ["修", "修正"])
        XCTAssertEqual(trace.providerID, "global")
        XCTAssertEqual(trace.model, "stream-model")
        XCTAssertEqual(trace.temperature, 0.8)
        XCTAssertEqual(trace.statusCode, 200)
        XCTAssertNil(trace.errorMessage)
        XCTAssertNotNil(trace.completedAt)
    }

    func testAgentComposeRequestUsesPromptDirectlyWithoutCorrectionWrapper() async throws {
        let credentials = TestCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(credentialStore: credentials)
        )
        let provider = makeProvider(isDefault: true)
        try environment.llmProviderRepository.save(provider)
        try credentials.saveCredential("secret", account: provider.apiKeyRef)
        let session = CapturingCompletionSession(
            response: Self.completionResponse("周三可以")
        )
        let defaults = UserDefaults(suiteName: "RepositoryBackedLLMRefinerTests.agentCompose")!
        defaults.removePersistentDomain(forName: "RepositoryBackedLLMRefinerTests.agentCompose")
        defaults.set(true, forKey: RepositoryBackedLLMRefiner.enabledDefaultsKey)
        let refiner = RepositoryBackedLLMRefiner(
            providerRepository: environment.llmProviderRepository,
            credentialStore: credentials,
            defaults: defaults,
            session: session
        )
        let request = AgentPromptBuilder().build(
            appName: "Messages",
            stylePrompt: nil,
            context: nil,
            userDictation: "帮我回复：周三可以"
        )

        _ = try await refiner.refine(request)

        let urlRequest = try XCTUnwrap(session.requests.first)
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(urlRequest.httpBody)) as? [String: Any]
        )
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let userContent = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertEqual(userContent, request.text)
        XCTAssertFalse(userContent.contains("不要回答原文里的问题"))
        XCTAssertFalse(userContent.contains("待处理原文："))
    }

    func testAgentComposeStreamingRequestUsesPromptDirectlyWithoutCorrectionWrapper() async throws {
        let credentials = TestCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(credentialStore: credentials)
        )
        let provider = makeProvider(isDefault: true)
        try environment.llmProviderRepository.save(provider)
        try credentials.saveCredential("secret", account: provider.apiKeyRef)
        let session = CapturingCompletionSession(
            response: Self.completionResponse("unused"),
            streamChunks: [
                #"data: {"choices":[{"delta":{"content":"周三可以"}}]}"# + "\n\n",
                "data: [DONE]\n\n",
            ]
        )
        let defaults = UserDefaults(suiteName: "RepositoryBackedLLMRefinerTests.agentComposeStream")!
        defaults.removePersistentDomain(forName: "RepositoryBackedLLMRefinerTests.agentComposeStream")
        defaults.set(true, forKey: RepositoryBackedLLMRefiner.enabledDefaultsKey)
        let refiner = RepositoryBackedLLMRefiner(
            providerRepository: environment.llmProviderRepository,
            credentialStore: credentials,
            defaults: defaults,
            session: session
        )
        let request = AgentPromptBuilder().build(
            appName: "Messages",
            stylePrompt: nil,
            context: nil,
            userDictation: "帮我回复：周三可以"
        )

        for try await _ in refiner.refineStream(request) {}

        let urlRequest = try XCTUnwrap(session.streamRequests.first)
        let body = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: XCTUnwrap(urlRequest.httpBody)) as? [String: Any]
        )
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let userContent = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertEqual(userContent, request.text)
        XCTAssertFalse(userContent.contains("不要回答原文里的问题"))
        XCTAssertFalse(userContent.contains("待处理原文："))
    }

    func testNoEnabledDefaultProviderIsNotConfigured() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let defaults = UserDefaults(suiteName: "RepositoryBackedLLMRefinerTests.empty")!
        defaults.removePersistentDomain(forName: "RepositoryBackedLLMRefinerTests.empty")
        defaults.set(true, forKey: RepositoryBackedLLMRefiner.enabledDefaultsKey)
        let refiner = RepositoryBackedLLMRefiner(
            providerRepository: environment.llmProviderRepository,
            credentialStore: environment.credentialStore,
            defaults: defaults
        )

        XCTAssertFalse(refiner.isConfigured)
    }

    func testConfiguredProviderFallsBackToEnabledProviderWhenDefaultFlagIsMissing() throws {
        let credentials = TestCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(credentialStore: credentials)
        )
        let provider = makeProvider(isDefault: false)
        try environment.llmProviderRepository.save(provider)
        try credentials.saveCredential("secret", account: provider.apiKeyRef)
        let defaults = UserDefaults(suiteName: "RepositoryBackedLLMRefinerTests.enabledFallback")!
        defaults.removePersistentDomain(forName: "RepositoryBackedLLMRefinerTests.enabledFallback")
        defaults.set(true, forKey: RepositoryBackedLLMRefiner.enabledDefaultsKey)
        let refiner = RepositoryBackedLLMRefiner(
            providerRepository: environment.llmProviderRepository,
            credentialStore: credentials,
            defaults: defaults
        )

        XCTAssertTrue(refiner.isConfigured)
    }

    private func makeProvider(isDefault: Bool) -> LLMProviderRecord {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return LLMProviderRecord(
            id: "global",
            displayName: "OpenAI",
            providerType: "openaiCompatible",
            baseURL: "https://api.example.com/v1",
            defaultModel: "global-model",
            apiKeyRef: "global-key",
            temperature: 0.25,
            timeoutSeconds: 13,
            enabled: true,
            isDefault: isDefault,
            lastHealthStatus: nil,
            lastHealthMessage: nil,
            lastLatencyMS: nil,
            createdAt: date,
            updatedAt: date
        )
    }

    private static func completionResponse(_ text: String) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": text]]]
        ])
    }

    private static func hotword(_ text: String, score: Double) -> TemporaryHotword {
        TemporaryHotword(
            text: text,
            normalizedText: text.lowercased(),
            score: score,
            source: .ocrShape,
            evidence: [HotwordEvidence(reason: "test", weight: score)],
            expiresAt: Date(timeIntervalSince1970: 1_800_000_120)
        )
    }
}

private final class TestCredentialStore: CredentialStore {
    private var values: [String: String] = [:]

    func readCredential(account: String) throws -> String? { values[account] }
    func saveCredential(_ value: String, account: String) throws { values[account] = value }
    func deleteCredential(account: String) throws { values.removeValue(forKey: account) }
}

private final class CapturingCompletionSession: LLMCompletionSession, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private(set) var streamRequests: [URLRequest] = []
    let response: Data
    let streamChunks: [String]

    var usedStreamingEndpoint: Bool {
        !streamRequests.isEmpty
    }

    init(response: Data, streamChunks: [String] = []) {
        self.response = response
        self.streamChunks = streamChunks
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return (
            response,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }

    func byteStream(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse) {
        streamRequests.append(request)
        let chunks = streamChunks
        let stream = AsyncThrowingStream<UInt8, Error> { continuation in
            Task {
                for chunk in chunks {
                    for byte in chunk.utf8 {
                        continuation.yield(byte)
                    }
                }
                continuation.finish()
            }
        }
        return (
            stream,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }
}
