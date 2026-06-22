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
        let contextBoostProvider = CurrentWindowOCRContextProvider()
        textPipeline = DefaultTextProcessingPipeline(
            refiner: llmRefiner,
            styleSelector: styleSelector,
            voiceCorrectionProcessor: environment.voiceCorrectionProcessor,
            contextBoostProvider: contextBoostProvider,
            contextBoostCoordinator: ContextBoostPrefetchCoordinator(
                sessionProvider: contextBoostProvider
            )
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
    let focusedTextObserver: AccessibilityFocusedTextObserver
    let correctionObservationScheduler: CorrectionObservationScheduler
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
        AppLogger.general.info("AppRuntime bootstrap start")
        let environment = AppEnvironment(container: makeLaunchContainer(containerFactory: containerFactory))
        AppLogger.general.debug("AppRuntime environment created")
        let asrManager = ASRManager(
            credentialStore: environment.credentialStore,
            settingsRepository: environment.settingsRepository
        )
        AppLogger.general.debug("AppRuntime ASRManager created")
        let asrRuntime = AppASRRuntime(manager: asrManager)
        let textRuntime = AppTextRuntime(environment: environment)
        AppLogger.general.debug("AppRuntime TextRuntime created")
        let audioCaptureCoordinator = AudioCaptureCoordinator()
        let capabilityModelDownloader = SoniqoCapabilityModelDownloader()
        AppLogger.general.debug("AppRuntime capability downloader created")
        let screenshotTextRefiner = ScreenshotTextRefiner(
            cloudRefiner: textRuntime.llmRefiner,
            localTranslator: SoniqoMADLADTranslationRefiner(
                capabilityDownloader: capabilityModelDownloader
            )
        )
        let screenshotOCRRecognizer = VisionTextOCRRecognizer()
        let screenshotInlineTranslator = ScreenshotInlineSelectionTranslator(
            ocrRecognizer: screenshotOCRRecognizer,
            translator: screenshotTextRefiner,
            lastResultStore: textRuntime.lastResultStore
        )
        let screenshotOCRService = ScreenshotOCRService(
            imageProvider: VoxFlowScreenshotImageProvider(
                inlineTranslator: screenshotInlineTranslator
            ),
            ocrRecognizer: screenshotOCRRecognizer,
            translator: screenshotTextRefiner,
            speechService: SystemScreenshotSpeechService(),
            clipboard: textRuntime.clipboardService,
            lastResultStore: textRuntime.lastResultStore
        )
        let dictationTargetProvider = WorkspaceDictationTargetProvider()
        let focusedTextObserver = AccessibilityFocusedTextObserver()
        AppLogger.general.debug("AppRuntime observers created")
        let correctionObservationCoordinator = CorrectionObservationCoordinator(
            observer: focusedTextObserver,
            repository: environment.correctionRuleRepository,
            targetRepository: environment.correctionTargetRepository,
            isAutoLearningEnabled: {
                (try? VoiceCorrectionSettingsStore.bool(
                    .autoLearningEnabled,
                    repository: environment.settingsRepository
                )) ?? VoiceCorrectionSettingsKey.autoLearningEnabled.defaultValue
            },
            autoLearningAppliesImmediately: {
                (try? VoiceCorrectionSettingsStore.bool(
                    .autoLearningAppliesImmediately,
                    repository: environment.settingsRepository
                )) ?? VoiceCorrectionSettingsKey.autoLearningAppliesImmediately.defaultValue
            }
        )
        let correctionObservationScheduler = CorrectionObservationScheduler(
            coordinator: correctionObservationCoordinator
        )
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
            agentRefiner: textRuntime.llmRefiner,
            correctionObservationScheduler: correctionObservationScheduler,
            isFocusedTextFieldSecure: {
                focusedTextObserver.focusedInputIsSecure()
            }
        )
        let agentHelperManager = environment.paths.map { AgentHelperManager(paths: $0) }
        let agentRouterClient = environment.paths.map { AgentRouterClient(socketURL: $0.agentRouterSocketURL) }
        AppLogger.general.debug("AppRuntime wireup complete")
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
            focusedTextObserver: focusedTextObserver,
            correctionObservationScheduler: correctionObservationScheduler,
            agentHelperManager: agentHelperManager,
            agentRouterClient: agentRouterClient
        )
    }

    private static func makeLaunchContainer(
        containerFactory: () throws -> DependencyContainer
    ) -> DependencyContainer {
        do {
            let container = try containerFactory()
            AppLogger.general.debug("makeLaunchContainer obtained persistent container")
            return container
        } catch {
            AppLogger.general.error("Failed to initialize app environment: \(error.localizedDescription)")
            try? FileManager.default.createDirectory(
                at: FileManager.default.temporaryDirectory,
                withIntermediateDirectories: true
            )
            AppLogger.general.warning("makeLaunchContainer fallback to in-memory container")
            return try! DependencyContainer.inMemory(
                storageHealth: .unavailable(
                    reason: "Persistent storage failed to initialize: \(error.localizedDescription)"
                )
            )
        }
    }
}
