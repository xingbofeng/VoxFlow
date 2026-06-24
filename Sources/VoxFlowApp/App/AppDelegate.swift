import AppKit
import AVFoundation
import SwiftUI
import VoxFlowTextInsertion

@MainActor
struct AgentDefaultOutputOperation {
    struct Result {
        let finalText: String
        let activatedOriginalTarget: Bool
        let currentTarget: DictationTarget?
        let outputResult: OutputResult
    }

    let process: (String, DictationTarget?) async -> TextProcessingResult
    let activate: (DictationTarget?) async -> Bool
    let currentTarget: () -> DictationTarget?
    let deliver: (String, DictationTarget?, DictationTarget?) async -> OutputResult
    let isCancelled: () -> Bool

    func run(utterance: String, originalTarget: DictationTarget?) async -> Result? {
        let processingResult = await process(utterance, originalTarget)
        guard !isCancelled() else { return nil }

        let trimmedFinalText = processingResult.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalText = trimmedFinalText.isEmpty ? utterance : trimmedFinalText
        let activatedOriginalTarget = await activate(originalTarget)
        guard !isCancelled() else { return nil }

        let target = currentTarget()
        let outputResult = await deliver(finalText, target, originalTarget)
        guard !isCancelled() else { return nil }

        return Result(
            finalText: finalText,
            activatedOriginalTarget: activatedOriginalTarget,
            currentTarget: target,
            outputResult: outputResult
        )
    }
}

enum AgentDefaultOutputHUDCompletion: Equatable {
    case hidden
    case failure(message: String, retainedText: String)

