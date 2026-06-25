import Foundation
@preconcurrency import Translation
import VoxFlowScreenshotKit
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
    let clipboardInternalWriteGuard: ClipboardInternalWriteGuard
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
        let clipboardGuard = ClipboardInternalWriteGuard()
        clipboardInternalWriteGuard = clipboardGuard
        fastPasteTextInserter = FastPasteTextInserter(
            shouldRestoreClipboard: {
                outputConfiguration.shouldRestoreClipboard()
            },
            markInternalPasteboardChangeCount: { changeCount in
                clipboardGuard.markInternalWrite(changeCount: changeCount)
            }
        )
        textInsertionCoordinator = TextInsertionCoordinator(
            fastPasteInserter: fastPasteTextInserter,
            simulatedTypingInserter: SimulatedTypingInserter()
        )
        lastResultStore = InMemoryLastResultStore()
        clipboardService = SystemClipboardService(internalWriteGuard: clipboardGuard)
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
    let updatePromptStore: UpdatePromptPresentationStore
    let capabilityModelDownloader: SoniqoCapabilityModelDownloader
    let appleTranslationCoordinator: AppleTranslationCoordinator
    let screenshotTextRefiner: ScreenshotTextRefiner
    let screenshotOCRService: ScreenshotOCRService
    let dictationTargetProvider: WorkspaceDictationTargetProvider
    let voiceTaskCoordinator: VoiceTaskCoordinator
    let focusedTextObserver: AccessibilityFocusedTextObserver
    let correctionObservationScheduler: CorrectionObservationScheduler
    let clipboardAssetMonitor: ClipboardAssetMonitor
    let agentHelperManager: AgentHelperManager?
    let agentRouterClient: AgentRouterClient?

    var llmRefiner: RepositoryBackedLLMRefiner { textRuntime.llmRefiner }
    var fastPasteTextInserter: FastPasteTextInserter { textRuntime.fastPasteTextInserter }
    var lastResultStore: InMemoryLastResultStore { textRuntime.lastResultStore }
    var clipboardInternalWriteGuard: ClipboardInternalWriteGuard { textRuntime.clipboardInternalWriteGuard }
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
        let updatePromptStore = UpdatePromptPresentationStore()
        let capabilityModelDownloader = SoniqoCapabilityModelDownloader()
        AppLogger.general.debug("AppRuntime capability downloader created")
        let appleTranslationCoordinator = AppleTranslationCoordinator()
        let appleSystemTranslationRefiner = AppleSystemTranslationRefiner(
            coordinator: appleTranslationCoordinator
        )
        let screenshotTextRefiner = ScreenshotTextRefiner(
            cloudRefiner: textRuntime.llmRefiner,
            systemTranslator: appleSystemTranslationRefiner,
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
        let overlayControllerFactory: VoxFlowInteractiveScreenshotProvider.OverlayControllerFactory = { onResult in
            let windowFactory = AppKitSelectionOverlayWindowFactory(
                accessoryViewProvider: { configuration in
                    guard configuration.display.isPrimary else { return nil }
                    return AppleTranslationSessionHostFactory.makeNSView(
                        coordinator: appleTranslationCoordinator
                    )
                }
            )
            return SelectionOverlayController(
                windowFactory: windowFactory,
                inlineTranslator: screenshotInlineTranslator,
                onResult: onResult
            )
        }

        let screenshotOCRService = ScreenshotOCRService(
            imageProvider: VoxFlowScreenshotImageProvider(
                screenshotProvider: VoxFlowInteractiveScreenshotProvider(
                    overlayControllerFactory: overlayControllerFactory
                ),
                inlineTranslator: screenshotInlineTranslator
            ),
            ocrRecognizer: screenshotOCRRecognizer,
            translator: screenshotTextRefiner,
            speechService: SystemScreenshotSpeechService(),
            clipboard: textRuntime.clipboardService,
            lastResultStore: textRuntime.lastResultStore,
            assetRepository: environment.assetRepository,
            assetImageDirectory: environment.paths?.screenshotsDirectory
        )
        let dictationTargetProvider = WorkspaceDictationTargetProvider()
        let focusedTextObserver = AccessibilityFocusedTextObserver()
        let correctionCommitObserver = AppKitCorrectionObservationCommitObserver()
        AppLogger.general.debug("AppRuntime observers created")
        let correctionObservationCoordinator = CorrectionObservationCoordinator(
            observer: focusedTextObserver,
            repository: environment.correctionRuleRepository,
            targetRepository: environment.correctionTargetRepository,
            commitObserver: correctionCommitObserver,
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
            },
            onLearningEvent: { event in
                NotificationCenter.default.post(
                    name: .correctionObservationLearningEvent,
                    object: event
                )
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
            assetRepository: environment.assetRepository,
            isFocusedTextFieldSecure: {
                focusedTextObserver.focusedInputIsSecure()
            }
        )
        let clipboardAssetMonitor = ClipboardAssetMonitor(
            repository: environment.assetRepository,
            internalWriteGuard: textRuntime.clipboardInternalWriteGuard,
            imageDataWriter: { data, contentHash in
                let directory = environment.paths?.clipboardAssetsDirectory
                    ?? FileManager.default.temporaryDirectory
                        .appendingPathComponent("VoxFlowClipboardAssets", isDirectory: true)
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                let url = directory.appendingPathComponent("\(contentHash).png", isDirectory: false)
                try data.write(to: url, options: .atomic)
                return url.path
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
                audioCaptureCoordinator: audioCaptureCoordinator,
                updatePromptStore: updatePromptStore
            ),
            updatePromptStore: updatePromptStore,
            capabilityModelDownloader: capabilityModelDownloader,
            appleTranslationCoordinator: appleTranslationCoordinator,
            screenshotTextRefiner: screenshotTextRefiner,
            screenshotOCRService: screenshotOCRService,
            dictationTargetProvider: dictationTargetProvider,
            voiceTaskCoordinator: voiceTaskCoordinator,
            focusedTextObserver: focusedTextObserver,
            correctionObservationScheduler: correctionObservationScheduler,
            clipboardAssetMonitor: clipboardAssetMonitor,
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
