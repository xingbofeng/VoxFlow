import XCTest
@testable import VoxFlowApp

@MainActor
final class LLMProviderViewModelTests: XCTestCase {
    func testNewProviderRequiresNameURLModelAndAPIKey() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = LLMProviderViewModel(environment: environment, client: StubProviderClient())

        XCTAssertThrowsError(
            try viewModel.saveProvider(
                id: nil,
                displayName: "",
                baseURL: "",
                model: "",
                apiKey: "",
                temperature: 0.2,
                timeoutSeconds: 8,
                enabled: true,
                isDefault: true
            )
        ) { error in
            XCTAssertEqual(
                error as? LLMProviderViewModelError,
                .requiredFields(["名称", "基础 URL", "模型", "访问密钥"])
            )
        }
        XCTAssertEqual(viewModel.providers, [])
    }

    func testEditingProviderCanKeepStoredAPIKey() throws {
        let store = InMemoryProviderCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(credentialStore: store)
        )
        let viewModel = LLMProviderViewModel(environment: environment, client: StubProviderClient())
        try viewModel.saveProvider(
            id: "provider",
            displayName: "Provider",
            baseURL: "https://api.example.com",
            model: "model-a",
            apiKey: "secret",
            temperature: 0.2,
            timeoutSeconds: 8,
            enabled: true,
            isDefault: true
        )

        XCTAssertTrue(viewModel.hasStoredAPIKey(providerID: "provider"))
        try viewModel.saveProvider(
            id: "provider",
            displayName: "Updated",
            baseURL: "https://api.example.com",
            model: "model-b",
            apiKey: "",
            temperature: 0.2,
            timeoutSeconds: 8,
            enabled: true,
            isDefault: true
        )

        XCTAssertEqual(store.value(for: "llm-provider-provider"), "secret")
    }

    func testAPIKeyForEditingUsesUniformMaskAndCanRevealStoredKey() throws {
        let store = InMemoryProviderCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(credentialStore: store)
        )
        let viewModel = LLMProviderViewModel(environment: environment, client: StubProviderClient())
        try viewModel.saveProvider(
            id: "provider",
            displayName: "Provider",
            baseURL: "https://api.example.com",
            model: "model-a",
            apiKey: "sk-real-secret-value",
            temperature: 0.2,
            timeoutSeconds: 8,
            enabled: true,
            isDefault: true
        )

        XCTAssertEqual(viewModel.APIKeyForEditing(providerID: "provider"), "••••••••••••")
        XCTAssertEqual(viewModel.storedAPIKeyForEditing(providerID: "provider"), "sk-real-secret-value")
        XCTAssertTrue(
            viewModel.isMaskedAPIKey(providerID: "provider", text: "••••••••••••")
        )
    }

    func testDraftConnectionUsesStoredKeyWhenDraftStillContainsMask() async throws {
        let store = InMemoryProviderCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(credentialStore: store)
        )
        let client = CapturingProviderClient()
        let viewModel = LLMProviderViewModel(environment: environment, client: client)
        try viewModel.saveProvider(
            id: "provider",
            displayName: "Provider",
            baseURL: "https://api.example.com",
            model: "model-a",
            apiKey: "stored-secret",
            temperature: 0.2,
            timeoutSeconds: 8,
            enabled: true,
            isDefault: true
        )

        await viewModel.testDraftConnection(
            providerID: "provider",
            displayName: "Provider",
            baseURL: "https://draft.example.com/v1/",
            model: "draft-model",
            apiKey: viewModel.APIKeyForEditing(providerID: "provider")
        )

        XCTAssertEqual(client.lastAPIKey, "stored-secret")
        XCTAssertEqual(viewModel.lastActionMessage, "连接测试成功")
    }

    func testDraftConnectionUsesUnsavedFields() async throws {
        let store = InMemoryProviderCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(credentialStore: store)
        )
        let client = CapturingProviderClient()
        let viewModel = LLMProviderViewModel(environment: environment, client: client)

        await viewModel.testDraftConnection(
            providerID: nil,
            displayName: "Draft",
            baseURL: "https://draft.example.com/v1/",
            model: "draft-model",
            apiKey: "draft-secret"
        )

        XCTAssertEqual(client.lastBaseURL, "https://draft.example.com/v1")
        XCTAssertEqual(client.lastModel, "draft-model")
        XCTAssertEqual(client.lastAPIKey, "draft-secret")
        XCTAssertEqual(viewModel.lastActionMessage, "连接测试成功")
    }

    func testSaveProviderRemovesLineBreaksFromSingleLineFields() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = LLMProviderViewModel(environment: environment, client: StubProviderClient())

        try viewModel.saveProvider(
            id: nil,
            displayName: "Primary\nModel",
            baseURL: "https://api.example.com\n/v1/",
            model: "gpt-4o\nmini",
            apiKey: "secret\nvalue",
            temperature: 0.2,
            timeoutSeconds: 8,
            enabled: true,
            isDefault: true
        )

        let provider = try XCTUnwrap(viewModel.providers.first)
        XCTAssertEqual(provider.displayName, "PrimaryModel")
        XCTAssertEqual(provider.baseURL, "https://api.example.com/v1")
        XCTAssertEqual(provider.defaultModel, "gpt-4omini")
    }

    func testDraftConnectionRemovesLineBreaksFromSingleLineFields() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let client = CapturingProviderClient()
        let viewModel = LLMProviderViewModel(environment: environment, client: client)

        await viewModel.testDraftConnection(
            providerID: nil,
            displayName: "Draft\nProvider",
            baseURL: "https://draft.example.com\n/v1/",
            model: "draft\nmodel",
            apiKey: "draft\nsecret"
        )

        XCTAssertEqual(client.lastBaseURL, "https://draft.example.com/v1")
        XCTAssertEqual(client.lastModel, "draftmodel")
        XCTAssertEqual(client.lastAPIKey, "draftsecret")
        XCTAssertEqual(viewModel.lastActionMessage, "连接测试成功")
    }

    func testDraftValidationReturnsInlineErrorsForEveryInvalidField() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = LLMProviderViewModel(environment: environment, client: StubProviderClient())

        let errors = viewModel.validationErrors(
            providerID: nil,
            displayName: " ",
            baseURL: "not a url",
            model: "",
            apiKey: ""
        )

        XCTAssertEqual(errors["displayName"], "请输入名称")
        XCTAssertEqual(errors["baseURL"], "请输入有效的 HTTP 或 HTTPS 地址")
        XCTAssertEqual(errors["model"], "请输入模型名称")
        XCTAssertEqual(errors["apiKey"], "请输入访问密钥")
    }

    func testSaveProviderStoresAPIKeyInCredentialStoreOnly() throws {
        let store = InMemoryProviderCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(credentialStore: store)
        )
        let viewModel = LLMProviderViewModel(environment: environment, client: StubProviderClient())

        try viewModel.saveProvider(
            id: nil,
            displayName: "Primary",
            baseURL: "https://api.example.com/v1/",
            model: "model-a",
            apiKey: "secret",
            temperature: 0.2,
            timeoutSeconds: 8,
            enabled: true,
            isDefault: true
        )

        let provider = try XCTUnwrap(viewModel.providers.first)
        XCTAssertEqual(provider.baseURL, "https://api.example.com/v1")
        XCTAssertEqual(provider.apiKeyRef, "llm-provider-\(provider.id)")
        XCTAssertEqual(store.value(for: provider.apiKeyRef), "secret")
        XCTAssertEqual(viewModel.lastActionMessage, "已保存模型服务")
    }

    func testEditingMigratedProviderWithoutNewKeyPreservesCredentialReference() throws {
        let store = InMemoryProviderCredentialStore()
        try store.saveCredential("legacy-secret", account: "llm-api-key")
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(credentialStore: store)
        )
        let now = Date(timeIntervalSince1970: 1_000)
        try environment.llmProviderRepository.save(
            LLMProviderRecord(
                id: "legacy-openai-compatible",
                displayName: "Legacy",
                providerType: "openaiCompatible",
                baseURL: "https://api.example.com/v1",
                defaultModel: "model-a",
                apiKeyRef: "llm-api-key",
                temperature: 0.2,
                timeoutSeconds: 8,
                enabled: true,
                isDefault: true,
                lastHealthStatus: nil,
                lastHealthMessage: nil,
                lastLatencyMS: nil,
                createdAt: now,
                updatedAt: now
            )
        )
        let viewModel = LLMProviderViewModel(environment: environment, client: StubProviderClient())

        try viewModel.saveProvider(
            id: "legacy-openai-compatible",
            displayName: "Updated",
            baseURL: "https://api.example.com/v1",
            model: "model-b",
            apiKey: "",
            temperature: 0.3,
            timeoutSeconds: 10,
            enabled: true,
            isDefault: true
        )

        let provider = try XCTUnwrap(
            try environment.llmProviderRepository.provider(id: "legacy-openai-compatible")
        )
        XCTAssertEqual(provider.apiKeyRef, "llm-api-key")
        XCTAssertEqual(store.value(for: provider.apiKeyRef), "legacy-secret")
    }

    func testTestConnectionUpdatesProviderHealth() async throws {
        let store = InMemoryProviderCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(credentialStore: store)
        )
        let client = StubProviderClient(result: .success(LLMProviderConnectionResult(message: "OK", latencyMS: 42)))
        let viewModel = LLMProviderViewModel(environment: environment, client: client)
        try viewModel.saveProvider(
            id: "provider",
            displayName: "Provider",
            baseURL: "https://api.example.com",
            model: "model-a",
            apiKey: "secret",
            temperature: 0.2,
            timeoutSeconds: 8,
            enabled: true,
            isDefault: true
        )

        await viewModel.testConnection(id: "provider")

        let provider = try XCTUnwrap(try environment.llmProviderRepository.provider(id: "provider"))
        XCTAssertEqual(provider.lastHealthStatus, "ok")
        XCTAssertEqual(provider.lastLatencyMS, 42)
    }

    func testConnectionExposesProviderTestingStateUntilRequestCompletes() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let client = BlockingProviderClient()
        let viewModel = LLMProviderViewModel(environment: environment, client: client)
        try viewModel.saveProvider(
            id: "provider",
            displayName: "Provider",
            baseURL: "https://api.example.com",
            model: "model-a",
            apiKey: "secret",
            temperature: 0.2,
            timeoutSeconds: 8,
            enabled: true,
            isDefault: true
        )

        let task = Task { await viewModel.testConnection(id: "provider") }
        await client.waitUntilStarted()

        XCTAssertEqual(viewModel.testingProviderID, "provider")

        await client.complete()
        await task.value
        XCTAssertNil(viewModel.testingProviderID)
    }

    func testDraftConnectionExposesTestingStateUntilRequestCompletes() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let client = BlockingProviderClient()
        let viewModel = LLMProviderViewModel(environment: environment, client: client)

        let task = Task {
            await viewModel.testDraftConnection(
                providerID: nil,
                displayName: "Draft",
                baseURL: "https://api.example.com",
                model: "model-a",
                apiKey: "draft-secret"
            )
        }
        await client.waitUntilStarted()

        XCTAssertTrue(viewModel.isTestingDraftConnection)

        await client.complete()
        await task.value
        XCTAssertFalse(viewModel.isTestingDraftConnection)
    }

    func testRefreshModelsStoresModelIDsAndLatency() async throws {
        let store = InMemoryProviderCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(credentialStore: store)
        )
        let client = StubProviderClient(
            result: .success(LLMProviderConnectionResult(message: "OK", latencyMS: 37)),
            models: ["model-a", "model-b"]
        )
        let viewModel = LLMProviderViewModel(environment: environment, client: client)
        try viewModel.saveProvider(
            id: "provider",
            displayName: "Provider",
            baseURL: "https://api.example.com",
            model: "model-a",
            apiKey: "secret",
            temperature: 0.2,
            timeoutSeconds: 8,
            enabled: true,
            isDefault: true
        )

        await viewModel.refreshModelsAndMeasure(id: "provider")

        XCTAssertEqual(viewModel.modelIDsByProviderID["provider"], ["model-a", "model-b"])
        let provider = try XCTUnwrap(try environment.llmProviderRepository.provider(id: "provider"))
        XCTAssertEqual(provider.lastLatencyMS, 37)
        XCTAssertEqual(provider.lastHealthStatus, "ok")
    }

    func testDeleteProviderRemovesCredential() throws {
        let store = InMemoryProviderCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(credentialStore: store)
        )
        let viewModel = LLMProviderViewModel(environment: environment, client: StubProviderClient())
        try viewModel.saveProvider(
            id: "provider",
            displayName: "Provider",
            baseURL: "https://api.example.com",
            model: "model-a",
            apiKey: "secret",
            temperature: 0.2,
            timeoutSeconds: 8,
            enabled: true,
            isDefault: true
        )

        viewModel.deleteProvider(id: "provider")

        XCTAssertEqual(viewModel.providers, [])
        XCTAssertNil(store.value(for: "llm-provider-provider"))
    }

    func testDeletingDefaultProviderPromotesRemainingEnabledProvider() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = LLMProviderViewModel(environment: environment, client: StubProviderClient())
        try viewModel.saveProvider(
            id: "primary",
            displayName: "Primary",
            baseURL: "https://primary.example.com",
            model: "model-a",
            apiKey: "primary-secret",
            temperature: 0.2,
            timeoutSeconds: 8,
            enabled: true,
            isDefault: true
        )
        try viewModel.saveProvider(
            id: "backup",
            displayName: "Backup",
            baseURL: "https://backup.example.com",
            model: "model-b",
            apiKey: "backup-secret",
            temperature: 0.2,
            timeoutSeconds: 8,
            enabled: true,
            isDefault: false
        )

        viewModel.deleteProvider(id: "primary")

        XCTAssertEqual(viewModel.providers.map(\.id), ["backup"])
        XCTAssertEqual(viewModel.providers.first?.isDefault, true)
    }

    func testSelectModelUpdatesGlobalProviderModel() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = LLMProviderViewModel(environment: environment, client: StubProviderClient())
        try viewModel.saveProvider(
            id: "provider",
            displayName: "Provider",
            baseURL: "https://api.example.com",
            model: "model-a",
            apiKey: "secret",
            temperature: 0.2,
            timeoutSeconds: 8,
            enabled: true,
            isDefault: true
        )

        try viewModel.selectModel(providerID: "provider", model: "model-b")

        XCTAssertEqual(viewModel.providers.first?.defaultModel, "model-b")
        XCTAssertEqual(viewModel.lastActionMessage, "已选择全局模型 model-b")
    }

    func testCodexRuntimeDetectionRefreshesRuntimeModelList() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let detector = StubCodexRuntimeDetector(
            availability: AgentRuntimeAvailability(
                providerID: "codex",
                status: .available,
                detectedAt: Date(timeIntervalSince1970: 1_800_000_000),
                expiresAt: Date(timeIntervalSince1970: 1_800_000_060),
                cliPath: "/tmp/codex",
                cliVersion: "codex-cli test"
            )
        )
        let modelLister = StubCodexModelListProvider(models: ["gpt-5.5", "gpt-5.4"])
        let viewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            codexRuntimeDetector: detector,
            codexModelListProvider: modelLister
        )

        await viewModel.detectCodexRuntime(forceRefresh: true)

        XCTAssertEqual(viewModel.codexModelIDs, ["gpt-5.5", "gpt-5.4"])
        XCTAssertEqual(modelLister.lastCLIPath, "/tmp/codex")
        XCTAssertEqual(viewModel.lastActionMessage, "本机 Codex 运行时可用")
    }

    func testCodexModelsDoNotUseStaticFallbackWhenUndetectedAndUnconfigured() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            codexRuntimeDetector: StubCodexRuntimeDetector(availability: .availableForTests()),
            codexModelListProvider: StubCodexModelListProvider(models: [])
        )

        XCTAssertEqual(viewModel.codexModelIDs, [])
        XCTAssertEqual(viewModel.codexSelectedModel, "")
    }

    func testCodexRuntimeDetectionKeepsConfiguredModelEvenWhenNotInDetectedList() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try environment.llmProviderRepository.save(
            LLMProviderRecord(
                id: AgentProviderRegistry.codex.providerID,
                displayName: "Codex",
                providerType: AgentProviderRegistry.codex.providerID,
                baseURL: "local://codex",
                defaultModel: "gpt-5.3-codex-spark",
                apiKeyRef: "codex-local-runtime",
                temperature: 0,
                timeoutSeconds: 120,
                enabled: true,
                isDefault: true,
                lastHealthStatus: "ok",
                lastHealthMessage: nil,
                lastLatencyMS: nil,
                createdAt: now,
                updatedAt: now
            )
        )
        let viewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            codexRuntimeDetector: StubCodexRuntimeDetector(availability: .availableForTests()),
            codexModelListProvider: StubCodexModelListProvider(models: ["gpt-5.5"])
        )

        await viewModel.detectCodexRuntime(forceRefresh: true)

        XCTAssertEqual(viewModel.codexSelectedModel, "gpt-5.3-codex-spark")
        XCTAssertEqual(viewModel.codexModelIDs, ["gpt-5.5", "gpt-5.3-codex-spark"])
        XCTAssertEqual(try environment.llmProviderRepository.provider(id: AgentProviderRegistry.codex.providerID)?.defaultModel, "gpt-5.3-codex-spark")
    }

    func testCodexRuntimeDetectionDoesNotPersistProviderBeforeEnablement() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            codexRuntimeDetector: StubCodexRuntimeDetector(availability: .availableForTests()),
            codexModelListProvider: StubCodexModelListProvider(models: ["gpt-5.4"])
        )

        await viewModel.detectCodexRuntime(forceRefresh: true)

        XCTAssertEqual(viewModel.codexModelIDs, ["gpt-5.4"])
        XCTAssertNil(viewModel.codexProvider)
        XCTAssertEqual(try environment.llmProviderRepository.list(), [])
    }

    func testCodexRuntimeEnablePersistsSelectedRuntimeModel() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            codexRuntimeDetector: StubCodexRuntimeDetector(availability: .availableForTests()),
            codexModelListProvider: StubCodexModelListProvider(models: ["gpt-5.4"])
        )
        await viewModel.detectCodexRuntime(forceRefresh: true)

        viewModel.setCodexEnabled(true)

        let provider = try XCTUnwrap(viewModel.codexProvider)
        XCTAssertEqual(provider.defaultModel, "gpt-5.4")
        XCTAssertTrue(provider.enabled)
        XCTAssertTrue(provider.isDefault)
    }

    func testCodexRuntimeEnableCanBecomeDefaultLLMProvider() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            codexRuntimeDetector: StubCodexRuntimeDetector(availability: .availableForTests()),
            codexModelListProvider: StubCodexModelListProvider(models: ["gpt-5.4"])
        )
        try viewModel.saveProvider(
            id: "text-provider",
            displayName: "Text Provider",
            baseURL: "https://api.example.com",
            model: "model-a",
            apiKey: "secret",
            temperature: 0.2,
            timeoutSeconds: 8,
            enabled: true,
            isDefault: true
        )
        await viewModel.detectCodexRuntime(forceRefresh: true)

        viewModel.setCodexEnabled(true)

        XCTAssertEqual(viewModel.providers.first(where: \.isDefault)?.id, AgentProviderRegistry.codex.providerID)
        XCTAssertTrue(try XCTUnwrap(viewModel.codexProvider).isDefault)
    }

    func testSetDefaultProviderMovesDefaultFlag() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = LLMProviderViewModel(environment: environment, client: StubProviderClient())
        try viewModel.saveProvider(
            id: "primary",
            displayName: "Primary",
            baseURL: "https://api.example.com",
            model: "model-a",
            apiKey: "secret",
            temperature: 0.2,
            timeoutSeconds: 8,
            enabled: true,
            isDefault: true
        )
        try viewModel.saveProvider(
            id: "backup",
            displayName: "Backup",
            baseURL: "https://backup.example.com",
            model: "model-b",
            apiKey: "backup-secret",
            temperature: 0.2,
            timeoutSeconds: 8,
            enabled: true,
            isDefault: false
        )

        try viewModel.setDefaultProvider(id: "backup")

        XCTAssertEqual(viewModel.providers.first(where: { $0.isDefault })?.id, "backup")
        XCTAssertFalse(viewModel.providers.first(where: { $0.id == "primary" })?.isDefault ?? true)
        XCTAssertEqual(viewModel.lastActionMessage, "已设为全局默认模型")
    }
}

