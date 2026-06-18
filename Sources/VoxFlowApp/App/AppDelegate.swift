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
    private let asrCoordinator = ASRCoordinator()
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
            openWorkbench: { [weak self] in self?.openWorkbench() },
            openSettings: { [weak self] in self?.openSettings() },
            openGitHub: { [weak self] in self?.openGitHub() },
            checkPermissions: { [weak self] in self?.checkPermissions() },
            quit: { [weak self] in self?.quitApp() },
            menuWillOpen: { [weak self] in self?.refreshStatusItemAppearance() }
        )
    )
    private lazy var recordingPermissionService = RecordingPermissionService(
        engineTypeProvider: { [asrCoordinator] in asrCoordinator.effectiveSelectedEngineType }
    )
    private let fastPasteTextInserter = FastPasteTextInserter()
    private let simulatedTypingInserter = SimulatedTypingInserter()
    private lazy var textInsertionCoordinator = TextInsertionCoordinator(
        fastPasteInserter: fastPasteTextInserter,
        simulatedTypingInserter: simulatedTypingInserter
    )
    private let lastResultStore = InMemoryLastResultStore()
    private lazy var outputService = DefaultOutputService(
        textInsertionCoordinator: textInsertionCoordinator,
        clipboardService: SystemClipboardService(),
        lastResultStore: lastResultStore
    )
    private let pasteLastResultHotKeyMonitor = PasteLastResultHotKeyMonitor()
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
    private var llmRefiner: RepositoryBackedLLMRefiner!
    private let overlayController = OverlayWindowController()
    private lazy var hudFeatureController = VoiceHUDFeatureController(overlay: overlayController)
    private let systemOutputMuter = SystemOutputMuter()
    private let escapeKeyMonitorController = EscapeKeyMonitorController()
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
        startCancelMonitor: { [weak self] in
            self?.startEscMonitor()
        },
        stopCancelMonitor: { [weak self] in
            self?.stopEscMonitor()
        },
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
            try self?.dictationOrchestrator.start(
                configuration: configuration,
                mode: mode
            )
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
    private var appEnvironment: AppEnvironment!
    private var windowCoordinator: WindowCoordinator!
    private var dictationOrchestrator: DictationOrchestrator!
    private var agentComposeHandler: DefaultAgentComposeHandler!

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
        do {
            appEnvironment = AppEnvironment(container: try DependencyContainer.live())
        } catch {
            AppLogger.general.error("Failed to initialize app environment: \(error.localizedDescription)")
            try? FileManager.default.createDirectory(
                at: FileManager.default.temporaryDirectory,
                withIntermediateDirectories: true
            )
            appEnvironment = AppEnvironment(container: try! DependencyContainer.inMemory())
        }
        windowCoordinator = WindowCoordinator(environment: appEnvironment)
        llmRefiner = RepositoryBackedLLMRefiner(
            providerRepository: appEnvironment.llmProviderRepository,
            credentialStore: appEnvironment.credentialStore
        )
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
        startPasteLastResultHotKeyMonitor()

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
        pasteLastResultHotKeyMonitor.stop()
        audioRecorder.stop()
        dictationOrchestrator.cancel()
        stopEscMonitor()
    }

    private func setupDictationOrchestrator() {
        let styleSelector = SettingsBackedStyleSelector(
            styleRepository: appEnvironment.styleRepository,
            settingsRepository: appEnvironment.settingsRepository,
            classifier: LLMApplicationStyleClassifier(refiner: llmRefiner)
        )
        let targetProvider = WorkspaceDictationTargetProvider()
        let textPipeline = DefaultTextProcessingPipeline(
            refiner: llmRefiner,
            replacementRuleRepository: appEnvironment.replacementRuleRepository,
            glossaryRepository: appEnvironment.glossaryRepository,
            styleSelector: styleSelector
        )
        let taskCoordinator = VoiceTaskCoordinator(
            taskRepository: VoiceTaskRepository(
                databaseQueue: appEnvironment.container.databaseQueue,
                clock: appEnvironment.clock
            ),
            outputService: outputService,
            textPipeline: textPipeline,
            targetProvider: targetProvider,
            clock: appEnvironment.clock,
            contextPipeline: ContextPipeline(),
            agentRefiner: llmRefiner
        )
        agentComposeHandler = DefaultAgentComposeHandler(
            coordinator: taskCoordinator,
            styleSelector: styleSelector
        )
        agentComposeHandler.onStageChange = { [weak self] stage in
            self?.hudFeatureController.handleAgentComposeStage(stage)
        }
        agentComposeHandler.onStreamingDelta = { [weak self] partialText in
            self?.hudFeatureController.updateStreamingText(partialText)
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
            agentComposeHandler: agentComposeHandler
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
            subtitle: "随声写需要辅助功能权限来监听 \(shortcutName) 并向当前应用输入转写文本。",
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
        asrCoordinator.dictationConfiguration(for: LanguageManager.shared.currentLanguage)
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
            subtitle: "确认随声写录音、转写和文本输入所需权限。",
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
        let message = error.localizedDescription
        if let taskID = agentComposeHandler?.lastFailedTaskID {
            hudFeatureController.showTemporaryMessage(
                "处理失败：\(message)",
                duration: 8.0
            ) { [weak self] in
                self?.openHistoryDetail(taskID)
            }
            return
        }
        // For dictation errors, try to open the last voice task detail; otherwise open home page.
        hudFeatureController.showTemporaryMessage(
            "\(message)",
            duration: 8.0
        ) { [weak self] in
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
            hudFeatureController.showTemporaryMessage("已生成并复制到剪贴板", duration: 2.5)
        case .targetChanged:
            hudFeatureController.showTemporaryMessage("目标窗口已变化，内容已复制", duration: 3.0)
        case .permissionDenied:
            hudFeatureController.showTemporaryMessage("没有辅助功能权限，内容已复制", duration: 3.0)
        case .injectionFailed:
            hudFeatureController.showTemporaryMessage("写入失败，内容已复制", duration: 3.0)
        case .copyFailed:
            hudFeatureController.showTemporaryMessage("生成完成，但复制失败", duration: 3.0)
        case .injected:
            hudFeatureController.showTemporaryMessage("已生成并写入当前输入框", duration: 2.5)
        case .cancelled:
            break
        }
    }

    private func handleEscapeKey() {
        if dictationOrchestrator.state == .processing {
            dictationOrchestrator.finishWithoutTextCorrection()
        } else {
            dictationOrchestrator.cancel()
        }
    }

    private func startEscMonitor() {
        escapeKeyMonitorController.start { [weak self] in
            self?.handleEscapeKey()
        }
    }

    private func stopEscMonitor() {
        escapeKeyMonitorController.stop()
    }

    private func startPasteLastResultHotKeyMonitor() {
        pasteLastResultHotKeyMonitor.onPasteLastResult = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handlePasteLastResultShortcut()
            }
        }
        _ = pasteLastResultHotKeyMonitor.start()
    }

    private func handlePasteLastResultShortcut() async {
        let outcome = await pasteLastResultService.paste()
        switch outcome {
        case .pastedLastResult:
            hudFeatureController.showTemporaryMessage("已粘贴上次结果", duration: 1.8)
        case .pastedOCRText:
            hudFeatureController.showTemporaryMessage("已识别图片文字并粘贴", duration: 2.2)
        case .noTextAvailable:
            hudFeatureController.showTemporaryMessage("没有可粘贴的上次结果", duration: 2.2)
        case .ocrFailed(let reason):
            hudFeatureController.showTemporaryMessage("图片 OCR 失败：\(reason)", duration: 3.0)
        case .outputFailed:
            hudFeatureController.showTemporaryMessage("粘贴失败，结果已保留", duration: 3.0)
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
        guard let repo = appEnvironment?.settingsRepository else { return defaultValue }
        guard let jsonString = try? repo.value(forKey: key),
              let data = jsonString.data(using: .utf8) else {
            return defaultValue
        }
        return (try? JSONDecoder().decode(DecodedSettingValue<Bool>.self, from: data).value) ?? defaultValue
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
