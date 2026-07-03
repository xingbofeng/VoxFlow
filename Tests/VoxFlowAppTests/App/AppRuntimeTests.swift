import XCTest
@testable import VoxFlowApp

@MainActor
final class AppRuntimeTests: XCTestCase {
    func testBootstrapBuildsCoreRuntimeFromContainerFactory() throws {
        let container = try DependencyContainer.inMemory()

        let runtime = AppRuntime.bootstrap(containerFactory: { container })

        XCTAssertEqual(runtime.environment.storageHealth, container.storageHealth)
        XCTAssertEqual(
            runtime.asrCoordinator.dictationConfiguration(for: .simplifiedChinese).engineType,
            .apple
        )
        XCTAssertFalse(runtime.llmRefiner.isConfigured)
    }

    func testBootstrapFallsBackToUnavailableInMemoryRuntimeWhenLiveContainerFails() {
        let runtime = AppRuntime.bootstrap(containerFactory: {
            throw NSError(
                domain: "AppRuntimeTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "disk locked"]
            )
        })

        XCTAssertEqual(
            runtime.environment.storageHealth,
            .unavailable(reason: "Persistent storage failed to initialize: disk locked")
        )
        XCTAssertFalse(runtime.environment.storageHealth.isPersistent)
    }

    func testAgentComposeIsConfiguredWhenCodexRuntimeProviderIsEnabled() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.llmProviderRepository.save(Self.codexProvider(enabled: true))
        try environment.settingsRepository.set(
            RepositoryBackedLLMRefiner.agentProviderIDSettingsKey,
            jsonValue: #""codex""#
        )

        let selection = AppRuntime.selectedAgentRuntimeProvider(environment: environment)