private final class CapturingProviderClient: LLMProviderConnecting, @unchecked Sendable {
    private(set) var lastBaseURL: String?
    private(set) var lastAPIKey: String?
    private(set) var lastModel: String?

    func testConnection(
        baseURL: String,
        apiKey: String,
        model: String,
        timeoutSeconds: Double
    ) async throws -> LLMProviderConnectionResult {
        lastBaseURL = baseURL
        lastAPIKey = apiKey
        lastModel = model
        return LLMProviderConnectionResult(message: "OK", latencyMS: 1)
    }

    func listModels(
        baseURL: String,
        apiKey: String,
        timeoutSeconds: Double
    ) async throws -> [String] {
        []
    }
}

private final class StubProviderClient: LLMProviderConnecting, @unchecked Sendable {
    var result: Result<LLMProviderConnectionResult, Error>
    var models: [String]

    init(
        result: Result<LLMProviderConnectionResult, Error> = .success(LLMProviderConnectionResult(message: "OK", latencyMS: 1)),
        models: [String] = []
    ) {
        self.result = result
        self.models = models
    }

    func testConnection(
        baseURL: String,
        apiKey: String,
        model: String,
        timeoutSeconds: Double
    ) async throws -> LLMProviderConnectionResult {
        try result.get()
    }

