import Foundation
@preconcurrency import Translation
import VoxFlowScreenshotKit
import VoxFlowTextInsertion
import VoxFlowTextProcessing

private final class WeakSelectionOverlayControllerBox {
    weak var controller: SelectionOverlayController?
}

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
            credentialStore: environment.credentialStore,
            settingsRepository: environment.settingsRepository
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
            lastResultStore: lastResultStore,
            recentTextOutputRecorder: { text, target in
                clipboardGuard.markRecentTextOutput(
                    text,
                    sourceAppName: target?.appName,
                    sourceAppBundleID: target?.bundleID
                )
            }
        )
        styleSelector = SettingsBackedStyleSelector(
            styleRepository: environment.styleRepository,
            settingsRepository: environment.settingsRepository,
            classifier: LLMApplicationStyleClassifier(refiner: llmRefiner)
        )
        let contextBoostProvider = CurrentWindowOCRContextProvider()
        let structuredLearningService = StructuredCorrectionLearningService(
            repository: environment.correctionTargetRepository,
            termCounter: RepositoryBackedKeyTermCounter(
                repository: environment.correctionTargetRepository,
                clock: environment.clock
            ),
            evidenceRepository: environment.correctionEvidenceRepository
        )
        textPipeline = DefaultTextProcessingPipeline(
            refiner: llmRefiner,
            styleSelector: styleSelector,
            structuredPromptBuilder: StructuredCorrectionPromptBuilder(),
            structuredLearningService: structuredLearningService,
            correctionTargetRepository: environment.correctionTargetRepository,
            correctionEvidenceRepository: environment.correctionEvidenceRepository,
            hotwordFileSyncService: environment.hotwordFileSyncService,
            historyRepository: environment.historyRepository,
            structuredLearningEnabled: {
                (try? VoiceCorrectionSettingsStore.bool(
                    .autoLearningEnabled,
                    repository: environment.settingsRepository
                )) ?? VoiceCorrectionSettingsKey.autoLearningEnabled.defaultValue
            },
            voiceCorrectionProcessor: environment.voiceCorrectionProcessor,
            contextBoostProvider: contextBoostProvider,
            contextBoostCoordinator: ContextBoostPrefetchCoordinator(
                sessionProvider: contextBoostProvider
            ),
            deterministicSettingsProvider: {
                DeterministicTextProcessingSettingsStore.load(
                    storage: SettingsRepositoryKeyValueAdapter(repository: environment.settingsRepository)
                )
            },
            autoMatchSettingsProvider: {
                StyleAutoMatchSettingsStore(settingsRepository: environment.settingsRepository).load()
            }
        )
    }
}