        XCTAssertEqual(selection?.providerID, AgentProviderRegistry.codex.providerID)
        XCTAssertEqual(selection?.model, "gpt-5.5")
        XCTAssertTrue(
            AgentComposeConfiguration.isConfigured(
                llmRefinerConfigured: false,
                environment: environment
            )
        )
    }

    func testAgentComposeIsConfiguredWhenTextLLMIsConfigured() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)

        XCTAssertTrue(
            AgentComposeConfiguration.isConfigured(
                llmRefinerConfigured: true,
                environment: environment
            )
        )
    }

    func testAgentComposeIsConfiguredWhenLocalAgentRuntimeProviderIsEnabled() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.llmProviderRepository.save(Self.localAgentProvider(providerID: "codebuddy", enabled: true))
        try environment.settingsRepository.set(
            RepositoryBackedLLMRefiner.agentProviderIDSettingsKey,
            jsonValue: #""codebuddy""#
        )

        let selection = AppRuntime.selectedAgentRuntimeProvider(environment: environment)

        XCTAssertEqual(selection?.providerID, "codebuddy")
        XCTAssertEqual(selection?.model, "deepseek-v4-flash-202605")
        XCTAssertTrue(
            AgentComposeConfiguration.isConfigured(
                llmRefinerConfigured: false,
                environment: environment
            )
        )
    }

    func testClaudeRuntimeSelectionDoesNotPassConfiguredDisplayModelToCLI() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.llmProviderRepository.save(
            Self.localAgentProvider(
                providerID: AgentProviderRegistry.claude.providerID,
                enabled: true,
                defaultModel: "sonnet"
            )
        )
        try environment.settingsRepository.set(
            RepositoryBackedLLMRefiner.agentProviderIDSettingsKey,
            jsonValue: #""claude""#
        )

        let selection = AppRuntime.selectedAgentRuntimeProvider(environment: environment)

        XCTAssertEqual(selection?.providerID, AgentProviderRegistry.claude.providerID)
        XCTAssertNil(selection?.model)
    }

    func testAgentRuntimeSelectionDoesNotUseEnabledAgentWhenTextLLMIsDefault() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.llmProviderRepository.save(Self.textProvider(isDefault: true))
        try environment.llmProviderRepository.save(Self.codexProvider(enabled: true, isDefault: false))

        let selection = AppRuntime.selectedAgentRuntimeProvider(environment: environment)

        XCTAssertNil(selection)
    }

    func testAgentComposeIsNotConfiguredWhenCodexRuntimeProviderIsDisabledAndLLMIsMissing() throws {
        let container = try DependencyContainer.inMemory()
        let environment = AppEnvironment(container: container)
        try environment.llmProviderRepository.save(Self.codexProvider(enabled: false))

        XCTAssertNil(AppRuntime.selectedAgentRuntimeProvider(environment: environment))
        XCTAssertFalse(
            AgentComposeConfiguration.isConfigured(
                llmRefinerConfigured: false,
                environment: environment
            )
        )
    }

    func testFallbackRuntimeKeepsASRCredentialsInPersistentStoreAcrossRelaunches() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppRuntimeCredentialFallback-\(UUID().uuidString)", isDirectory: true)
        let paths = ApplicationSupportPaths(applicationSupportDirectory: root)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstRuntime = AppRuntime.bootstrap(
            containerFactory: {
                throw NSError(
                    domain: "AppRuntimeTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "migration failed"]
                )
            },
            fallbackCredentialStore: {
                DependencyContainer.defaultCredentialStore(paths: paths)
            }
        )
        try firstRuntime.asrRuntime.manager.saveGroqAPIKey("groq-secret")

        let secondRuntime = AppRuntime.bootstrap(
            containerFactory: {
                throw NSError(
                    domain: "AppRuntimeTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "migration failed"]
                )
            },
            fallbackCredentialStore: {
                DependencyContainer.defaultCredentialStore(paths: paths)
            }
        )

        XCTAssertTrue(secondRuntime.asrRuntime.manager.isGroqConfigured)
        XCTAssertEqual(secondRuntime.asrRuntime.manager.storedGroqAPIKey(), "groq-secret")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: paths.credentialsURL.path),
            "Fallback ASR credentials must be written to the persistent credentials file, not a volatile temp path."
        )
    }

    func testWindowCompositionReceivesAppScopedASRRuntime() throws {
        let root = try Self.repositoryRoot()
        let appRuntime = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/App/AppRuntime.swift"),
            encoding: .utf8
        )
        let windowCoordinator = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/WindowCoordinator.swift"),
            encoding: .utf8
        )
        let mainWindow = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/MainWindowController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appRuntime.contains("let asrRuntime: AppASRRuntime"))
        XCTAssertTrue(appRuntime.contains("let textRuntime: AppTextRuntime"))
        XCTAssertTrue(appRuntime.contains("let audioCaptureCoordinator: AudioCaptureCoordinator"))
        XCTAssertTrue(windowCoordinator.contains("asrRuntime: AppASRRuntime"))
        XCTAssertTrue(windowCoordinator.contains("textRuntime: AppTextRuntime"))
        XCTAssertTrue(windowCoordinator.contains("audioCaptureCoordinator: AudioCaptureCoordinator"))
        XCTAssertTrue(mainWindow.contains("textRuntime: AppTextRuntime"))
        XCTAssertFalse(mainWindow.contains("RepositoryBackedLLMRefiner("))
        XCTAssertFalse(mainWindow.contains("DefaultOutputService("))
        XCTAssertFalse(mainWindow.contains("DefaultTextProcessingPipeline("))
        XCTAssertTrue(mainWindow.contains("ASRProviderViewModel(environment: environment, asrManager: asrRuntime.manager, registry: asrRuntime.registry)"))
        XCTAssertTrue(mainWindow.contains("pipeline: VoxFlowFileTranscriptionPipeline("))
        XCTAssertTrue(mainWindow.contains("makeSegmentWorker: { locale in"))
        XCTAssertTrue(mainWindow.contains("ASRFileTranscriptionWorker(asrManager: asrRuntime.manager, locale: locale)"))
        XCTAssertTrue(mainWindow.contains("nativeFileTranscriber: asrRuntime.manager.makeGroqNativeFileTranscriber()"))
        XCTAssertTrue(mainWindow.contains("translationCoordinator: translationCoordinator"))
        XCTAssertTrue(mainWindow.contains(".appleTranslationSessionHost(translationCoordinator)"))
        XCTAssertTrue(mainWindow.contains("currentASRProviderID: { asrRuntime.manager.effectiveSelectedEngineType.providerID }"))
        XCTAssertTrue(mainWindow.contains("NotesRecordingService("))
        XCTAssertTrue(mainWindow.contains("asrManager: asrRuntime.manager"))
        XCTAssertTrue(mainWindow.contains("audioCaptureCoordinator: audioCaptureCoordinator"))
        XCTAssertFalse(mainWindow.contains("NotesRecordingService()"))
        XCTAssertFalse(mainWindow.contains("FileTranscriptionViewModel(environment: environment)"))
    }

    func testAppDelegateUsesRuntimeOwnedLongLivedServices() throws {
        let root = try Self.repositoryRoot()
        let appRuntime = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/App/AppRuntime.swift"),
            encoding: .utf8
        )
        let appDelegate = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appRuntime.contains("let capabilityModelDownloader: SoniqoCapabilityModelDownloader"))
        XCTAssertTrue(appRuntime.contains("let screenshotTextRefiner: ScreenshotTextRefiner"))
        XCTAssertTrue(appRuntime.contains("let screenshotOCRService: ScreenshotOCRService"))
        XCTAssertTrue(appRuntime.contains("let screenRecordingCoordinator: ScreenRecordingCoordinator"))
        XCTAssertTrue(appRuntime.contains("let voiceTaskCoordinator: VoiceTaskCoordinator"))
        XCTAssertTrue(appRuntime.contains("let clipboardAssetMonitor: ClipboardAssetMonitor"))
        XCTAssertTrue(appRuntime.contains("ClipboardAssetMonitor("))
        XCTAssertTrue(appRuntime.contains("ScreenRecordingCoordinator("))
        XCTAssertTrue(appRuntime.contains("let agentHelperManager: AgentHelperManager?"))
        XCTAssertFalse(appDelegate.contains("private let capabilityModelDownloader = SoniqoCapabilityModelDownloader()"))
        XCTAssertFalse(appDelegate.contains("ScreenshotOCRService("))
        XCTAssertFalse(appDelegate.contains("VoiceTaskCoordinator("))
        XCTAssertFalse(appDelegate.contains("TextTransformService(refiner: llmRefiner)"))
        XCTAssertTrue(appDelegate.contains("TextTransformService(refiner: screenshotTextRefiner)"))
        XCTAssertTrue(appDelegate.contains("clipboardAssetMonitor.start()"))
        XCTAssertTrue(appDelegate.contains("clipboardAssetMonitor.stop()"))
        XCTAssertFalse(appDelegate.contains("AgentHelperManager(paths: paths)"))
    }

    func testTextRuntimeInjectsCurrentWindowOCRContextProviderIntoPipeline() throws {
        let root = try Self.repositoryRoot()
        let appRuntime = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/App/AppRuntime.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appRuntime.contains("let contextBoostProvider = CurrentWindowOCRContextProvider()"))
        XCTAssertTrue(appRuntime.contains("contextBoostProvider: contextBoostProvider"))
        XCTAssertTrue(appRuntime.contains("sessionProvider: contextBoostProvider"))
        XCTAssertTrue(appRuntime.contains("let screenshotInlineTranslator = ScreenshotInlineSelectionTranslator("))
        XCTAssertTrue(appRuntime.contains("inlineTranslator: screenshotInlineTranslator"))
        XCTAssertFalse(appRuntime.contains("imageProvider: SystemInteractiveScreenshotImageProvider()"))
    }

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "AppRuntimeTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Package.swift."]
        )
    }

    private static func textProvider(isDefault: Bool) -> LLMProviderRecord {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return LLMProviderRecord(
            id: "openai",
            displayName: "OpenAI",
            providerType: "openaiCompatible",
            baseURL: "https://api.example.com",
            defaultModel: "gpt-4.1",
            apiKeyRef: "openai-key",
            temperature: 0.7,
            timeoutSeconds: 60,
            enabled: true,
            isDefault: isDefault,
            lastHealthStatus: "ok",
            lastHealthMessage: nil,
            lastLatencyMS: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private static func codexProvider(enabled: Bool, isDefault: Bool = true) -> LLMProviderRecord {
        localAgentProvider(providerID: AgentProviderRegistry.codex.providerID, enabled: enabled, isDefault: isDefault)
    }

    private static func localAgentProvider(
        providerID: String,
        enabled: Bool,
        isDefault: Bool = true,
        defaultModel: String? = nil
    ) -> LLMProviderRecord {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return LLMProviderRecord(
            id: providerID,
            displayName: providerID,
            providerType: providerID,
            baseURL: "local://\(providerID)",
            defaultModel: defaultModel ?? (providerID == AgentProviderRegistry.codex.providerID
                ? "gpt-5.5"
                : "deepseek-v4-flash-202605"),
            apiKeyRef: "\(providerID)-local-runtime",
            temperature: 0.7,
            timeoutSeconds: 60,
            enabled: enabled,
            isDefault: isDefault,
            lastHealthStatus: "ok",
            lastHealthMessage: nil,
            lastLatencyMS: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}
