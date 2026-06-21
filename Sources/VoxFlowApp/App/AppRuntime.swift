import Foundation
import VoxFlowTextInsertion

@MainActor
final class AppASRRuntime {
    let manager: ASRManager
    let registry: ASRProviderRegistry

    init(manager: ASRManager) {
        self.manager = manager
        self.registry = ASRProviderRegistry(asrManager: manager)
    }
}

@MainActor
final class AppTextRuntime {
    let llmRefiner: RepositoryBackedLLMRefiner
    let textOutputConfiguration: SettingsBackedTextOutputConfiguration
    let fastPasteTextInserter: FastPasteTextInserter
    let textInsertionCoordinator: TextInsertionCoordinator
    let lastResultStore: InMemoryLastResultStore
    let clipboardService: SystemClipboardService
    let outputService: DefaultOutputService
    let styleSelector: SettingsBackedStyleSelector
    let textPipeline: DefaultTextProcessingPipeline

    init(environment: AppEnvironment) {
        llmRefiner = RepositoryBackedLLMRefiner(
            providerRepository: environment.llmProviderRepository,
            credentialStore: environment.credentialStore
        )
        let outputConfiguration = SettingsBackedTextOutputConfiguration(
            settingsRepository: environment.settingsRepository
        )
        textOutputConfiguration = outputConfiguration
        fastPasteTextInserter = FastPasteTextInserter(
            shouldRestoreClipboard: {
                outputConfiguration.shouldRestoreClipboard()
            }
        )
        textInsertionCoordinator = TextInsertionCoordinator(
            fastPasteInserter: fastPasteTextInserter,
            simulatedTypingInserter: SimulatedTypingInserter()
        )
        lastResultStore = InMemoryLastResultStore()
        clipboardService = SystemClipboardService()
        outputService = DefaultOutputService(
            textInsertionCoordinator: textInsertionCoordinator,
            clipboardService: clipboardService,
            textInputMode: {
                outputConfiguration.textInputMode()
            },
            lastResultStore: lastResultStore
        )
        styleSelector = SettingsBackedStyleSelector(
            styleRepository: environment.styleRepository,
            settingsRepository: environment.settingsRepository,
            classifier: LLMApplicationStyleClassifier(refiner: llmRefiner)
        )
        textPipeline = DefaultTextProcessingPipeline(
            refiner: llmRefiner,
            styleSelector: styleSelector,
            voiceCorrectionProcessor: environment.voiceCorrectionProcessor
        )
    }
}

@MainActor
struct AppRuntime {
    let environment: AppEnvironment
    let asrRuntime: AppASRRuntime
    let textRuntime: AppTextRuntime
    let audioCaptureCoordinator: AudioCaptureCoordinator
    let asrCoordinator: ASRCoordinator
    let windowCoordinator: WindowCoordinator
    let capabilityModelDownloader: SoniqoCapabilityModelDownloader
    let screenshotOCRService: ScreenshotOCRService
    let dictationTargetProvider: WorkspaceDictationTargetProvider
    let voiceTaskCoordinator: VoiceTaskCoordinator
    let agentHelperManager: AgentHelperManager?
    let agentRouterClient: AgentRouterClient?

    var llmRefiner: RepositoryBackedLLMRefiner { textRuntime.llmRefiner }
    var fastPasteTextInserter: FastPasteTextInserter { textRuntime.fastPasteTextInserter }
    var lastResultStore: InMemoryLastResultStore { textRuntime.lastResultStore }
    var clipboardService: SystemClipboardService { textRuntime.clipboardService }
    var outputService: DefaultOutputService { textRuntime.outputService }
    var styleSelector: SettingsBackedStyleSelector { textRuntime.styleSelector }
    var textPipeline: DefaultTextProcessingPipeline { textRuntime.textPipeline }

    static func bootstrap(
        containerFactory: () throws -> DependencyContainer = {
            try DependencyContainer.live()
        }
    ) -> AppRuntime {
        let environment = AppEnvironment(container: makeLaunchContainer(containerFactory: containerFactory))
        let asrManager = ASRManager(
            credentialStore: environment.credentialStore,
            settingsRepository: environment.settingsRepository
        )
        let asrRuntime = AppASRRuntime(manager: asrManager)
        let textRuntime = AppTextRuntime(environment: environment)
        let audioCaptureCoordinator = AudioCaptureCoordinator()
        let capabilityModelDownloader = SoniqoCapabilityModelDownloader()
        let screenshotTextRefiner = ScreenshotTextRefiner(
            cloudRefiner: textRuntime.llmRefiner,
            localTranslator: SoniqoMADLADTranslationRefiner(
                capabilityDownloader: capabilityModelDownloader
            )
        )
        let screenshotOCRService = ScreenshotOCRService(
            imageProvider: SystemInteractiveScreenshotImageProvider(),
            ocrRecognizer: VisionTextOCRRecognizer(),
            translator: screenshotTextRefiner,
            speechService: SystemScreenshotSpeechService(),
            clipboard: textRuntime.clipboardService,
            lastResultStore: textRuntime.lastResultStore
        )
        let dictationTargetProvider = WorkspaceDictationTargetProvider()
        let voiceTaskCoordinator = VoiceTaskCoordinator(
            taskRepository: VoiceTaskRepository(
                databaseQueue: environment.container.databaseQueue,
                clock: environment.clock
            ),
            outputService: textRuntime.outputService,
            textPipeline: textRuntime.textPipeline,
            targetProvider: dictationTargetProvider,
            clock: environment.clock,
            contextPipeline: ContextPipeline(),
            agentRefiner: textRuntime.llmRefiner
        )
        let agentHelperManager = environment.paths.map { AgentHelperManager(paths: $0) }
        let agentRouterClient = environment.paths.map { AgentRouterClient(socketURL: $0.agentRouterSocketURL) }
        return AppRuntime(
            environment: environment,
            asrRuntime: asrRuntime,
            textRuntime: textRuntime,
            audioCaptureCoordinator: audioCaptureCoordinator,
            asrCoordinator: ASRCoordinator(manager: asrRuntime.manager),
            windowCoordinator: WindowCoordinator(
                environment: environment,
                asrRuntime: asrRuntime,
                textRuntime: textRuntime,
                audioCaptureCoordinator: audioCaptureCoordinator
            ),
            capabilityModelDownloader: capabilityModelDownloader,
            screenshotOCRService: screenshotOCRService,
            dictationTargetProvider: dictationTargetProvider,
            voiceTaskCoordinator: voiceTaskCoordinator,
            agentHelperManager: agentHelperManager,
            agentRouterClient: agentRouterClient
        )
    }

    private static func makeLaunchContainer(
        containerFactory: () throws -> DependencyContainer
    ) -> DependencyContainer {
        do {
            return try containerFactory()
        } catch {
            AppLogger.general.error("Failed to initialize app environment: \(error.localizedDescription)")
            try? FileManager.default.createDirectory(
                at: FileManager.default.temporaryDirectory,
                withIntermediateDirectories: true
            )
            return try! DependencyContainer.inMemory(
                storageHealth: .unavailable(
                    reason: "Persistent storage failed to initialize: \(error.localizedDescription)"
                )
            )
        }
    }
}