    func listModels(
        baseURL: String,
        apiKey: String,
        timeoutSeconds: Double
    ) async throws -> [String] {
        models
    }
}

private final class StubCodexRuntimeDetector: AgentRuntimeAvailabilityDetecting, @unchecked Sendable {
    let availability: AgentRuntimeAvailability

    init(availability: AgentRuntimeAvailability) {
        self.availability = availability
    }

    func cachedOrDetect(forceRefresh: Bool) async -> AgentRuntimeAvailability {
        availability
    }
}

@MainActor
private final class StubCodexModelListProvider: AgentRuntimeModelListing, @unchecked Sendable {
    let models: [String]
    private(set) var lastCLIPath: String?

    init(models: [String]) {
        self.models = models
    }

    nonisolated func listModels(cliPath: String) async -> [String] {
        await MainActor.run {
            lastCLIPath = cliPath
            return models
        }
    }
}

private extension AgentRuntimeAvailability {
    static func availableForTests() -> AgentRuntimeAvailability {
        AgentRuntimeAvailability(
            providerID: "codex",
            status: .available,
            detectedAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_800_000_060),
            cliPath: "/tmp/codex",
            cliVersion: "codex-cli test"
        )
    }
}

private actor BlockingProviderClient: LLMProviderConnecting {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var completion: CheckedContinuation<Void, Never>?

    func testConnection(
        baseURL: String,
        apiKey: String,
        model: String,
        timeoutSeconds: Double
    ) async throws -> LLMProviderConnectionResult {
        started = true
        for waiter in startWaiters {
            waiter.resume()
        }
        startWaiters.removeAll()
        await withCheckedContinuation { continuation in
            completion = continuation
        }
        return LLMProviderConnectionResult(message: "OK", latencyMS: 1)
    }

    func listModels(
        baseURL: String,
        apiKey: String,
        timeoutSeconds: Double
    ) async throws -> [String] {
        []
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func complete() {
        completion?.resume()
        completion = nil
    }
}

private final class InMemoryProviderCredentialStore: CredentialStore {
    private var values: [String: String] = [:]

    func readCredential(account: String) throws -> String? {
        values[account]
    }

    func saveCredential(_ value: String, account: String) throws {
        values[account] = value
    }

    func deleteCredential(account: String) throws {
        values.removeValue(forKey: account)
    }

    func value(for account: String) -> String? {
        values[account]
    }
}
