import AppKit
import Speech
import AVFoundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    // MARK: - UI

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var languageMenuItems: [NSMenuItem] = []
    private var asrEngineMenuItems: [NSMenuItem] = []
    private var refiningMenuItem: NSMenuItem!
    private var workbenchItem: NSMenuItem!
    private var settingsItem: NSMenuItem!

    // MARK: - Subsystems

    private let keyMonitor = KeyMonitor()
    private let audioRecorder = AudioRecorder()
    private let asrManager = ASRManager()
    private let textInjector = TextInjector()
    private var llmRefiner: RepositoryBackedLLMRefiner!
    private let overlayController = OverlayWindowController()
    private let systemOutputMuter = SystemOutputMuter()
    private var recordingFeedbackController: RecordingAudioFeedbackController!
    private var permissionGuideController: PermissionGuideWindowController?
    private var appEnvironment: AppEnvironment!
    private var windowCoordinator: WindowCoordinator!
    private var dictationOrchestrator: DictationOrchestrator!
    private var agentComposeHandler: DefaultAgentComposeHandler!

    // MARK: - State

    private var permissionsResolved = false
    private var hasRecordingPermissions = false
    private var escEventMonitor: Any?
    private var localEscEventMonitor: Any?
    private var activeVoiceAction: VoiceAction?

    /// Scheduled task that starts recording after longPressThreshold.
    /// Cancelled by onShortPress so the toggle logic takes over instead.
    private var delayedPressTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(AppPresentationPolicy.activationPolicy)
        LegacyConfigurationMigrator.migrateBundleDefaults()
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
        setupMainMenu()
        setupMenu()

        audioRecorder.delegate = self

        // Start key monitor
        setupKeyMonitor()

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
        keyMonitor.stop()
        delayedPressTask?.cancel()
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
        let outputService = DefaultOutputService(
            textInjector: textInjector,
            clipboardService: SystemClipboardService()
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
            self?.overlayController.updateAgentComposeStatus(stage)
            self?.overlayController.show()
        }
        dictationOrchestrator = DictationOrchestrator(
            asrEngineFactory: asrManager,
            audioRecorder: audioRecorder,
            textPipeline: textPipeline,
            textInjector: textInjector,
            historyRepository: appEnvironment.historyRepository,
            clock: appEnvironment.clock,
            targetProvider: targetProvider,
            agentComposeHandler: agentComposeHandler
        )
        dictationOrchestrator.onStateChange = { [weak self] state in
            self?.handleDictationStateChange(state)
        }
        dictationOrchestrator.onTranscriptionUpdate = { [weak self] text, isRefining in
            self?.overlayController.updateTranscription(text, isRefining: isRefining)
        }
        dictationOrchestrator.onProcessingStarted = { [weak self] text in
            self?.overlayController.updateTranscription(text, isRefining: true)
        }
        dictationOrchestrator.onHistorySaved = { [weak self] in
            self?.appEnvironment.historyDidChange.send()
        }
        dictationOrchestrator.onAgentComposeCompleted = { [weak self] result in
            self?.appEnvironment.historyDidChange.send()
            self?.showAgentComposeResult(result)
        }
        dictationOrchestrator.onError = { [weak self] error in
            self?.showRecognitionError(error)
        }
    }

    private func handleDictationStateChange(_ state: DictationState) {
        recordingFeedbackController?.handle(state)
        switch state {
        case .idle:
            activeVoiceAction = nil
            stopEscMonitor()
            overlayController.dismiss()
            refiningMenuItem?.isHidden = true
        case .recording:
            startEscMonitor()
            overlayController.show()
            overlayController.updateTranscription("", isRefining: false)
            refiningMenuItem?.isHidden = true
        case .waitingForFinal:
            if asrManager.effectiveSelectedEngineType == .qwen3 {
                overlayController.updateTranscription("正在识别...", isRefining: true)
            }
        case .processing:
            refiningMenuItem?.isHidden = false
        case .injecting:
            stopEscMonitor()
            overlayController.dismiss()
            refiningMenuItem?.isHidden = true
        case .failed:
            stopEscMonitor()
            overlayController.dismiss()
            refiningMenuItem?.isHidden = true
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: StatusBarIcon.preferredLength)
        StatusBarIcon.restoreVisibility(of: statusItem)
        if let button = statusItem.button {
            statusItem.length = StatusBarIcon.preferredLength
            button.identifier = StatusBarIcon.buttonIdentifier
            button.image = StatusBarIcon.makeImage()
            button.title = StatusBarIcon.visibleTitle
            button.imagePosition = StatusBarIcon.imagePosition
            button.toolTip = StatusBarIcon.tooltip
            button.setAccessibilityLabel(StatusBarIcon.accessibilityName)
            refreshStatusItemAppearance()
        }
    }

    // MARK: - Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let applicationMenuItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(
            withTitle: "关于随声写",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: "隐藏随声写",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        applicationMenu.addItem(
            withTitle: "隐藏其他",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        ).keyEquivalentModifierMask = [.command, .option]
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: "退出随声写",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        applicationMenuItem.submenu = applicationMenu
        mainMenu.addItem(applicationMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    private func setupMenu() {
        menu.autoenablesItems = false
        menu.delegate = self

        // Language submenu
        let languageMenu = NSMenu()
        languageMenu.autoenablesItems = false
        for lang in RecognitionLanguage.allCases {
            let item = NSMenuItem(
                title: lang.displayName,
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            item.representedObject = lang
            item.target = self
            item.state = (lang == LanguageManager.shared.currentLanguage) ? .on : .off
            languageMenu.addItem(item)
            languageMenuItems.append(item)
        }

        let languageParentItem = NSMenuItem()
        languageParentItem.title = "语言 / Language"
        languageParentItem.submenu = languageMenu
        menu.addItem(languageParentItem)

        menu.addItem(.separator())

        // ASR Engine submenu
        setupASREngineMenu()

        menu.addItem(.separator())

        // Workbench
        workbenchItem = NSMenuItem(
            title: "打开工作台",
            action: #selector(openWorkbench(_:)),
            keyEquivalent: ""
        )
        workbenchItem.target = self
        menu.addItem(workbenchItem)

        // Settings
        settingsItem = NSMenuItem(
            title: "设置",
            action: #selector(openSettings(_:)),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let githubItem = NSMenuItem(
            title: "GitHub",
            action: #selector(openGitHub(_:)),
            keyEquivalent: ""
        )
        githubItem.target = self
        menu.addItem(githubItem)

        menu.addItem(.separator())

        // Refining status (shown during active LLM refinement)
        refiningMenuItem = NSMenuItem(
            title: "正在 LLM 纠错",
            action: nil,
            keyEquivalent: ""
        )
        refiningMenuItem.isHidden = true
        menu.addItem(refiningMenuItem)

        menu.addItem(.separator())

        // Quit
        let checkPermissionsItem = NSMenuItem(
            title: "检查权限",
            action: #selector(checkPermissions(_:)),
            keyEquivalent: ""
        )
        checkPermissionsItem.target = self
        menu.addItem(checkPermissionsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出随声写",
            action: #selector(quitApp(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateASREngineMenuState()
        refreshStatusItemAppearance()
    }

    private func updateLanguageMenuState() {
        let current = LanguageManager.shared.currentLanguage
        for item in languageMenuItems {
            item.state = (item.representedObject as? RecognitionLanguage) == current ? .on : .off
        }
    }

    // MARK: - Menu Actions

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let lang = sender.representedObject as? RecognitionLanguage else { return }
        LanguageManager.shared.setLanguage(lang)
        updateLanguageMenuState()
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        windowCoordinator.showSettings(tab: .asr)
    }

    @objc private func openWorkbench(_ sender: NSMenuItem) {
        windowCoordinator.showMainWindow()
    }

    @objc private func openGitHub(_ sender: NSMenuItem) {
        guard let url = URL(string: HelpExternalLinks.githubRepository) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - ASR Engine Menu

    private func setupASREngineMenu() {
        let asrMenu = NSMenu()
        asrMenu.autoenablesItems = false

        for engineType in ASREngineType.allCases {
            let item = NSMenuItem(
                title: engineType.displayName,
                action: #selector(selectASREngine(_:)),
                keyEquivalent: ""
            )
            item.representedObject = engineType
            item.target = self
            item.isEnabled = asrManager.canSelectEngine(engineType)
            item.state = (engineType == asrManager.effectiveSelectedEngineType) ? .on : .off
            asrMenu.addItem(item)
            asrEngineMenuItems.append(item)
        }

        let asrParentItem = NSMenuItem()
        asrParentItem.title = "语音识别引擎"
        asrParentItem.submenu = asrMenu
        menu.addItem(asrParentItem)
    }

    @objc private func selectASREngine(_ sender: NSMenuItem) {
        guard let engineType = sender.representedObject as? ASREngineType else { return }
        asrManager.selectEngine(engineType)
        updateASREngineMenuState()
    }

    private func updateASREngineMenuState() {
        let effective = asrManager.effectiveSelectedEngineType
        for item in asrEngineMenuItems {
            guard let engineType = item.representedObject as? ASREngineType else { continue }
            item.isEnabled = asrManager.canSelectEngine(engineType)
            item.state = engineType == effective ? .on : .off
        }
    }

    // MARK: - Quit

    @objc private func quitApp(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Key Monitor

    private func setupKeyMonitor() {
        keyMonitor.onHotKeyPress = { [weak self] action in
            guard let self, self.dictationOrchestrator.state.isIdle else { return }

            // Delay recording start by longPressThreshold. If the user
            // releases before the threshold (short press), onShortPress
            // cancels this task and toggles recording instead.
            let threshold = ShortcutManager.shared.longPressThreshold
            let task = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(threshold * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.delayedPressTask = nil
                self.handleHotKeyPress(action: action)
            }
            delayedPressTask = task
        }
        keyMonitor.onHotKeyRelease = { [weak self] action in
            self?.delayedPressTask?.cancel()
            self?.delayedPressTask = nil

            // Route release to notes recording if active.
            let notesCoordinator = NotesCaptureCoordinator.shared
            if action == .dictation && notesCoordinator.isActive && notesCoordinator.isRecording {
                notesCoordinator.finishRecording?()
                return
            }

            self?.handleHotKeyRelease(action: action)
        }
        keyMonitor.onShortPress = { [weak self] action in
            guard let self else { return }

            // Cancel any pending long-press start — this is a short press.
            self.delayedPressTask?.cancel()
            self.delayedPressTask = nil

            // Route to notes recording if the notes view is active.
            let notesCoordinator = NotesCaptureCoordinator.shared
            if action == .dictation && notesCoordinator.shouldCaptureHotKey() {
                if notesCoordinator.isRecording {
                    notesCoordinator.finishRecording?()
                } else {
                    Task { @MainActor in
                        await notesCoordinator.startRecording?()
                    }
                }
                return
            }

            // Toggle recording on short press.
            switch self.dictationOrchestrator.state {
            case .recording, .waitingForFinal:
                self.handleHotKeyRelease(action: action)
            case .idle:
                self.handleHotKeyPress(action: action)
            case .processing, .injecting, .failed:
                break
            }
        }

        guard keyMonitor.start() else {
            // Accessibility permission not granted
            DispatchQueue.main.async {
                self.showAccessibilityAlert()
            }
            return
        }
    }

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
            settingsURL: URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        )
    }

    private static func keyDisplayName(for keyCode: Int64) -> String {
        KeyCodeMapping.displayName(for: keyCode)
    }

    // MARK: - Hot Key Handling

    private func handleHotKeyPress(action: VoiceAction = .dictation) {
        // Route to notes recording if the notes view is active.
        let notesCoordinator = NotesCaptureCoordinator.shared
        if action == .dictation && notesCoordinator.shouldCaptureHotKey() {
            Task { @MainActor in
                await notesCoordinator.startRecording?()
            }
            return
        }

        guard dictationOrchestrator.state.isIdle else { return }
        if action == .agentCompose && !llmRefiner.isConfigured {
            overlayController.showTemporaryMessage("请先在设置中配置 LLM", duration: 3.0)
            return
        }
        refreshRecordingPermissionState()
        guard permissionsResolved, hasRecordingPermissions else {
            if permissionsResolved {
                showRecordingPermissionsAlert()
            }
            return
        }

        do {
            audioRecorder.voiceEnhancementEnabled = isSettingEnabled(
                SettingsKey.audioVoiceEnhancementEnabled,
                defaultValue: true
            )
            try dictationOrchestrator.start(
                configuration: currentDictationConfiguration(),
                mode: action == .agentCompose ? .agentCompose : .dictation
            )
            activeVoiceAction = action
        } catch {
            if error is AudioRecorder.AudioRecorderError {
                showRecordingPermissionsAlert()
            } else {
                showRecognitionError(error)
            }
        }
    }

    private func handleHotKeyRelease(action: VoiceAction = .dictation) {
        // Route release to notes recording if notes is currently recording.
        let notesCoordinator = NotesCaptureCoordinator.shared
        if action == .dictation && notesCoordinator.isActive && notesCoordinator.isRecording {
            notesCoordinator.finishRecording?()
            return
        }

        guard activeVoiceAction == action else {
            return
        }
        dictationOrchestrator.release()
    }

    private func currentDictationConfiguration() -> DictationConfiguration {
        let engineType = asrManager.effectiveSelectedEngineType
        let language = LanguageManager.shared.currentLanguage
        return DictationConfiguration(
            engineType: engineType,
            locale: language.locale,
            languageIdentifier: language.rawValue
        )
    }

    // MARK: - Error Handling

    private func resolveRecordingPermissions() async {
        // Qwen3-ASR only needs microphone, not system speech recognition.
        let engineType = asrManager.effectiveSelectedEngineType

        if engineType == .qwen3 {
            let micStatus = AudioRecorder.checkPermission()
            if micStatus == .notDetermined {
                _ = await AudioRecorder.requestPermission()
            }
            let microphoneGranted = AudioRecorder.checkPermission() == .granted
            permissionsResolved = true
            hasRecordingPermissions = RecordingPermissionPolicy.hasRequiredPermissions(
                engineType: .qwen3,
                microphonePermission: microphoneGranted ? .granted : .denied,
                speechPermission: .denied
            )
            return
        }

        let micStatus = AudioRecorder.checkPermission()
        let speechStatus = SpeechRecognizer.checkPermission()

        var microphoneGranted = (micStatus == .granted)
        var speechAuthorized = (speechStatus == .granted)

        // Only request if not yet determined — don't re-prompt for already denied
        if micStatus == .notDetermined {
            microphoneGranted = await AudioRecorder.requestPermission()
        }
        if speechStatus == .notDetermined {
            let status = await SpeechRecognizer.requestPermission()
            speechAuthorized = (status == .authorized)
        }

        permissionsResolved = true
        hasRecordingPermissions = RecordingPermissionPolicy.hasRequiredPermissions(
            engineType: .apple,
            microphonePermission: microphoneGranted ? .granted : .denied,
            speechPermission: speechAuthorized ? .granted : .denied
        )
    }

    private func refreshRecordingPermissionState() {
        let engineType = asrManager.effectiveSelectedEngineType

        permissionsResolved = true
        hasRecordingPermissions = RecordingPermissionPolicy.hasRequiredPermissions(
            engineType: engineType,
            microphonePermission: AudioRecorder.checkPermission(),
            speechPermission: SpeechRecognizer.checkPermission()
        )
    }

    private func checkAllPermissions() {
        let mic = AudioRecorder.checkPermission()
        let speech = SpeechRecognizer.checkPermission()
        let accessibility = AXIsProcessTrusted()
        let screenRecording = CGPreflightScreenCaptureAccess()
        let engineType = asrManager.effectiveSelectedEngineType
        let speechStatus = PermissionSummary.speechRecognitionStatus(
            engineType: engineType,
            speechPermission: speech
        )

        presentPermissionGuide(
            title: "权限检查",
            subtitle: "确认随声写录音、转写和文本输入所需权限。",
            items: [
                    PermissionStatusItem(
                        title: "辅助功能",
                        subtitle: "监听快捷键并向当前应用输入转写文本",
                        systemImage: "accessibility",
                        status: PermissionSummary.statusText(accessibility),
                        granted: accessibility
                    ),
                    PermissionStatusItem(
                        title: "麦克风",
                        subtitle: "录制你的声音用于听写",
                        systemImage: "mic",
                        status: PermissionSummary.statusText(mic == .granted),
                        granted: mic == .granted
                    ),
                    PermissionStatusItem(
                        title: "语音识别",
                        subtitle: "Apple 语音识别的真实系统授权状态",
                        systemImage: "waveform",
                        status: speechStatus,
                        granted: speech == .granted
                    ),
                    PermissionStatusItem(
                        title: "屏幕录制",
                        subtitle: "用于“帮我说”的当前窗口 OCR，不保存截图",
                        systemImage: "rectangle.inset.filled.and.person.filled",
                        status: PermissionSummary.statusText(screenRecording),
                        granted: screenRecording
                    ),
                ],
            settingsURL: URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy"
            )
        )
    }

    @objc private func checkPermissions(_ sender: NSMenuItem) {
        checkAllPermissions()
    }

    private func showRecordingPermissionsAlert() {
        let message = PermissionSummary.recordingPermissionAlertText(
            engineType: asrManager.effectiveSelectedEngineType
        )
        presentPermissionGuide(
            title: message.title,
            subtitle: message.body,
            items: recordingPermissionItems(),
            settingsURL: URL(
                string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity"
            )
        )
    }

    private func recordingPermissionItems() -> [PermissionStatusItem] {
        let microphoneGranted = AudioRecorder.checkPermission() == .granted
        let speechGranted = SpeechRecognizer.checkPermission() == .granted
        return [
            PermissionStatusItem(
                title: "麦克风",
                subtitle: "录制你的声音用于听写",
                systemImage: "mic",
                status: PermissionSummary.statusText(microphoneGranted),
                granted: microphoneGranted
            ),
            PermissionStatusItem(
                title: "语音识别",
                subtitle: "Apple 语音识别的真实系统授权状态",
                systemImage: "waveform",
                status: PermissionSummary.statusText(speechGranted),
                granted: speechGranted
            ),
        ]
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
        // Use non-blocking overlay feedback instead of a modal alert.
        // The dictation orchestrator already preserves any partial text
        // before calling this handler, so the user won't lose work.
        let message = error.localizedDescription
        overlayController.showTemporaryMessage("识别失败: \(message)", duration: 3.0)
    }

    private func showAgentComposeResult(_ result: OutputResult) {
        switch result {
        case .copied:
            overlayController.showTemporaryMessage("已生成并复制到剪贴板", duration: 2.5)
        case .targetChanged:
            overlayController.showTemporaryMessage("目标窗口已变化，内容已复制", duration: 3.0)
        case .injectionFailed, .copyFailed:
            overlayController.showTemporaryMessage("生成完成，但复制失败", duration: 3.0)
        case .injected:
            overlayController.showTemporaryMessage("已生成回复", duration: 2.5)
        case .cancelled:
            break
        }
    }

    /// Cancel the current recording without injecting any text.
    private func cancelRecording() {
        dictationOrchestrator.cancel()
    }

    private func startEscMonitor() {
        stopEscMonitor()
        localEscEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard EscapeEventRouting.isEscapeKey(event.keyCode) else {
                return event
            }
            self?.cancelRecording()
            return nil
        }
        escEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if EscapeEventRouting.isEscapeKey(event.keyCode) {
                DispatchQueue.main.async {
                    self?.cancelRecording()
                }
            }
        }
    }

    private func stopEscMonitor() {
        if let monitor = escEventMonitor {
            NSEvent.removeMonitor(monitor)
            escEventMonitor = nil
        }
        if let monitor = localEscEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEscEventMonitor = nil
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
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.contentTintColor = usesGrayIcon ? .secondaryLabelColor : nil
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

enum EscapeEventRouting {
    static func isEscapeKey(_ keyCode: UInt16) -> Bool {
        keyCode == 53
    }
}

// MARK: - AudioRecorder Delegate

extension AppDelegate: AudioRecorder.Delegate {
    func audioRecorder(_ recorder: AudioRecorder, didReceiveBuffer buffer: AVAudioPCMBuffer) {
        dictationOrchestrator.appendAudioBuffer(buffer)
    }

    func audioRecorder(_ recorder: AudioRecorder, didUpdateRMS rms: Float) {
        overlayController.updateRMS(rms)
    }
}