enum AppRuntimeBootstrapError: Error, LocalizedError {
    case persistentStorageUnavailable(reason: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .persistentStorageUnavailable(let reason, _):
            return reason
        }
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
    let screenRecordingCoordinator: ScreenRecordingCoordinator
    let screenRecordingSelectionBridge: ScreenRecordingSelectionBridge
    let dictationTargetProvider: WorkspaceDictationTargetProvider
    let voiceTaskCoordinator: VoiceTaskCoordinator
    let focusedTextObserver: AccessibilityFocusedTextObserver
    let correctionObservationScheduler: CorrectionObservationScheduler
    let clipboardAssetMonitor: ClipboardAssetMonitor
    let agentRuntimeService: DefaultAgentRuntimeService
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
        },
        fallbackCredentialStore: @MainActor () -> CredentialStore? = AppRuntime.persistentFallbackCredentialStore,
        temporaryStorageFallbackDecision: @MainActor (Error) -> Bool = { _ in false }
    ) throws -> AppRuntime {
        AppLogger.general.info("AppRuntime bootstrap start")
        let environment = AppEnvironment(
            container: try makeLaunchContainer(
                containerFactory: containerFactory,
                fallbackCredentialStore: fallbackCredentialStore,
                temporaryStorageFallbackDecision: temporaryStorageFallbackDecision
            )
        )
        AppLogger.general.debug("AppRuntime environment created")
        startHotwordFileSync(environment: environment)
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
        let screenRecordingSelectionBridge = ScreenRecordingSelectionBridge()
        let overlayControllerFactory: VoxFlowInteractiveScreenshotProvider.OverlayControllerFactory = { onResult in
            let windowFactory = AppKitSelectionOverlayWindowFactory(
                accessoryViewProvider: { configuration in
                    guard configuration.display.isPrimary else { return nil }
                    return AppleTranslationSessionHostFactory.makeNSView(
                        coordinator: appleTranslationCoordinator
                    )
                }
            )
            let overlayControllerBox = WeakSelectionOverlayControllerBox()
            let controller = SelectionOverlayController(
                windowFactory: windowFactory,
                inlineTranslator: screenshotInlineTranslator,
                onResult: { [overlayControllerBox] result in
                    if let controller = overlayControllerBox.controller {
                        let controls = ScreenRecordingOverlayControls(
                            showCountdown: { remaining in
                                controller.updateScreenRecordingCountdown(remaining)
                            },
                            showRecordingFrame: {
                                controller.enterActiveScreenRecordingOverlay()
                            },
                            excludedWindowIDs: {
                                controller.currentScreenCaptureExclusionWindowIDs()
                            },
                            close: {
                                controller.close()
                            }
                        )
                        screenRecordingSelectionBridge.handle(result, overlayControls: controls)
                    }
                    onResult(result)
                }
            )
            overlayControllerBox.controller = controller
            return controller
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
        let screenRecordingPaths = environment.paths ?? ApplicationSupportPaths(
            applicationSupportDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("VoxFlowScreenRecording.\(UUID().uuidString)", isDirectory: true)
        )
        try? screenRecordingPaths.ensureDirectories()
        let screenRecordingFileStorage = ScreenRecordingFileStorage(paths: screenRecordingPaths)
        let screenRecordingCoordinator = ScreenRecordingCoordinator(
            service: ScreenRecordingService(fileStorage: screenRecordingFileStorage),
            fileStorage: screenRecordingFileStorage,
            committer: ScreenRecordingCompletionCommitter(
                fileStorage: screenRecordingFileStorage,
                repository: environment.mediaRecordRepository,
                now: { environment.clock.now }
            )
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
            },
            onDiagnostic: { diagnostic in
                AppLogger.dictation.info(
                    "correction_auto_learning_diagnostic reason=\(String(describing: diagnostic.reason)) bundle=\(diagnostic.bundleIdentifier ?? "nil") insertedLen=\(diagnostic.insertedText.count)"
                )
            }
        )
        let correctionObservationScheduler = CorrectionObservationScheduler(
            coordinator: correctionObservationCoordinator
        )
        let runtimeClock = environment.clock
        let agentRuntimeService = DefaultAgentRuntimeService(
            detector: CodexRuntimeAvailabilityDetector(clock: runtimeClock),
            workspaceManager: AgentRuntimeWorkspaceManager(
                paths: environment.paths,
                now: { runtimeClock.now }
            ),
            client: CodexRuntimeClient(clock: runtimeClock),
            localAgentClients: [
                AgentProviderRegistry.voxflowAgent.providerID: BuiltinAgentRuntimeClient(
                    providerRepository: environment.llmProviderRepository,
                    credentialStore: environment.credentialStore,
                    outputService: textRuntime.outputService,
                    historyRepository: environment.historyRepository,
                    clock: runtimeClock
                )
            ]
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
            agentRuntimeService: agentRuntimeService,
            agentRuntimeSelection: {
                Self.selectedAgentRuntimeProvider(environment: environment)
            },
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
                translationCoordinator: appleTranslationCoordinator,
                updatePromptStore: updatePromptStore
            ),
            updatePromptStore: updatePromptStore,
            capabilityModelDownloader: capabilityModelDownloader,
            appleTranslationCoordinator: appleTranslationCoordinator,
            screenshotTextRefiner: screenshotTextRefiner,
            screenshotOCRService: screenshotOCRService,
            screenRecordingCoordinator: screenRecordingCoordinator,
            screenRecordingSelectionBridge: screenRecordingSelectionBridge,
            dictationTargetProvider: dictationTargetProvider,
            voiceTaskCoordinator: voiceTaskCoordinator,
            focusedTextObserver: focusedTextObserver,
            correctionObservationScheduler: correctionObservationScheduler,
            clipboardAssetMonitor: clipboardAssetMonitor,
            agentRuntimeService: agentRuntimeService,
            agentHelperManager: agentHelperManager,
            agentRouterClient: agentRouterClient
        )
    }

    static func selectedAgentRuntimeProvider(
        environment: AppEnvironment
    ) -> AgentRuntimeProviderSelection? {
        let providers = (try? environment.llmProviderRepository.list()) ?? []
        guard let selectedID = try? RepositoryBackedLLMRefiner.agentProviderID(
            settingsRepository: environment.settingsRepository
        ) else {
            return nil
        }
        let selected = providers.first {
            $0.enabled &&
                $0.isLocalAgentProvider &&
                ($0.id.caseInsensitiveCompare(selectedID) == .orderedSame ||
                 $0.providerType.caseInsensitiveCompare(selectedID) == .orderedSame)
        }
        guard let selected else {
            return nil
        }
        return AgentRuntimeProviderSelection(
            providerID: selected.providerType,
            model: agentRuntimeModelArgument(for: selected)
        )
    }

    private static func agentRuntimeModelArgument(for provider: LLMProviderRecord) -> String? {
        guard provider.providerType.caseInsensitiveCompare(AgentProviderRegistry.claude.providerID) != .orderedSame else {
            return nil
        }
        let trimmed = provider.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func startHotwordFileSync(environment: AppEnvironment) {
        guard let service = environment.hotwordFileSyncService else {
            AppLogger.general.info("Hotword file sync unavailable: no Application Support paths")
            return
        }
        do {
            try service.startWatching { result in
                AppLogger.general.info(
                    "hotwords_file_sync_result source=\(result.source.rawValue) " +
                    "valid=\(result.validHotwords) duplicates=\(result.duplicates) " +
                    "restored=\(result.restoredFromBlocklist) failures=\(result.failures)"
                )
            }
        } catch {
            AppLogger.general.error("Hotword file sync failed to start: \(error.localizedDescription)")
        }
    }

    private static func makeLaunchContainer(
        containerFactory: () throws -> DependencyContainer,
        fallbackCredentialStore: @MainActor () -> CredentialStore?,
        temporaryStorageFallbackDecision: @MainActor (Error) -> Bool
    ) throws -> DependencyContainer {
        do {
            let container = try containerFactory()
            AppLogger.general.debug("makeLaunchContainer obtained persistent container")
            return container
        } catch {
            AppLogger.general.error("Failed to initialize app environment: \(error.localizedDescription)")
            guard temporaryStorageFallbackDecision(error) else {
                AppLogger.general.warning("makeLaunchContainer temporary storage fallback declined")
                throw AppRuntimeBootstrapError.persistentStorageUnavailable(
                    reason: "Persistent storage failed to initialize: \(error.localizedDescription)",
                    underlying: error
                )
            }
            try? FileManager.default.createDirectory(
                at: FileManager.default.temporaryDirectory,
                withIntermediateDirectories: true
            )
            AppLogger.general.warning("makeLaunchContainer fallback to in-memory container after explicit decision")
            return try! DependencyContainer.inMemory(
                credentialStore: fallbackCredentialStore(),
                storageHealth: .unavailable(
                    reason: "Persistent storage failed to initialize: \(error.localizedDescription)"
                )
            )
        }
    }

    private static func persistentFallbackCredentialStore() -> CredentialStore? {
        guard let paths = try? ApplicationSupportPaths.live() else {
            AppLogger.general.warning("Persistent fallback credential store unavailable: app support path missing")
            return nil
        }
        return DependencyContainer.defaultCredentialStore(paths: paths)
    }
}