    init(outputResult: OutputResult, finalText: String) {
        switch outputResult.kind {
        case .permissionDenied, .failed:
            self = .failure(message: "写入当前输入框失败", retainedText: finalText)
        case .inserted, .copied, .targetChanged, .cancelled:
            self = .hidden
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - UI

    private var statusItem: NSStatusItem!

    // MARK: - Subsystems

    private let audioRecorder = AudioRecorder()
    private nonisolated let dictationAudioBufferForwarder = ASREngineAudioFrameForwarder()
    private var runtime: AppRuntime?
    private var appEnvironment: AppEnvironment { runtime!.environment }
    private var asrCoordinator: ASRCoordinator { runtime!.asrCoordinator }
    private var windowCoordinator: WindowCoordinator { runtime!.windowCoordinator }
    private var llmRefiner: RepositoryBackedLLMRefiner { runtime!.llmRefiner }
    private var fastPasteTextInserter: FastPasteTextInserter { runtime!.fastPasteTextInserter }
    private var lastResultStore: InMemoryLastResultStore { runtime!.lastResultStore }
    private var clipboardService: SystemClipboardService { runtime!.clipboardService }
    private var outputService: DefaultOutputService { runtime!.outputService }
    private var styleSelector: SettingsBackedStyleSelector { runtime!.styleSelector }
    private var textPipeline: DefaultTextProcessingPipeline { runtime!.textPipeline }
    private var capabilityModelDownloader: SoniqoCapabilityModelDownloader { runtime!.capabilityModelDownloader }
    private var screenshotOCRService: ScreenshotOCRService { runtime!.screenshotOCRService }
    private var voiceTaskCoordinator: VoiceTaskCoordinator { runtime!.voiceTaskCoordinator }
    private var clipboardAssetMonitor: ClipboardAssetMonitor { runtime!.clipboardAssetMonitor }
    private var agentHelperManager: AgentHelperManager? { runtime!.agentHelperManager }
    private lazy var menuBarCoordinator = MenuBarCoordinator(
        asrOptions: Self.makeASRMenuOptions(),
        currentLanguage: { LanguageManager.shared.currentLanguage },
        isASRMenuOptionEnabled: { [asrCoordinator] option in
            asrCoordinator.isMenuOptionEnabled(option)
        },
        isASRMenuOptionSelected: { [asrCoordinator] option in
            asrCoordinator.isMenuOptionSelected(option)
        },
        actions: MenuBarActions(
            selectLanguage: { [weak self] language in self?.selectLanguage(language) },
            selectASRMenuOption: { [weak self] option in self?.selectASREngine(option) },
            selectLLMProvider: { [weak self] providerID in self?.selectLLMProvider(providerID) },
            selectCapabilityModel: { [weak self] kind, modelID in self?.selectCapabilityModel(kind: kind, modelID: modelID) },
            openWorkbench: { [weak self] in self?.openWorkbench() },
            requestSelectionAction: { [weak self] in _ = self?.performWorkflowShortcut(.selectionAction) },
            openSettings: { [weak self] in self?.openSettings() },
            openGitHub: { [weak self] in self?.openGitHub() },
            checkPermissions: { [weak self] in self?.checkPermissions() },
            quit: { [weak self] in self?.quitApp() },
            menuWillOpen: { [weak self] in self?.refreshStatusItemAppearance() }
        ),
        llmProviders: { [weak self] in
            (try? self?.appEnvironment.llmProviderRepository.list()) ?? []
        },
        selectedLLMProviderID: { [weak self] in
            (try? self?.appEnvironment.llmProviderRepository.list().first { $0.enabled && $0.isDefault }?.id) ?? nil
        },
        capabilityModels: { [weak self] kind in
            CapabilityModelCatalog.models(for: kind).map { model in
                var mutable = model
                mutable.isInstalled = CapabilityModelID.isBuiltInOption(model.id) ||
                    (self?.capabilityModelDownloader.isInstalled(modelID: model.id) ?? false)
                return mutable
            }
        },
        selectedCapabilityModelID: { kind in
            CapabilityModelViewModel.selectedModelID(kind: kind)
        },
        isCapabilityModelEnabled: { $0.isInstalled }
    )
    private lazy var recordingPermissionService = RecordingPermissionService(
        engineTypeProvider: { [asrCoordinator] in asrCoordinator.effectiveSelectedEngineType }
    )
    private lazy var pasteLastResultService = PasteLastResultService(
        lastResultStore: lastResultStore,
        clipboardImageProvider: SystemClipboardImageProvider(),
        ocrRecognizer: VisionTextOCRRecognizer(),
        outputService: outputService,
        targetProvider: WorkspaceDictationTargetProvider(),
        isImageOCREnabled: { [weak self] in
            self?.isSettingEnabled(
                SettingsSystemOption.clipboardImageOCR.rawValue,
                defaultValue: SettingsSystemOption.clipboardImageOCR.defaultValue
            ) ?? false
        }
    )
    private lazy var screenshotOCRResultPanelController = ScreenshotOCRResultPanelController(
        service: screenshotOCRService,
        clipboard: clipboardService
    )
    private lazy var selectionHistoryRecorder = SQLiteSelectionHistoryRecorder(
        databaseQueue: appEnvironment.databaseQueue,
        clock: appEnvironment.clock,
        didRecord: { [weak self] in
            self?.appEnvironment.notifyHistoryDidChange()
        }
    )
    private lazy var selectionResultPanelController = SelectionResultPanelController(
        transformService: TextTransformService(refiner: llmRefiner),
        clipboard: clipboardService,
        speech: SystemScreenshotSpeechService(),
        textInserter: fastPasteTextInserter,
        historyRecorder: selectionHistoryRecorder
    )
    private var paletteWindowController: PaletteWindowController?
    private let overlayController = OverlayWindowController()
    private lazy var hudFeatureController = VoiceHUDFeatureController(overlay: overlayController)
    private var pendingASRSelectionFallbackNotice: ASRManager.SelectionFallbackNotice?
    private let systemOutputMuter = SystemOutputMuter()
    private lazy var hotKeyDecisionPerformer = HotKeyDecisionPerformer(
        startNotesRecording: { [weak self] in
            self?.startNotesRecording()
        },
        finishNotesRecording: { [weak self] in
            self?.finishNotesRecording()
        },
        startDictation: { [weak self] action in
            self?.dictationFeatureController.handlePress(action: action)
        },
        releaseDictation: { [weak self] action in
            self?.dictationFeatureController.handleRelease(action: action)
        }
    )
    private lazy var hotKeyFeatureController = makeHotKeyFeatureController()
    private lazy var dictationStatePresentationController = DictationStatePresentationController(
        handleFeedbackState: { [weak self] state in
            self?.recordingFeedbackController?.handle(state)
        },
        handleHUDState: { [weak self] state, activeVoiceAction, shouldShowWaitingIndicator in
            self?.hudFeatureController.handleState(
                state,
                activeVoiceAction: activeVoiceAction,
                shouldShowWaitingIndicator: shouldShowWaitingIndicator
            )
        },
        shouldShowWaitingIndicator: { [weak self] activeVoiceAction in
            self?.asrCoordinator.shouldShowWaitingIndicator(activeVoiceAction: activeVoiceAction) ?? false
        },
        startCancelMonitor: {},
        stopCancelMonitor: {},
        setRefiningStatusVisible: { [weak self] isVisible in
            self?.menuBarCoordinator.setRefiningStatusVisible(isVisible)
        }
    )
    private lazy var dictationFeatureController = DictationFeatureController(
        currentState: { [weak self] in
            self?.dictationOrchestrator.state ?? .idle
        },
        isAgentComposeConfigured: { [weak self] in
            self?.llmRefiner.isConfigured ?? false
        },
        showAgentComposeSetupRequired: { [weak self] in
            self?.hudFeatureController.showTemporaryMessage("请先在设置中配置智能模型", duration: 3.0)
        },
        refreshRecordingPermissionSnapshot: { [weak self] in
            guard let self else {
                return RecordingPermissionSnapshot(
                    engineType: .apple,
                    microphonePermission: .denied,
                    speechPermission: .denied,
                    isResolved: true,
                    hasRequiredPermissions: false
                )
            }
            return self.recordingPermissionService.refreshRecordingPermissions()
        },
        showRecordingPermissionsAlert: { [weak self] in
            self?.showRecordingPermissionsAlert()
        },
        voiceEnhancementEnabled: { [weak self] in
            self?.isSettingEnabled(
                SettingsKey.audioVoiceEnhancementEnabled,
                defaultValue: false
            ) ?? false
        },
        setVoiceEnhancementEnabled: { [weak self] isEnabled in
            self?.audioRecorder.voiceEnhancementEnabled = isEnabled
        },
        currentConfiguration: { [weak self] in
            self?.currentDictationConfiguration() ?? DictationConfiguration(
                engineType: .apple,
                locale: Locale(identifier: "zh-Hans"),
                languageIdentifier: "zh-CN"
            )
        },
        startDictation: { [weak self] configuration, mode in
            guard let self else { return }
            do {
                try self.dictationOrchestrator.start(
                    configuration: configuration,
                    mode: mode
                )
                self.pendingASRSelectionFallbackNotice = nil
            } catch {
                self.pendingASRSelectionFallbackNotice = nil
                throw error
            }
        },
        releaseDictation: { [weak self] in
            self?.dictationOrchestrator.release()
        },
        isRecordingPermissionError: { error in
            error is AudioRecorder.AudioRecorderError
        },
        showRecognitionError: { [weak self] error in
            self?.showRecognitionError(error)
        },
        presentState: { [weak self] state, activeVoiceAction in
            self?.dictationStatePresentationController.handle(
                state,
                activeVoiceAction: activeVoiceAction
            ) ?? DictationStatePresentationResult(shouldClearActiveVoiceAction: false)
        }
    )
    private var recordingFeedbackController: RecordingAudioFeedbackController!
    private var permissionGuideController: PermissionGuideWindowController?
    private var dictationOrchestrator: DictationOrchestrator!
    private var agentComposeHandler: DefaultAgentComposeHandler!
    private var agentDispatchHandler: DefaultAgentDispatchHandler?
    private let logger = AppLogger.general
    private let pendingCorrectionFallback = PendingCorrectionFallbackController()
    private var lastExternalSelectionTarget: DictationTarget?
    private var selectionTargetActivationObserver: NSObjectProtocol?
    private var agentDefaultOutputTask: Task<Void, Never>?

    private func makeHotKeyFeatureController() -> HotKeyFeatureController {
        HotKeyFeatureController(
            monitor: HotKeyMonitorClient.live(keyMonitor: KeyMonitor()),
            delayedPress: DelayedHotKeyPressClient.live(controller: DelayedHotKeyPressController()),
            longPressThreshold: {
                ShortcutManager.shared.longPressThreshold
            },
            currentShortPressBehavior: {
                ShortcutManager.shared.shortPressBehavior
            },
            currentDictationState: { [weak self] in
                self?.dictationOrchestrator.state ?? .idle
            },
            activeVoiceAction: { [weak self] in
                self?.dictationFeatureController.activeVoiceAction
            },
            primaryVoiceAction: { [weak self] in
                self?.isSettingEnabled(
                    SettingsKey.agentDispatchEnabled,
                    defaultValue: false
                ) == true ? .agentDispatch : .dictation
            },
            currentNotesState: {
                let notesCoordinator = NotesCaptureCoordinator.shared
                return HotKeyNotesState(
                    shouldCaptureHotKey: notesCoordinator.shouldCaptureHotKey(),
                    isActive: notesCoordinator.isActive,
                    isRecording: notesCoordinator.isRecording
                )
            },
            performDecision: { [weak self] decision in
                self?.hotKeyDecisionPerformer.perform(decision)
            },
            performWorkflowShortcut: { [weak self] shortcut in
                self?.performWorkflowShortcut(shortcut) ?? false
            },
            scheduleAccessibilityAlert: { alert in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        alert()
                    }
                }
            },
            showAccessibilityAlert: { [weak self] in
                self?.showAccessibilityAlert()
            }
        )
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("application_did_finish_launching")
        NSApp.setActivationPolicy(AppPresentationPolicy.activationPolicy)
        runtime = AppRuntime.bootstrap()
        startSelectionTargetTracking()
        logger.debug("application_runtime_bootstrapped")
        setupDictationOrchestrator()
        recordingFeedbackController = RecordingAudioFeedbackController(
            soundFeedbackEnabled: { [weak self] in self?.isSettingEnabled(SettingsKey.audioSoundFeedbackEnabled, defaultValue: true) ?? true },
            muteWhileRecordingEnabled: { [weak self] in self?.isSettingEnabled(SettingsKey.audioMuteWhileRecordingEnabled, defaultValue: false) ?? false },
            playSound: { [weak self] event in self?.playFeedbackSound(event) },
            setMuted: { [weak self] muted in self?.systemOutputMuter.setMuted(muted) }
        )

        setupStatusItem()
        if AppPresentationPolicy.usesMainMenu {
            setupMainMenu()
        }
        setupMenu()

        audioRecorder.delegate = self

        hotKeyFeatureController.start()
        clipboardAssetMonitor.start()

        Task {
            await resolveRecordingPermissions()
        }

        if AppPresentationPolicy.opensWorkbenchOnLaunch {
            windowCoordinator.showMainWindow()
        }
        logger.debug("application_launch_completed")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        logger.debug("application_should_handle_reopen hasVisibleWindows=\(flag)")
        guard AppPresentationPolicy.restoresWorkbenchOnReopen else {
            return true
        }
        windowCoordinator.showMainWindow()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("application_will_terminate")
        hotKeyFeatureController.stop()
        audioRecorder.stop()
        dictationOrchestrator.cancel()
        agentDefaultOutputTask?.cancel()
        agentDispatchHandler?.cancel()
        clipboardAssetMonitor.stop()
        stopSelectionTargetTracking()
        agentHelperManager?.stopRouter()
    }

