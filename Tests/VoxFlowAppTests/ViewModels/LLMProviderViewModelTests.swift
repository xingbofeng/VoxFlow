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

    func testCodexRuntimeDetectionPersistsAvailabilityWithoutSelectingIt() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            codexRuntimeDetector: StubCodexRuntimeDetector(availability: .availableForTests()),
            codexModelListProvider: StubCodexModelListProvider(models: ["gpt-5.4"])
        )

        await viewModel.detectCodexRuntime(forceRefresh: true)

        XCTAssertEqual(viewModel.codexModelIDs, ["gpt-5.4"])
        let provider = try XCTUnwrap(viewModel.codexProvider)
        XCTAssertEqual(provider.defaultModel, "gpt-5.4")
        XCTAssertEqual(provider.lastHealthStatus, "ok")
        XCTAssertFalse(provider.enabled)
        XCTAssertFalse(provider.isDefault)
        XCTAssertNil(viewModel.selectedAgentProviderID)
    }

    func testCodexRuntimeDetectionPersistsUnavailableHealthOnExistingRecord() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try environment.llmProviderRepository.save(
            LLMProviderRecord(
                id: AgentProviderRegistry.codex.providerID,
                displayName: "Codex",
                providerType: AgentProviderRegistry.codex.providerID,
                baseURL: "local://codex",
                defaultModel: "gpt-5.4",
                apiKeyRef: "codex-local-runtime",
                temperature: 0,
                timeoutSeconds: 120,
                enabled: true,
                isDefault: false,
                lastHealthStatus: "ok",
                lastHealthMessage: "codex-cli test",
                lastLatencyMS: nil,
                createdAt: now,
                updatedAt: now
            )
        )
        let viewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            codexRuntimeDetector: StubCodexRuntimeDetector(
                availability: .unavailableForTests(
                    providerID: AgentProviderRegistry.codex.providerID,
                    reason: "Codex.app 内置 CLI 不可用"
                )
            ),
            codexModelListProvider: StubCodexModelListProvider(models: [])
        )

        await viewModel.detectCodexRuntime(forceRefresh: true)

        let provider = try XCTUnwrap(environment.llmProviderRepository.provider(id: AgentProviderRegistry.codex.providerID))
        XCTAssertEqual(provider.lastHealthStatus, "error")
        XCTAssertEqual(provider.lastHealthMessage, "Codex.app 内置 CLI 不可用")
        XCTAssertTrue(provider.enabled)
    }

    func testLocalAgentProviderDetectionRefreshesRuntimeModelList() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let adapter = StubLocalAgentProviderAdapter(
            availability: .availableForTests(providerID: "opencode", cliPath: "/tmp/opencode", cliVersion: "opencode 1.0"),
            models: ["kimi-k2", "qwen3-coder"]
        )
        let viewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            localAgentAdapters: ["opencode": adapter]
        )

        await viewModel.detectLocalAgentProvider(providerID: "opencode", forceRefresh: true)

        XCTAssertEqual(viewModel.localAgentAvailability(providerID: "opencode")?.cliVersion, "opencode 1.0")
        XCTAssertEqual(viewModel.localAgentModelIDs(providerID: "opencode"), ["kimi-k2", "qwen3-coder"])
        XCTAssertEqual(adapter.lastCLIPath, "/tmp/opencode")
    }

    func testClaudeDetectionRefreshesStoredModelFromSettings() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try environment.llmProviderRepository.save(
            LLMProviderRecord(
                id: "claude",
                displayName: "Claude Code",
                providerType: "claude",
                baseURL: "local://claude",
                defaultModel: "sonnet",
                apiKeyRef: "claude-local-runtime",
                temperature: 0,
                timeoutSeconds: 120,
                enabled: true,
                isDefault: false,
                lastHealthStatus: "ok",
                lastHealthMessage: nil,
                lastLatencyMS: nil,
                createdAt: now,
                updatedAt: now
            )
        )
        let adapter = StubLocalAgentProviderAdapter(
            availability: .availableForTests(providerID: "claude", cliPath: "/tmp/claude", cliVersion: "2.1.165 (Claude Code)"),
            models: ["deepseek-v4-flash-202605"]
        )
        let viewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            localAgentAdapters: ["claude": adapter]
        )

        await viewModel.detectLocalAgentProvider(providerID: "claude", forceRefresh: true)

        let provider = try XCTUnwrap(environment.llmProviderRepository.provider(id: "claude"))
        XCTAssertEqual(provider.defaultModel, "deepseek-v4-flash-202605")
        XCTAssertEqual(viewModel.localAgentModelIDs(providerID: "claude"), ["deepseek-v4-flash-202605"])
    }

    func testLocalAgentProviderEnablePersistsLLMProviderRecord() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            localAgentAdapters: [
                "opencode": StubLocalAgentProviderAdapter(
                    availability: .availableForTests(providerID: "opencode", cliPath: "/tmp/opencode", cliVersion: "opencode 1.0"),
                    models: ["kimi-k2"]
                )
            ]
        )
        await viewModel.detectLocalAgentProvider(providerID: "opencode", forceRefresh: true)

        viewModel.setLocalAgentProviderEnabled(providerID: "opencode", true)

        let provider = try XCTUnwrap(try environment.llmProviderRepository.provider(id: "opencode"))
        XCTAssertEqual(provider.providerType, "opencode")
        XCTAssertEqual(provider.baseURL, "local://opencode")
        XCTAssertEqual(provider.apiKeyRef, "opencode-local-runtime")
        XCTAssertEqual(provider.defaultModel, "kimi-k2")
        XCTAssertTrue(provider.enabled)
        XCTAssertFalse(provider.isDefault)
        XCTAssertTrue(viewModel.isLocalAgentProviderSelected(providerID: "opencode"))
        XCTAssertEqual(
            try RepositoryBackedLLMRefiner.agentProviderID(settingsRepository: environment.settingsRepository),
            "opencode"
        )
    }

    func testLocalAgentProviderEnableDetectsBeforePersistingWhenModelsAreNotLoaded() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let adapter = StubLocalAgentProviderAdapter(
            availability: .availableForTests(providerID: "opencode", cliPath: "/tmp/opencode", cliVersion: "opencode 1.0"),
            models: ["kimi-k2"]
        )
        let viewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            localAgentAdapters: ["opencode": adapter]
        )

        await viewModel.setLocalAgentProviderEnabledAfterDetection(providerID: "opencode", true)

        XCTAssertEqual(adapter.detectCallCount, 1)
        XCTAssertEqual(adapter.lastCLIPath, "/tmp/opencode")
        let provider = try XCTUnwrap(try environment.llmProviderRepository.provider(id: "opencode"))
        XCTAssertEqual(provider.defaultModel, "kimi-k2")
        XCTAssertTrue(provider.enabled)
    }

    func testAlreadyAvailableLocalAgentSelectionDoesNotWaitForDetection() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try environment.llmProviderRepository.save(
            LLMProviderRecord(
                id: "codebuddy",
                displayName: "CodeBuddy",
                providerType: "codebuddy",
                baseURL: "local://codebuddy",
                defaultModel: "hy3-preview",
                apiKeyRef: "codebuddy-local-runtime",
                temperature: 0,
                timeoutSeconds: 120,
                enabled: true,
                isDefault: false,
                lastHealthStatus: "ok",
                lastHealthMessage: "CodeBuddy ready",
                lastLatencyMS: nil,
                createdAt: now,
                updatedAt: now
            )
        )
        let adapter = StubLocalAgentProviderAdapter(
            availability: .availableForTests(providerID: "codebuddy", cliPath: "/tmp/codebuddy", cliVersion: "CodeBuddy ready"),
            models: ["hy3-preview"]
        )
        let viewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            localAgentAdapters: ["codebuddy": adapter]
        )

        await viewModel.setLocalAgentProviderEnabledAfterDetection(providerID: "codebuddy", true)

        XCTAssertEqual(adapter.detectCallCount, 0)
        XCTAssertEqual(viewModel.selectedAgentProviderID, "codebuddy")
        XCTAssertEqual(
            try RepositoryBackedLLMRefiner.agentProviderID(settingsRepository: environment.settingsRepository),
            "codebuddy"
        )
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
        XCTAssertFalse(provider.isDefault)
        XCTAssertEqual(viewModel.selectedAgentProviderID, AgentProviderRegistry.codex.providerID)
    }

    func testCodexRuntimeEnableDoesNotReplaceDefaultLLMProvider() async throws {
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

        XCTAssertEqual(viewModel.providers.first(where: \.isDefault)?.id, "text-provider")
        XCTAssertFalse(try XCTUnwrap(viewModel.codexProvider).isDefault)
        XCTAssertEqual(viewModel.selectedAgentProviderID, AgentProviderRegistry.codex.providerID)
    }

    func testLocalAgentProviderSelectionTracksAgentSelectionSetting() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            localAgentAdapters: [
                "opencode": StubLocalAgentProviderAdapter(
                    availability: .availableForTests(providerID: "opencode", cliPath: "/tmp/opencode", cliVersion: "opencode 1.0"),
                    models: ["kimi-k2"]
                )
            ]
        )
        await viewModel.setLocalAgentProviderEnabledAfterDetection(providerID: "opencode", true)
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

        XCTAssertTrue(viewModel.isLocalAgentProviderSelected(providerID: "opencode"))
        XCTAssertEqual(try environment.llmProviderRepository.provider(id: "opencode")?.enabled, true)
        XCTAssertEqual(viewModel.defaultProvider?.id, "text-provider")
    }

    func testLocalAgentProviderSelectionReloadsWhenAnotherViewModelChangesSelection() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let settingsViewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            localAgentAdapters: [
                "opencode": StubLocalAgentProviderAdapter(
                    availability: .availableForTests(providerID: "opencode", cliPath: "/tmp/opencode", cliVersion: "opencode 1.0"),
                    models: ["kimi-k2"]
                )
            ]
        )
        let menuViewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            localAgentAdapters: [
                "opencode": StubLocalAgentProviderAdapter(
                    availability: .availableForTests(providerID: "opencode", cliPath: "/tmp/opencode", cliVersion: "opencode 1.0"),
                    models: ["kimi-k2"]
                )
            ]
        )

        await menuViewModel.setLocalAgentProviderEnabledAfterDetection(providerID: "opencode", true)
        await Task.yield()

        XCTAssertTrue(settingsViewModel.isLocalAgentProviderSelected(providerID: "opencode"))
        XCTAssertEqual(settingsViewModel.selectedAgentProviderID, "opencode")
    }

    func testDisablingSelectedLocalAgentClearsAgentSelectionWithoutChangingLLMDefault() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            localAgentAdapters: [
                "opencode": StubLocalAgentProviderAdapter(
                    availability: .availableForTests(providerID: "opencode", cliPath: "/tmp/opencode", cliVersion: "opencode 1.0"),
                    models: ["kimi-k2"]
                )
            ]
        )
        try viewModel.saveProvider(
            id: "first-provider",
            displayName: "First Provider",
            baseURL: "https://first.example.com",
            model: "model-a",
            apiKey: "secret",
            temperature: 0.2,
            timeoutSeconds: 8,
            enabled: true,
            isDefault: false
        )
        try viewModel.saveProvider(
            id: "second-provider",
            displayName: "Second Provider",
            baseURL: "https://second.example.com",
            model: "model-b",
            apiKey: "secret",
            temperature: 0.2,
            timeoutSeconds: 8,
            enabled: true,
            isDefault: false
        )
        await viewModel.setLocalAgentProviderEnabledAfterDetection(providerID: "opencode", true)

        viewModel.setLocalAgentProviderEnabled(providerID: "opencode", false)

        XCTAssertEqual(viewModel.defaultProvider?.id, "first-provider")
        XCTAssertNil(viewModel.selectedAgentProviderID)
        XCTAssertNil(try RepositoryBackedLLMRefiner.agentProviderID(settingsRepository: environment.settingsRepository))
        let agent = try XCTUnwrap(environment.llmProviderRepository.provider(id: "opencode"))
        XCTAssertFalse(agent.enabled)
        XCTAssertFalse(agent.isDefault)
    }

    func testDetectLocalAgentProviderPersistsAvailabilityWithoutSelectingIt() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            localAgentAdapters: [
                "opencode": StubLocalAgentProviderAdapter(
                    availability: .availableForTests(providerID: "opencode", cliPath: "/tmp/opencode", cliVersion: "opencode 1.0"),
                    models: ["kimi-k2"]
                )
            ]
        )

        await viewModel.detectLocalAgentProvider(providerID: "opencode", forceRefresh: true)

        let provider = try XCTUnwrap(environment.llmProviderRepository.provider(id: "opencode"))
        XCTAssertEqual(provider.defaultModel, "kimi-k2")
        XCTAssertEqual(provider.lastHealthStatus, "ok")
        XCTAssertEqual(provider.lastHealthMessage, "opencode 1.0")
        XCTAssertFalse(provider.enabled)
        XCTAssertFalse(provider.isDefault)
    }

    func testDetectLocalAgentProviderPersistsUnavailableHealthOnExistingRecord() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try environment.llmProviderRepository.save(
            LLMProviderRecord(
                id: "opencode",
                displayName: "opencode",
                providerType: "opencode",
                baseURL: "local://opencode",
                defaultModel: "kimi-k2",
                apiKeyRef: "opencode-local-runtime",
                temperature: 0,
                timeoutSeconds: 120,
                enabled: true,
                isDefault: false,
                lastHealthStatus: "ok",
                lastHealthMessage: "opencode 1.0",
                lastLatencyMS: nil,
                createdAt: now,
                updatedAt: now
            )
        )
        let viewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            localAgentAdapters: [
                "opencode": StubLocalAgentProviderAdapter(
                    availability: .unavailableForTests(providerID: "opencode", reason: "opencode CLI 不可用"),
                    models: []
                )
            ]
        )

        await viewModel.detectLocalAgentProvider(providerID: "opencode", forceRefresh: true)

        let provider = try XCTUnwrap(environment.llmProviderRepository.provider(id: "opencode"))
        XCTAssertEqual(provider.displayName, "Opencode")
        XCTAssertEqual(provider.lastHealthStatus, "error")
        XCTAssertEqual(provider.lastHealthMessage, "opencode CLI 不可用")
        XCTAssertTrue(provider.enabled)
    }

    func testSetDefaultProviderRejectsDetectedLocalAgentProvider() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = LLMProviderViewModel(
            environment: environment,
            client: StubProviderClient(),
            localAgentAdapters: [
                "opencode": StubLocalAgentProviderAdapter(
                    availability: .availableForTests(providerID: "opencode", cliPath: "/tmp/opencode", cliVersion: "opencode 1.0"),
                    models: ["kimi-k2"]
                )
            ]
        )
        await viewModel.detectLocalAgentProvider(providerID: "opencode", forceRefresh: true)
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

        XCTAssertThrowsError(try viewModel.setDefaultProvider(id: "opencode")) { error in
            XCTAssertEqual(error as? LLMProviderViewModelError, .providerDisabled)
        }

        let provider = try XCTUnwrap(environment.llmProviderRepository.provider(id: "opencode"))
        XCTAssertFalse(provider.enabled)
        XCTAssertFalse(provider.isDefault)
        XCTAssertTrue(try XCTUnwrap(environment.llmProviderRepository.provider(id: "text-provider")).isDefault)
    }

    func testLoadMovesDefaultFromLegacyLocalAgentToUsableTextProvider() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try environment.llmProviderRepository.save(
            LLMProviderRecord(
                id: "opencode",
                displayName: "Opencode",
                providerType: "opencode",
                baseURL: "local://opencode",
                defaultModel: "kimi-k2",
                apiKeyRef: "opencode-local-runtime",
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
        try environment.llmProviderRepository.save(
            LLMProviderRecord(
                id: "text-provider",
                displayName: "Text Provider",
                providerType: "openaiCompatible",
                baseURL: "https://api.example.com",
                defaultModel: "model-a",
                apiKeyRef: "text-provider-key",
                temperature: 0.2,
                timeoutSeconds: 8,
                enabled: true,
                isDefault: false,
                lastHealthStatus: "ok",
                lastHealthMessage: nil,
                lastLatencyMS: nil,
                createdAt: now,
                updatedAt: now
            )
        )

        let viewModel = LLMProviderViewModel(environment: environment, client: StubProviderClient())

        XCTAssertEqual(viewModel.defaultProvider?.id, "text-provider")
        XCTAssertFalse(try XCTUnwrap(environment.llmProviderRepository.provider(id: "opencode")).isDefault)
        XCTAssertTrue(try XCTUnwrap(environment.llmProviderRepository.provider(id: "text-provider")).isDefault)
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
private final class StubLocalAgentProviderAdapter: LocalAgentProviderChecking, @unchecked Sendable {
    let availability: AgentRuntimeAvailability
    let models: [String]
    private(set) var lastCLIPath: String?
    private(set) var detectCallCount = 0

    init(availability: AgentRuntimeAvailability, models: [String]) {
        self.availability = availability
        self.models = models
    }

    nonisolated func cachedOrDetect(forceRefresh: Bool) async -> AgentRuntimeAvailability {
        await MainActor.run {
            detectCallCount += 1
            return availability
        }
    }

    nonisolated func listModels(cliPath: String) async -> [String] {
        await MainActor.run {
            lastCLIPath = cliPath
            return models
        }
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
        availableForTests(providerID: "codex", cliPath: "/tmp/codex", cliVersion: "codex-cli test")
    }

    static func availableForTests(
        providerID: String,
        cliPath: String,
        cliVersion: String
    ) -> AgentRuntimeAvailability {
        AgentRuntimeAvailability(
            providerID: providerID,
            status: .available,
            detectedAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_800_000_060),
            cliPath: cliPath,
            cliVersion: cliVersion
        )
    }

    static func unavailableForTests(providerID: String, reason: String) -> AgentRuntimeAvailability {
        AgentRuntimeAvailability(
            providerID: providerID,
            status: .unavailable(reason: reason),
            detectedAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_800_000_060),
            cliPath: nil,
            cliVersion: nil
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
