import AppKit
import AVFoundation
import SwiftUI
import VoxFlowTextInsertion

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
            self?.hudFeatureController.showTemporaryMessage("请先在设置中配置 LLM", duration: 3.0)
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
        NSApp.setActivationPolicy(AppPresentationPolicy.activationPolicy)
        runtime = AppRuntime.bootstrap()
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

        Task {
            await resolveRecordingPermissions()
        }

        if AppPresentationPolicy.opensWorkbenchOnLaunch {
            windowCoordinator.showMainWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard AppPresentationPolicy.restoresWorkbenchOnReopen else {
            return true
        }
        windowCoordinator.showMainWindow()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyFeatureController.stop()
        audioRecorder.stop()
        dictationOrchestrator.cancel()
        agentDispatchHandler?.cancel()
        agentHelperManager?.stopRouter()
    }

    private func setupDictationOrchestrator() {
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
        if let helperManager = agentHelperManager,
           let agentRouterClient = runtime!.agentRouterClient {
            Task { @MainActor in
                do {
                    try await helperManager.startRouter()
                } catch {
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
            audioCaptureCoordinator: runtime!.audioCaptureCoordinator
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
    }

    private func handleDictationStateChange(_ state: DictationState) {
        dictationFeatureController.handleStateChange(state)
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: StatusBarIcon.preferredLength)
        if !StatusBarIcon.configure(statusItem) {
            AppLogger.general.error("Status item button unavailable during menu bar setup.")
        }
    }

    // MARK: - Menu

    private func setupMainMenu() {
        NSApplication.shared.mainMenu = AppMainMenuBuilder.makeMainMenu()
    }

    private func setupMenu() {
        menuBarCoordinator.attach(to: statusItem)
    }

    // MARK: - Menu Actions

    private func selectLanguage(_ language: RecognitionLanguage) {
        LanguageManager.shared.setLanguage(language)
    }

    private func openSettings() {
        windowCoordinator.showSettings(tab: .asr)
    }

    private func selectLLMProvider(_ providerID: String) {
        do {
            let viewModel = LLMProviderViewModel(environment: appEnvironment)
            try viewModel.setDefaultProvider(id: providerID)
        } catch {
            AppLogger.general.error("Failed to select LLM provider from menu: \(error.localizedDescription)")
        }
    }

    private func selectCapabilityModel(kind: CapabilityModelKind, modelID: String) {
        CapabilityModelViewModel.setSelectedModelID(modelID, kind: kind)
    }

    private func openWorkbench() {
        windowCoordinator.showMainWindow()
    }

    private func openGitHub() {
        guard let url = URL(string: HelpExternalLinks.githubRepository) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - ASR Engine Menu

    static func makeASRMenuOptions() -> [ASRMenuModel] {
        ASRMenuOptions.makeOptions()
    }

    private func selectASREngine(_ option: ASRMenuModel) {
        asrCoordinator.selectMenuOption(option)
    }

    // MARK: - Quit

    private func quitApp() {
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
        Task { @MainActor in
            await NotesCaptureCoordinator.shared.startRecording?()
        }
    }

    private func finishNotesRecording() {
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
        _ = await recordingPermissionService.resolveRecordingPermissions()
    }

    private func checkAllPermissions() {
        let recordingPermissions = recordingPermissionService.refreshRecordingPermissions()
        let accessibility = AXIsProcessTrusted()
        let screenRecording = CGPreflightScreenCaptureAccess()

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
        checkAllPermissions()
    }

    private func showRecordingPermissionsAlert() {
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

    private func handleEscapeKey() {
        if dictationOrchestrator.state == .processing {
            dictationOrchestrator.finishWithoutTextCorrection()
        } else {
            dictationOrchestrator.cancel()
            agentDispatchHandler?.cancel()
            hudFeatureController.render(.hidden)
        }
    }

    private func performWorkflowShortcut(_ shortcut: HotKeyWorkflowShortcut) -> Bool {
        switch shortcut {
        case .clipboardImageOCR:
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
        case .cancel:
            if voiceTaskCoordinator.activeTaskID(for: .clipboardImageOCR) != nil {
                voiceTaskCoordinator.cancelEphemeralWorkflow(kind: .clipboardImageOCR)
                return true
            }
            if voiceTaskCoordinator.activeTaskID(for: .screenshotOCR) != nil {
                voiceTaskCoordinator.cancelEphemeralWorkflow(kind: .screenshotOCR)
                return true
            }
            if voiceTaskCoordinator.activeTaskID(for: .agentDispatch) != nil {
                handleEscapeKey()
                return true
            }
            guard !dictationOrchestrator.state.isIdle else {
                return false
            }
            handleEscapeKey()
            return true
        }
    }

    private func shouldStartEphemeralWorkflow(_ shortcut: HotKeyWorkflowShortcut) -> Bool {
        let shouldStart = HotKeyWorkflowRoutingPolicy.shouldStartEphemeralWorkflow(
            shortcut,
            dictationState: dictationOrchestrator.state
        )
        if !shouldStart {
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

        if shouldPresentHUD {
            hudFeatureController.showTemporaryMessage("框选截图区域以识别文字", duration: 1.8)
        }
        let outcome = await screenshotOCRService.captureAndRecognize()
        guard !Task.isCancelled else { return }
        guard voiceTaskCoordinator.isWorkflowLeaseActive(lease) else {
            return
        }

        switch outcome {
        case .recognized(let result):
            screenshotOCRResultPanelController.present(result: result)
            if shouldPresentHUD {
                hudFeatureController.showTemporaryMessage("屏幕文字识别完成", duration: 1.8, tone: .success)
            }
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