    private func setupDictationOrchestrator() {
        logger.debug("setup_dictation_orchestrator")
        let targetProvider = runtime!.dictationTargetProvider
        agentComposeHandler = DefaultAgentComposeHandler(
            coordinator: voiceTaskCoordinator,
            styleSelector: styleSelector
        )
        agentComposeHandler.onStageChange = { [weak self] stage in
            self?.hudFeatureController.handleAgentComposeStage(stage)
        }
        agentComposeHandler.onStreamingDelta = { [weak self] partialText in
            self?.hudFeatureController.updateStreamingText(partialText)
        }
        overlayController.onSelectionActionSelected = { [weak self] action, selectedText in
            self?.handleSelectionActionSelected(action: action, selectedText: selectedText)
        }
        if let helperManager = agentHelperManager,
           let agentRouterClient = runtime!.agentRouterClient {
            Task { @MainActor in
                do {
                    try await helperManager.startRouter()
                    logger.info("agent_router_started")
                } catch {
                    logger.error("agent_router_start_failed \(error.localizedDescription)")
                    AppLogger.general.error("Failed to start Agent Router: \(error.localizedDescription)")
                }
            }
            let dispatchCoordinator = AgentDispatchCoordinator(
                router: agentRouterClient,
                modelResolver: LLMAgentTargetResolver(
                    refiner: llmRefiner,
                    isEnabled: { [weak self] in
                        await MainActor.run {
                            self?.settingString(
                                SettingsKey.agentDispatchUnresolvedBehavior,
                                defaultValue: "confirm"
                            ) == "model"
                        }
                    }
                ),
                directSendEnabled: { [weak self] in
                    self?.isSettingEnabled(
                        SettingsKey.agentDispatchExactDirectEnabled,
                        defaultValue: true
                    ) ?? true
                },
                unresolvedBehavior: { [weak self] in
                    self?.settingString(
                        SettingsKey.agentDispatchUnresolvedBehavior,
                        defaultValue: "confirm"
                    ) ?? "confirm"
                }
            )
            let handler = DefaultAgentDispatchHandler(
                taskCoordinator: voiceTaskCoordinator,
                dispatchCoordinator: dispatchCoordinator,
                clipboardService: clipboardService
            )
            handler.onPresentationChange = { [weak self] presentation in
                self?.hudFeatureController.handleAgentDispatch(presentation)
            }
            overlayController.onAgentCandidateSelected = { [weak handler] agentID, utterance in
                Task { @MainActor in
                    let intent = AgentConfirmationIntent.parse(utterance)
                    await handler?.confirm(
                        agentID: agentID,
                        utterance: utterance,
                        message: intent.message,
                        alias: intent.alias
                    )
                }
            }
            overlayController.onAgentDefaultOutputSelected = { [weak self, weak handler] utterance in
                handler?.beginDefaultOutput()
                self?.agentDefaultOutputTask?.cancel()
                self?.agentDefaultOutputTask = Task { @MainActor in
                    await self?.handleAgentDefaultOutputSelected(
                        utterance: utterance,
                        handler: handler
                    )
                }
            }
            agentDispatchHandler = handler
        }
        dictationOrchestrator = DictationOrchestrator(
            asrEngineFactory: asrCoordinator,
            audioRecorder: audioRecorder,
            audioBufferForwarder: dictationAudioBufferForwarder,
            textPipeline: textPipeline,
            textInjector: fastPasteTextInserter,
            historyRepository: appEnvironment.historyRepository,
            clock: appEnvironment.clock,
            targetProvider: targetProvider,
            outputService: outputService,
            agentComposeHandler: agentComposeHandler,
            agentDispatchHandler: agentDispatchHandler,
            audioCaptureCoordinator: runtime!.audioCaptureCoordinator,
            correctionObservationScheduler: runtime!.correctionObservationScheduler,
            isFocusedTextFieldSecure: { [weak self] in
                self?.runtime?.focusedTextObserver.focusedInputIsSecure() ?? false
            },
            assetRepository: appEnvironment.assetRepository
        )
        dictationOrchestrator.onStateChange = { [weak self] state in
            self?.handleDictationStateChange(state)
        }
        dictationOrchestrator.onTranscriptionUpdate = { [weak self] text, isRefining in
            self?.hudFeatureController.updateTranscription(text, isRefining: isRefining)
        }
        dictationOrchestrator.onProcessingStarted = { [weak self] text in
            self?.hudFeatureController.processingStarted(text)
        }
        dictationOrchestrator.onHistorySaved = { [weak self] in
            self?.appEnvironment.notifyHistoryDidChange()
        }
        dictationOrchestrator.onAgentComposeCompleted = { [weak self] result in
            self?.appEnvironment.notifyHistoryDidChange()
            self?.showAgentComposeResult(result)
        }
        dictationOrchestrator.onAgentDispatchPresentation = { [weak self] presentation in
            self?.hudFeatureController.handleAgentDispatch(presentation)
            self?.appEnvironment.notifyHistoryDidChange()
        }
        dictationOrchestrator.onError = { [weak self] error in
            self?.dictationFeatureController.handleRecognitionError(error)
        }
        logger.debug("setup_dictation_orchestrator_completed")
    }

    private func handleAgentDefaultOutputSelected(
        utterance: String,
        handler: DefaultAgentDispatchHandler?
    ) async {
        let originalTarget = handler?.activeTarget ?? runtime?.dictationTargetProvider.currentTarget()
        let currentTargetBeforeCorrection = runtime?.dictationTargetProvider.currentTarget()
        let enteredCorrection = true
        AppLogger.general.info(
            "agent_default_output_started originalTarget=\(Self.logDescription(for: originalTarget)) currentTarget=\(Self.logDescription(for: currentTargetBeforeCorrection)) activatedOriginalTarget=false enteredCorrection=\(enteredCorrection) outputKind=pending fallbackReason=none"
        )
        hudFeatureController.render(.processing)
        hudFeatureController.processingStarted(utterance)
        let fallbackToken = pendingCorrectionFallback.begin(rawText: utterance)
        var hudCompletion = AgentDefaultOutputHUDCompletion.hidden
        defer {
            pendingCorrectionFallback.finish(fallbackToken)
            switch hudCompletion {
            case .hidden:
                hudFeatureController.render(.hidden)
            case let .failure(message, retainedText):
                hudFeatureController.handleAgentDispatch(.failure(
                    message: message,
                    retainedText: retainedText
                ))
            }
        }
        let operation = AgentDefaultOutputOperation(
            process: { [textPipeline] text, target in
                await textPipeline.process(
                    text,
                    target: target,
                    onRefinedTextUpdate: { _ in }
                )
            },
            activate: { target in
                await DictationTargetActivation.activate(target)
            },
            currentTarget: { [weak self] in
                self?.runtime?.dictationTargetProvider.currentTarget()
            },
            deliver: { [outputService] text, target, originalTarget in
                await outputService.deliver(
                    text: text,
                    mode: .dictation,
                    target: target,
                    originalTarget: originalTarget
                )
            },
            isCancelled: { Task.isCancelled }
        )
        guard let result = await operation.run(
            utterance: utterance,
            originalTarget: originalTarget
        ) else { return }
        hudCompletion = AgentDefaultOutputHUDCompletion(
            outputResult: result.outputResult,
            finalText: result.finalText
        )
        AppLogger.general.info(
            "agent_default_output_completed originalTarget=\(Self.logDescription(for: originalTarget)) currentTarget=\(Self.logDescription(for: result.currentTarget)) activatedOriginalTarget=\(result.activatedOriginalTarget) enteredCorrection=\(enteredCorrection) outputKind=\(result.outputResult.kind.rawValue) fallbackReason=\(Self.fallbackReason(for: result.outputResult))"
        )
        do {
            try handler?.completeFallbackInput(
                finalText: result.finalText,
                outputResult: result.outputResult
            )
        } catch {
            AppLogger.general.error("Failed to complete Agent Dispatch default output: \(error.localizedDescription)")
        }
    }

    private static func logDescription(for target: DictationTarget?) -> String {
        guard let target else { return "nil" }
        let hasWindowTitle = target.windowTitle?.isEmpty == false
        return "{bundleID=\(target.bundleID ?? "nil"),appName=\(target.appName ?? "nil"),pid=\(target.pid.map { String($0) } ?? "nil"),windowID=\(target.windowID ?? "nil"),hasWindowTitle=\(hasWindowTitle)}"
    }

    private static func fallbackReason(for result: OutputResult) -> String {
        switch result {
        case .injected, .copied, .cancelled:
            return "none"
        case let .targetChanged(reason),
             let .permissionDenied(reason),
             let .injectionFailed(reason),
             let .copyFailed(reason):
            return reason
        }
    }

    private func handleDictationStateChange(_ state: DictationState) {
        dictationFeatureController.handleStateChange(state)
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        logger.debug("setup_status_item")
        statusItem = NSStatusBar.system.statusItem(withLength: StatusBarIcon.preferredLength)
        if !StatusBarIcon.configure(statusItem) {
            AppLogger.general.error("Status item button unavailable during menu bar setup.")
        }
    }

    // MARK: - Menu

    private func setupMainMenu() {
        logger.debug("setup_main_menu")
        NSApplication.shared.mainMenu = AppMainMenuBuilder.makeMainMenu()
    }

    private func setupMenu() {
        logger.debug("setup_menu")
        menuBarCoordinator.attach(to: statusItem)
    }

    // MARK: - Menu Actions

    private func selectLanguage(_ language: RecognitionLanguage) {
        logger.debug("menu_select_language language=\(language)")
        LanguageManager.shared.setLanguage(language)
    }

    private func openSettings() {
        logger.debug("menu_open_settings")
        windowCoordinator.showSettings(tab: .asr)
    }

    private func selectLLMProvider(_ providerID: String) {
        logger.debug("menu_select_llm_provider providerID=\(providerID)")
        do {
            let viewModel = LLMProviderViewModel(environment: appEnvironment)
            try viewModel.setDefaultProvider(id: providerID)
        } catch {
            AppLogger.general.error("Failed to select LLM provider from menu: \(error.localizedDescription)")
        }
    }

    private func selectCapabilityModel(kind: CapabilityModelKind, modelID: String) {
        logger.debug("menu_select_capability_model kind=\(kind) modelID=\(modelID)")
        CapabilityModelViewModel.setSelectedModelID(modelID, kind: kind)
    }

    private func openWorkbench() {
        logger.debug("menu_open_workbench")
        windowCoordinator.showMainWindow()
    }

    private func openGitHub() {
        logger.debug("menu_open_github")
        guard let url = URL(string: HelpExternalLinks.githubRepository) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - ASR Engine Menu

    static func makeASRMenuOptions() -> [ASRMenuModel] {
        ASRMenuOptions.makeOptions()
    }

    private func selectASREngine(_ option: ASRMenuModel) {
        logger.debug("menu_select_asr_engine title=\(option.title) value=\(option.engineType.rawValue)")
        asrCoordinator.selectMenuOption(option)
    }

    // MARK: - Quit

    private func quitApp() {
        logger.info("menu_quit_app")
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Key Monitor

    private func showAccessibilityAlert() {
        let shortcutName = Self.keyDisplayName(for: ShortcutManager.shared.shortcutKeyCode)
        presentPermissionGuide(
            title: "需要辅助功能权限",
            subtitle: "码上写需要辅助功能权限来监听 \(shortcutName) 并向当前应用输入转写文本。",
            items: [
                PermissionStatusItem(
                    title: "辅助功能",
                    subtitle: "监听全局快捷键并输入文字",
                    systemImage: "accessibility",
                    status: "未授权",
                    granted: false
                )
            ],
            settingsURL: PermissionGuideContent.systemSettingsURL(for: .accessibility)
        )
    }

    private static func keyDisplayName(for keyCode: Int64) -> String {
        KeyCodeMapping.displayName(for: keyCode)
    }

    // MARK: - Hot Key Handling

    private func startNotesRecording() {
        logger.debug("hotkey_start_notes_recording")
        Task { @MainActor in
            await NotesCaptureCoordinator.shared.startRecording?()
        }
    }

    private func finishNotesRecording() {
        logger.debug("hotkey_finish_notes_recording")
        NotesCaptureCoordinator.shared.finishRecording?()
    }

    private func currentDictationConfiguration() -> DictationConfiguration {
        if let notice = asrCoordinator.selectionFallbackNotice {
            AppLogger.dictation.warning(
                "ASR selection fallback selected=\(notice.selectedEngineType.rawValue) effective=\(notice.effectiveEngineType.rawValue)"
            )
            pendingASRSelectionFallbackNotice = notice
        } else {
            pendingASRSelectionFallbackNotice = nil
        }
        return asrCoordinator.dictationConfiguration(for: LanguageManager.shared.currentLanguage)
    }

    // MARK: - Error Handling

    private func resolveRecordingPermissions() async {
        logger.debug("resolve_recording_permissions")
        _ = await recordingPermissionService.resolveRecordingPermissions()
    }

    private func checkAllPermissions() {
        let recordingPermissions = recordingPermissionService.refreshRecordingPermissions()
        let accessibility = AXIsProcessTrusted()
        let screenRecording = CGPreflightScreenCaptureAccess()
        logger.debug(
            "permission_snapshot microphone=\(recordingPermissions.microphonePermission) speech=\(recordingPermissions.speechPermission) accessibility=\(accessibility) screenRecording=\(screenRecording) engine=\(recordingPermissions.engineType)"
        )

        presentPermissionGuide(
            title: "权限检查",
            subtitle: "确认码上写录音、转写和文本输入所需权限。",
            items: PermissionGuideContent.allPermissionItems(
                microphonePermission: recordingPermissions.microphonePermission,
                speechPermission: recordingPermissions.speechPermission,
                accessibilityTrusted: accessibility,
                screenRecordingGranted: screenRecording,
                engineType: recordingPermissions.engineType
            ),
            settingsURL: PermissionGuideContent.privacySettingsURL
        )
    }

    private func checkPermissions() {
        logger.debug("check_permissions_requested")
        checkAllPermissions()
    }

    private func showRecordingPermissionsAlert() {
        logger.debug("show_recording_permissions_alert engineType=\(asrCoordinator.effectiveSelectedEngineType)")
        let message = PermissionSummary.recordingPermissionAlertText(
            engineType: asrCoordinator.effectiveSelectedEngineType
        )
        presentPermissionGuide(
            title: message.title,
            subtitle: message.body,
            items: recordingPermissionItems(),
            settingsURL: PermissionGuideContent.privacySecuritySettingsURL
        )
    }

    private func recordingPermissionItems() -> [PermissionStatusItem] {
        let snapshot = recordingPermissionService.refreshRecordingPermissions()
        return PermissionGuideContent.recordingPermissionItems(
            microphonePermission: snapshot.microphonePermission,
            speechPermission: snapshot.speechPermission
        )
    }

    private func presentPermissionGuide(
        title: String,
        subtitle: String,
        items: [PermissionStatusItem],
        settingsURL: URL?
    ) {
        permissionGuideController = PermissionGuideWindowController(
            title: title,
            subtitle: subtitle,
            items: items,
            settingsURL: settingsURL
        )
        permissionGuideController?.present()
    }

    private func showRecognitionError(_ error: Error) {
        AppLogger.dictation.error("语音识别错误: \(error.localizedDescription)")
        if let taskID = agentComposeHandler?.lastFailedTaskID {
            let feedback = RecognitionErrorHUDPresentation.feedback(
                for: error,
                recovery: .openHistoryDetail
            )
            hudFeatureController.handleRecognitionErrorFeedback(feedback) { [weak self] in
                self?.openHistoryDetail(taskID)
            }
            return
        }
        // For dictation errors, try to open the last voice task detail; otherwise open home page.
        let feedback = RecognitionErrorHUDPresentation.feedback(
            for: error,
            recovery: .openMainWindow
        )
        hudFeatureController.handleRecognitionErrorFeedback(feedback) { [weak self] in
            self?.windowCoordinator.showMainWindow()
        }
    }

    private func openHistoryDetail(_ id: String) {
        windowCoordinator.showMainWindow()
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.appEnvironment.requestOpenHistoryDetail(id)
        }
    }

    private func showAgentComposeResult(_ result: OutputResult) {
        switch result {
        case .copied:
            hudFeatureController.handleWorkflowFeedback(.agentComposeCopied)
        case .targetChanged:
            hudFeatureController.handleWorkflowFeedback(.agentComposeTargetChangedCopied)
        case .permissionDenied:
            hudFeatureController.handleWorkflowFeedback(.agentComposePermissionDeniedCopied)
        case .injectionFailed:
            hudFeatureController.handleWorkflowFeedback(.agentComposeInjectionFailedCopied)
        case .copyFailed:
            hudFeatureController.handleWorkflowFeedback(.agentComposeCopyFailed { [weak self] in
                self?.copyLastResultToClipboardForRecovery()
            })
        case .injected:
            hudFeatureController.handleWorkflowFeedback(.agentComposeInjected)
        case .cancelled:
            break
        }
    }

    private func handleEscapeKey() -> Bool {
        if let rawText = pendingCorrectionFallback.consumeRawText() {
            agentDefaultOutputTask?.cancel()
            agentDefaultOutputTask = nil
            Task { @MainActor [weak self] in
                await self?.deliverPendingCorrectionFallback(rawText)
            }
            return true
        }

        let didOutputRawText = dictationOrchestrator.handleEscapeKey()
        guard !didOutputRawText else { return true }
        agentDispatchHandler?.cancel()
        hudFeatureController.render(.hidden)
        return false
    }

    private func deliverPendingCorrectionFallback(_ rawText: String) async {
        let originalTarget = agentDispatchHandler?.activeTarget ?? runtime?.dictationTargetProvider.currentTarget()
        await DictationTargetActivation.activate(originalTarget)
        let outputResult = await outputService.deliver(
            text: rawText,
            mode: .dictation,
            target: runtime?.dictationTargetProvider.currentTarget(),
            originalTarget: originalTarget
        )
        do {
            try agentDispatchHandler?.completeFallbackInput(
                finalText: rawText,
                outputResult: outputResult
            )
        } catch {
            AppLogger.general.error(
                "Failed to complete pending correction fallback input: \(error.localizedDescription)"
            )
        }

        switch outputResult.kind {
        case .permissionDenied, .failed:
            hudFeatureController.handleAgentDispatch(.failure(
                message: "写入当前输入框失败",
                retainedText: rawText
            ))
        case .inserted, .copied, .targetChanged, .cancelled:
            break
        }
    }

    @objc func performScreenshotOCRFromMenu(_ sender: Any?) {
        _ = performWorkflowShortcut(.screenshotOCR)
    }

    private func performWorkflowShortcut(_ shortcut: HotKeyWorkflowShortcut) -> Bool {
        logger.debug("workflow_shortcut_requested shortcut=\(shortcut)")
        switch shortcut {
        case .palette:
            logger.debug("workflow_shortcut_palette")
            showPalette()
            return true
        case .clipboardImageOCR:
            logger.debug("workflow_shortcut_clipboard_image_ocr")
            guard shouldStartEphemeralWorkflow(shortcut) else {
                return true
            }
            let lease: VoiceWorkflowLease
            do {
                lease = try voiceTaskCoordinator.beginEphemeralWorkflow(kind: .clipboardImageOCR)
            } catch {
                hudFeatureController.handleWorkflowFeedback(.clipboardImageOCRAlreadyRunning)
                return true
            }
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.handleClipboardImageOCRShortcut(lease: lease)
            }
            voiceTaskCoordinator.registerEphemeralWorkflowTask(task, for: lease)
            return true
        case .screenshotOCR:
            logger.debug("workflow_shortcut_screenshot_ocr")
            guard shouldStartEphemeralWorkflow(shortcut) else {
                return true
            }
            let shouldPresentHUD = shouldPresentEphemeralWorkflowHUD(shortcut)
            let lease: VoiceWorkflowLease
            do {
                lease = try voiceTaskCoordinator.beginEphemeralWorkflow(kind: .screenshotOCR)
            } catch {
                if shouldPresentHUD {
                    hudFeatureController.showTemporaryMessage("屏幕 OCR 正在处理中", duration: 2.2)
                }
                return true
            }
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.handleScreenshotOCRShortcut(
                    lease: lease,
                    shouldPresentHUD: shouldPresentHUD
                )
            }
            voiceTaskCoordinator.registerEphemeralWorkflowTask(task, for: lease)
            return true
        case .selectionAction:
            logger.debug("workflow_shortcut_selection_action")
            guard shouldStartEphemeralWorkflow(shortcut) else {
                return true
            }
            showSelectionActionCard()
            return true
        case .selectionTranslate:
            logger.debug("workflow_shortcut_selection_translate")
            guard shouldStartEphemeralWorkflow(shortcut) else {
                return true
            }
            performSelectionAction(.translate)
            return true
        case .selectionSummarize:
            logger.debug("workflow_shortcut_selection_summarize")
            guard shouldStartEphemeralWorkflow(shortcut) else {
                return true
            }
            performSelectionAction(.summarize)
            return true
        case .selectionAgent:
            logger.debug("workflow_shortcut_selection_agent")
            guard shouldStartEphemeralWorkflow(shortcut) else {
                return true
            }
            performSelectionAction(.agent)
            return true
        case .cancel:
            logger.debug("workflow_shortcut_cancel")
            if pendingCorrectionFallback.hasPending {
                _ = handleEscapeKey()
                return true
            }
            if voiceTaskCoordinator.activeTaskID(for: .clipboardImageOCR) != nil {
                voiceTaskCoordinator.cancelEphemeralWorkflow(kind: .clipboardImageOCR)
                return true
            }
            if voiceTaskCoordinator.activeTaskID(for: .screenshotOCR) != nil {
                voiceTaskCoordinator.cancelEphemeralWorkflow(kind: .screenshotOCR)
                return true
            }
            if voiceTaskCoordinator.activeTaskID(for: .agentDispatch) != nil {
                _ = handleEscapeKey()
                return true
            }
            guard !dictationOrchestrator.state.isIdle else {
                return false
            }
            _ = handleEscapeKey()
            return true
        }
    }

    private func performSelectionAction(_ action: SelectionActionKind) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await restoreLastExternalSelectionTargetIfNeeded()
            let provider = SelectionTextProvider(
                adapter: SystemSelectionAcquisitionAdapter(
                    accessibilityReader: SystemSelectionAccessibilityReader(),
                    copyPerformer: SystemSelectionCopyPerformer(),
                    appContext: SystemSelectionAppContextProvider()
                ),
                configuration: .userInitiated(
                    frontmostBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                )
            )
            switch await provider.snapshotResult() {
            case .success(let snapshot):
                handleSelectionActionSelected(action: action, selectedText: snapshot.text)
            case .failure(let failure):
                hudFeatureController.showTemporaryMessage(failure.userMessage, duration: 1.8)
            }
        }
    }

    private func showPalette() {
        logger.debug("palette_show_requested")
        if paletteWindowController?.isVisible == true {
            paletteWindowController?.close()
            return
        }
        if paletteWindowController == nil {
            paletteWindowController = PaletteWindowController(
                repository: appEnvironment.assetRepository,
                actionService: AssetActionService(
                    textInserter: fastPasteTextInserter,
                    internalWriteGuard: runtime!.clipboardInternalWriteGuard,
                    repository: appEnvironment.assetRepository
                ),
                onCommand: { [weak self] command in
                    self?.handlePaletteCommand(command)
                }
            )
        }
        paletteWindowController?.present()
    }

    private func handlePaletteCommand(_ command: PaletteCommand) {
        switch command {
        case .recentAssets, .assetHistory:
            break
        case .screenshotOCR:
            paletteWindowController?.close()
            _ = performWorkflowShortcut(.screenshotOCR)
        case .startAgentCompose:
            paletteWindowController?.close()
            togglePaletteVoiceAction(.agentCompose)
        case .startAgentDispatch:
            paletteWindowController?.close()
            togglePaletteVoiceAction(.agentDispatch)
        case .startDictation:
            paletteWindowController?.close()
            togglePaletteVoiceAction(.dictation)
        }
    }

    private func togglePaletteVoiceAction(_ action: VoiceAction) {
        if dictationFeatureController.activeVoiceAction == action {
            dictationFeatureController.handleRelease(action: action)
        } else {
            dictationFeatureController.handlePress(action: action)
        }
    }

    private func showSelectionActionCard() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let mouseAnchor = NSRect(
                x: NSEvent.mouseLocation.x,
                y: NSEvent.mouseLocation.y,
                width: 1,
                height: 1
            )
            await restoreLastExternalSelectionTargetIfNeeded()
            let provider = SelectionTextProvider(
                adapter: SystemSelectionAcquisitionAdapter(
                    accessibilityReader: SystemSelectionAccessibilityReader(),
                    copyPerformer: SystemSelectionCopyPerformer(),
                    appContext: SystemSelectionAppContextProvider()
                ),
                configuration: .userInitiated(
                    frontmostBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                )
            )
            switch await provider.snapshotResult() {
            case .success(let snapshot):
                let anchor = snapshot.selectionBounds ?? mouseAnchor
                overlayController.showSelectionActions(
                    SelectionActionCardPresentation(selectedText: snapshot.text),
                    anchor: anchor
                )
            case .failure(let failure):
                hudFeatureController.showTemporaryMessage(failure.userMessage, duration: 1.8)
            }
        }
    }

    private func startSelectionTargetTracking() {
        recordCurrentExternalSelectionTarget()
        selectionTargetActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let bundleID = application.bundleIdentifier
            let appName = application.localizedName
            let pid = Int(application.processIdentifier)
            MainActor.assumeIsolated {
                self?.recordExternalSelectionTarget(
                    DictationTarget(bundleID: bundleID, appName: appName, pid: pid)
                )
            }
        }
    }

    private func stopSelectionTargetTracking() {
        if let selectionTargetActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(selectionTargetActivationObserver)
            self.selectionTargetActivationObserver = nil
        }
    }

    private func recordCurrentExternalSelectionTarget() {
        guard let application = NSWorkspace.shared.frontmostApplication else { return }
        recordExternalSelectionTarget(application)
    }

    private func recordExternalSelectionTarget(_ application: NSRunningApplication) {
        recordExternalSelectionTarget(DictationTarget(
            bundleID: application.bundleIdentifier,
            appName: application.localizedName,
            pid: Int(application.processIdentifier)
        ))
    }

    private func recordExternalSelectionTarget(_ target: DictationTarget) {
        guard target.bundleID != Bundle.main.bundleIdentifier else { return }
        lastExternalSelectionTarget = target
    }

    private func restoreLastExternalSelectionTargetIfNeeded() async {
        guard runtime?.dictationTargetProvider.currentTarget()?.bundleID == Bundle.main.bundleIdentifier,
              let lastExternalSelectionTarget else {
            return
        }
        _ = await DictationTargetActivation.activate(lastExternalSelectionTarget)
    }

    private func handleSelectionActionSelected(
        action: SelectionActionKind,
        selectedText: String
    ) {
        switch SelectionActionDispatcher().route(action: action, selectedText: selectedText) {
        case let .textTransform(operation, text):
            logger.debug("selection_action_text_transform operation=\(operation) textLen=\(text.count)")
            selectionResultPanelController.present(
                selectedText: text,
                operation: operation
            )
        case let .agentContext(text):
            logger.debug("selection_action_agent_context textLen=\(text.count)")
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    await restoreLastExternalSelectionTargetIfNeeded()
                    try agentDispatchHandler?.start(
                        target: runtime?.dictationTargetProvider.currentTarget(),
                        asrMetadata: nil
                    )
                    let presentation = try await agentDispatchHandler?.finish(rawTranscript: text)
                    if let presentation {
                        selectionHistoryRecorder.record(
                            SelectionHistoryRecordDraft(
                                kind: .selectionAgent,
                                selectedText: text,
                                resultText: text,
                                status: .completed,
                                failureMessage: nil
                            )
                        )
                        hudFeatureController.handleAgentDispatch(presentation)
                    }
                } catch {
                    selectionHistoryRecorder.record(
                        SelectionHistoryRecordDraft(
                            kind: .selectionAgent,
                            selectedText: text,
                            resultText: text,
                            status: .failed,
                            failureMessage: error.localizedDescription
                        )
                    )
                    hudFeatureController.handleAgentDispatch(
                        .failure(message: "任务助手处理失败", retainedText: text)
                    )
                }
            }
        }
    }

    private func shouldStartEphemeralWorkflow(_ shortcut: HotKeyWorkflowShortcut) -> Bool {
        let shouldStart = HotKeyWorkflowRoutingPolicy.shouldStartEphemeralWorkflow(
            shortcut,
            dictationState: dictationOrchestrator.state
        )
        if !shouldStart {
            logger.debug("workflow_shortcut_blocked dictationState=\(dictationOrchestrator.state)")
            hudFeatureController.showTemporaryMessage("语音输入进行中，请先结束当前任务", duration: 2.2)
        }
        return shouldStart
    }

    private func shouldPresentEphemeralWorkflowHUD(_ shortcut: HotKeyWorkflowShortcut) -> Bool {
        HotKeyWorkflowRoutingPolicy.shouldPresentEphemeralWorkflowHUD(
            shortcut,
            dictationState: dictationOrchestrator.state
        )
    }

    private func handlePasteLastResultShortcut() async {
        let outcome = await pasteLastResultService.pasteLastResult()
        switch outcome {
        case .pastedLastResult:
            hudFeatureController.handleWorkflowFeedback(.pasteLastResultSucceeded)
        case .pastedOCRText:
            hudFeatureController.handleWorkflowFeedback(.clipboardImageOCRSucceeded)
        case .noTextAvailable:
            hudFeatureController.handleWorkflowFeedback(.noPasteLastResult)
        case .ocrFailed(let reason):
            hudFeatureController.handleWorkflowFeedback(.clipboardImageOCRFailed(reason))
        case .outputFailed:
            hudFeatureController.handleWorkflowFeedback(.pasteOutputFailed { [weak self] in
                self?.copyLastResultToClipboardForRecovery()
            })
        }
    }

    private func handleClipboardImageOCRShortcut(lease: VoiceWorkflowLease) async {
        defer {
            voiceTaskCoordinator.completeEphemeralWorkflow(lease)
        }

        let outcome = await pasteLastResultService.pasteClipboardImageOCR()
        guard !Task.isCancelled else { return }
        guard voiceTaskCoordinator.isWorkflowLeaseActive(lease) else {
            return
        }
        switch outcome {
        case .pastedOCRText:
            hudFeatureController.handleWorkflowFeedback(.clipboardImageOCRSucceeded)
        case .ocrFailed(let reason):
            hudFeatureController.handleWorkflowFeedback(.clipboardImageOCRFailed(reason))
        case .outputFailed:
            hudFeatureController.handleWorkflowFeedback(.clipboardImageOCROutputFailed { [weak self] in
                self?.copyLastResultToClipboardForRecovery()
            })
        case .pastedLastResult, .noTextAvailable:
            hudFeatureController.handleWorkflowFeedback(.noClipboardImage)
        }
    }

    private func handleScreenshotOCRShortcut(
        lease: VoiceWorkflowLease,
        shouldPresentHUD: Bool
    ) async {
        defer {
            voiceTaskCoordinator.completeEphemeralWorkflow(lease)
        }

        let outcome = await screenshotOCRService.captureAndRecognize()
        guard !Task.isCancelled else { return }
        guard voiceTaskCoordinator.isWorkflowLeaseActive(lease) else {
            return
        }

        switch outcome {
        case .recognized(let result):
            let opensFromTextRecognitionCommand = result.captureCompletionKind == .textRecognition
            if opensFromTextRecognitionCommand {
                screenshotOCRResultPanelController.present(
                    result: result,
                    initialTab: .ocr,
                    autoDismiss: false
                )
            } else {
                screenshotOCRResultPanelController.presentThumbnail(
                    result: result,
                    initialTab: .originalImage
                )
            }
            saveScreenshotRecord(result: result)
        case .translatedOverlay(let originalResult, let overlayImage):
            // 翻译覆盖图：把 overlayImage 放进剪贴板 + 弹结果面板显示覆盖图
            clipboardService.setImage(overlayImage.image)
            var resultWithOverlay = originalResult
            resultWithOverlay.translatedText = originalResult.originalText  // 保留原文供参考
            screenshotOCRResultPanelController.present(
                result: resultWithOverlay,
                initialTab: .translatedOverlay,
                autoDismiss: false,
                overlayImage: overlayImage.image
            )
            if shouldPresentHUD {
                hudFeatureController.showTemporaryMessage("翻译完成", duration: 1.8, tone: .success)
            }
            saveScreenshotRecord(result: originalResult)
        case .captureCancelled:
            if shouldPresentHUD {
                hudFeatureController.showTemporaryMessage("已取消截图", duration: 1.6)
            }
        case .captureFailed(let reason):
            if shouldPresentHUD {
                hudFeatureController.handleWorkflowFeedback(.clipboardImageOCRFailed(reason))
            }
        case .ocrFailed(let reason):
            if shouldPresentHUD {
                hudFeatureController.handleWorkflowFeedback(.clipboardImageOCRFailed(reason))
            }
        case .translated, .summarized, .translationUnavailable, .summaryUnavailable,
             .translationFailed, .summaryFailed:
            break
        }
    }

    private func saveScreenshotRecord(result: ScreenshotOCRResult) {
        guard let image = result.originalImage else { return }
        let recordID = UUID().uuidString
        let directory = appEnvironment.paths?.screenshotsDirectory
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("VoxFlowScreenshots", isDirectory: true)

        let imagePath: String?
        do {
            imagePath = try ScreenshotImageStorage.save(image: image, id: recordID, directory: directory)
        } catch {
            AppLogger.general.error("Failed to save screenshot image: \(error.localizedDescription)")
            imagePath = nil
        }

        let now = appEnvironment.clock.now
        let record = ScreenshotRecord(
            id: recordID,
            ocrText: result.originalText,
            translatedText: nil,
            summaryText: nil,
            imagePath: imagePath,
            charCount: result.originalText.count,
            isFavorited: false,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        do {
            try appEnvironment.screenshotRecordRepository.save(record)
            windowCoordinator.refreshScreenshotRecords()
        } catch {
            AppLogger.general.error("Failed to save screenshot record: \(error.localizedDescription)")
        }
    }

    private func copyLastResultToClipboardForRecovery() {
        guard let text = lastResultStore.lastResultText else {
            hudFeatureController.handleWorkflowFeedback(.noCopyableResult)
            return
        }
        if clipboardService.setString(text) {
            hudFeatureController.handleWorkflowFeedback(.manualCopySucceeded)
        } else {
            hudFeatureController.handleWorkflowFeedback(.manualCopyFailed)
        }
    }

    // MARK: - Audio Feedback

    @MainActor
    private enum FeedbackSound {
        static let start = NSSound(named: "Morse")
        static let complete = NSSound(named: "Glass")
        static let error = NSSound(named: "Basso")
    }

    private func playFeedbackSound(_ event: RecordingAudioFeedbackController.SoundEvent) {
        let sound: NSSound?
        switch event {
        case .start:
            sound = FeedbackSound.start
        case .complete:
            sound = FeedbackSound.complete
        case .error:
            sound = FeedbackSound.error
        }
        sound?.play()
    }

    private func refreshStatusItemAppearance() {
        let usesGrayIcon = isSettingEnabled(
            SettingsSystemOption.grayMenuBarIcon.rawValue,
            defaultValue: false
        )
        if !StatusBarIcon.configure(statusItem, usesGrayIcon: usesGrayIcon) {
            AppLogger.general.error("Status item button unavailable while refreshing menu bar icon.")
        }
    }

    private func isSettingEnabled(_ key: String, defaultValue: Bool) -> Bool {
        guard let repo = runtime?.environment.settingsRepository else { return defaultValue }
        guard let jsonString = try? repo.value(forKey: key),
              let data = jsonString.data(using: .utf8) else {
            return defaultValue
        }
        return (try? JSONDecoder().decode(DecodedSettingValue<Bool>.self, from: data).value) ?? defaultValue
    }

    private func settingString(_ key: String, defaultValue: String) -> String {
        let repo = appEnvironment.settingsRepository
        guard let jsonString = try? repo.value(forKey: key),
              let data = jsonString.data(using: .utf8) else {
            return defaultValue
        }
        return (try? JSONDecoder().decode(DecodedSettingValue<String>.self, from: data).value)
            ?? defaultValue
    }

}

// MARK: - AudioRecorder Delegate

extension AppDelegate: AudioRecorder.Delegate {
    nonisolated func audioRecorder(_ recorder: AudioRecorder, didReceiveBuffer buffer: AVAudioPCMBuffer) {
        dictationAudioBufferForwarder.appendAudioBuffer(buffer)
    }

    nonisolated func audioRecorder(_ recorder: AudioRecorder, didUpdateRMS rms: Float) {
        Task { @MainActor [weak self] in
            self?.hudFeatureController.updateRMS(rms)
        }
    }
}
