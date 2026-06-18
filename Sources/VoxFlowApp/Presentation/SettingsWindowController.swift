import AppKit
import VoxFlowProviderQwen3

/// Tab identifiers for the Settings window.
enum SettingsTab: Int {
    case asr = 0
    case llm
    case shortcut
}

/// Custom window that can become key even in an LSUIElement app.
private final class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Settings window with three-panel tab view: ASR, LLM, Shortcut.
@MainActor
final class SettingsWindowController: NSWindowController {
    // MARK: - Singleton

    static let shared = SettingsWindowController()

    // MARK: - Tab View

    private let tabView = NSTabView()

    // MARK: - ASR Tab

    private let appleRadio = NSButton(radioButtonWithTitle: "系统自带", target: nil, action: nil)
    private let qwen3Radio = NSButton(radioButtonWithTitle: "Qwen3-ASR", target: nil, action: nil)
    private let modelPathField = NSTextField()
    private let downloadButton = NSButton()
    private let browseButton = NSButton()
    private let size06Radio = NSButton(radioButtonWithTitle: "0.6B", target: nil, action: nil)
    private let modelDownloadProgress = NSProgressIndicator()
    private let asrStatusLabel = NSTextField(labelWithString: "")

    // MARK: - LLM Tab

    private let baseURLField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let modelField = NSTextField()
    private let llmStatusLabel = NSTextField(labelWithString: "")
    private let testButton = NSButton()
    private let saveButton = NSButton()
    private var testSpinner: NSProgressIndicator!

    // MARK: - Shortcut Tab

    private let shortcutDisplayField = NSTextField()
    private let recordShortcutButton = NSButton()
    private let thresholdSlider = NSSlider()
    private let thresholdValueLabel = NSTextField(labelWithString: "")
    private let shortPressPopup = NSPopUpButton()
    private let resetShortcutButton = NSButton()
    private var shortcutRecordingSheet: NSWindow?
    private var shortcutEventMonitors: [Any] = []

    // MARK: - Shared Instances

    private lazy var asrManager = ASRManager()
    private let modelDownloader: any Qwen3ModelDownloading
    private var modelDownloadTask: Task<Void, Never>?

    // MARK: - Init

    private init(modelDownloader: any Qwen3ModelDownloading = Qwen3ModelDownloader.live()) {
        self.modelDownloader = modelDownloader
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        setupWindow()
        setupTabView()
        setupASRTab()
        setupLLMTab()
        setupShortcutTab()
        loadAllSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup Window

    private func setupWindow() {
        guard let window = window else { return }
        window.title = "\(ProductBrand.chineseDisplayName)设置"
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.center()
    }

    // MARK: - Tab View

    private func setupTabView() {
        guard let window = window,
              let contentView = window.contentView else { return }

        tabView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tabView)

        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])

        // Will be added after sub-views are built
    }

    // MARK: - ASR Tab

    private func setupASRTab() {
        let item = NSTabViewItem(identifier: "asr")
        item.label = "ASR"
        let view = NSView()

        // --- Engine Selection ---
        let engineLabel = makeTitleLabel("语音识别引擎")

        appleRadio.translatesAutoresizingMaskIntoConstraints = false
        appleRadio.target = self
        appleRadio.action = #selector(asrEngineChanged(_:))

        qwen3Radio.translatesAutoresizingMaskIntoConstraints = false
        qwen3Radio.target = self
        qwen3Radio.action = #selector(asrEngineChanged(_:))

        // --- Qwen3 Model Path ---
        let pathLabel = makeLabel("模型路径：")
        modelPathField.translatesAutoresizingMaskIntoConstraints = false
        modelPathField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        modelPathField.controlSize = .small
        modelPathField.placeholderString = "未选择模型文件..."
        modelPathField.isEditable = false

        downloadButton.title = "下载模型..."
        downloadButton.bezelStyle = .rounded
        downloadButton.translatesAutoresizingMaskIntoConstraints = false
        downloadButton.target = self
        downloadButton.action = #selector(downloadQwen3Model(_:))

        browseButton.title = "浏览..."
        browseButton.bezelStyle = .rounded
        browseButton.translatesAutoresizingMaskIntoConstraints = false
        browseButton.target = self
        browseButton.action = #selector(browseModelPath(_:))

        // --- Qwen3 Model Size ---
        let sizeLabel = makeTitleLabel("模型大小")

        size06Radio.translatesAutoresizingMaskIntoConstraints = false
        size06Radio.target = self
        size06Radio.action = #selector(qwen3SizeChanged(_:))


        modelDownloadProgress.translatesAutoresizingMaskIntoConstraints = false
        modelDownloadProgress.isIndeterminate = false
        modelDownloadProgress.minValue = 0
        modelDownloadProgress.maxValue = 1
        modelDownloadProgress.doubleValue = 0
        modelDownloadProgress.isHidden = true

        // --- Status ---
        asrStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        asrStatusLabel.font = NSFont.systemFont(ofSize: 11)
        asrStatusLabel.textColor = .secondaryLabelColor
        asrStatusLabel.maximumNumberOfLines = 3

        // Layout
        for sub in [
            engineLabel, appleRadio, qwen3Radio,
            pathLabel, modelPathField, downloadButton, browseButton,
            sizeLabel, size06Radio, modelDownloadProgress,
            asrStatusLabel,
        ] {
            view.addSubview(sub)
        }

        let labelWidth: CGFloat = 72
        let margin: CGFloat = 20

        NSLayoutConstraint.activate([
            // Engine label
            engineLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: margin),
            engineLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),

        // System speech recognition radio
            appleRadio.topAnchor.constraint(equalTo: engineLabel.bottomAnchor, constant: 8),
            appleRadio.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin + 16),

            // Qwen3 radio
            qwen3Radio.topAnchor.constraint(equalTo: appleRadio.bottomAnchor, constant: 4),
            qwen3Radio.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin + 16),

            // Path label
            pathLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin + 32),
            pathLabel.topAnchor.constraint(equalTo: qwen3Radio.bottomAnchor, constant: 10),
            pathLabel.widthAnchor.constraint(equalToConstant: labelWidth),

            // Path field + browse
            modelPathField.leadingAnchor.constraint(equalTo: pathLabel.trailingAnchor, constant: 4),
            modelPathField.centerYAnchor.constraint(equalTo: pathLabel.centerYAnchor),
            modelPathField.trailingAnchor.constraint(equalTo: downloadButton.leadingAnchor, constant: -8),
            modelPathField.heightAnchor.constraint(equalToConstant: 22),

            downloadButton.centerYAnchor.constraint(equalTo: pathLabel.centerYAnchor),
            downloadButton.trailingAnchor.constraint(equalTo: browseButton.leadingAnchor, constant: -8),

            browseButton.centerYAnchor.constraint(equalTo: pathLabel.centerYAnchor),
            browseButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),

            // Size label
            sizeLabel.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 14),
            sizeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin + 32),

            // Size radios
            size06Radio.topAnchor.constraint(equalTo: sizeLabel.bottomAnchor, constant: 6),
            size06Radio.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin + 48),

            modelDownloadProgress.topAnchor.constraint(equalTo: size06Radio.bottomAnchor, constant: 10),
            modelDownloadProgress.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            modelDownloadProgress.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),

            // Status
            asrStatusLabel.topAnchor.constraint(equalTo: modelDownloadProgress.bottomAnchor, constant: 10),
            asrStatusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            asrStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
        ])

        item.view = view
        tabView.addTabViewItem(item)
    }

    // MARK: - LLM Tab

    private func setupLLMTab() {
        let item = NSTabViewItem(identifier: "llm")
        item.label = "LLM"
        let view = NSView()

        let baseURLLabel = makeLabel("API Base URL:")
        let apiKeyLabel = makeLabel("API Key:")
        let modelLabel = makeLabel("Model:")

        baseURLField.placeholderString = "https://api.openai.com"
        baseURLField.translatesAutoresizingMaskIntoConstraints = false
        baseURLField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        baseURLField.controlSize = .small

        apiKeyField.placeholderString = "sk-..."
        apiKeyField.translatesAutoresizingMaskIntoConstraints = false
        apiKeyField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        apiKeyField.controlSize = .small

        modelField.placeholderString = "gpt-4o-mini"
        modelField.translatesAutoresizingMaskIntoConstraints = false
        modelField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        modelField.controlSize = .small

        testButton.title = "Test"
        testButton.bezelStyle = .rounded
        testButton.translatesAutoresizingMaskIntoConstraints = false
        testButton.target = self
        testButton.action = #selector(testConnection(_:))

        saveButton.title = "Save"
        saveButton.bezelStyle = .rounded
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(saveLLMSettings(_:))

        llmStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        llmStatusLabel.font = NSFont.systemFont(ofSize: 11)
        llmStatusLabel.textColor = .secondaryLabelColor
        llmStatusLabel.maximumNumberOfLines = 2

        testSpinner = NSProgressIndicator()
        testSpinner.style = .spinning
        testSpinner.controlSize = .small
        testSpinner.translatesAutoresizingMaskIntoConstraints = false
        testSpinner.isHidden = true

        for sub: NSView in [
            baseURLLabel, baseURLField,
            apiKeyLabel, apiKeyField,
            modelLabel, modelField,
            testButton, saveButton,
            llmStatusLabel,
        ] {
            view.addSubview(sub)
        }
        view.addSubview(testSpinner)

        let labelWidth: CGFloat = 100
        let margin: CGFloat = 20

        NSLayoutConstraint.activate([
            baseURLLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            baseURLLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: margin),
            baseURLLabel.widthAnchor.constraint(equalToConstant: labelWidth),

            baseURLField.leadingAnchor.constraint(equalTo: baseURLLabel.trailingAnchor, constant: 8),
            baseURLField.topAnchor.constraint(equalTo: baseURLLabel.topAnchor),
            baseURLField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            baseURLField.heightAnchor.constraint(equalToConstant: 24),

            apiKeyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            apiKeyLabel.topAnchor.constraint(equalTo: baseURLField.bottomAnchor, constant: 12),
            apiKeyLabel.widthAnchor.constraint(equalToConstant: labelWidth),

            apiKeyField.leadingAnchor.constraint(equalTo: apiKeyLabel.trailingAnchor, constant: 8),
            apiKeyField.topAnchor.constraint(equalTo: apiKeyLabel.topAnchor),
            apiKeyField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            apiKeyField.heightAnchor.constraint(equalToConstant: 24),

            modelLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            modelLabel.topAnchor.constraint(equalTo: apiKeyField.bottomAnchor, constant: 12),
            modelLabel.widthAnchor.constraint(equalToConstant: labelWidth),

            modelField.leadingAnchor.constraint(equalTo: modelLabel.trailingAnchor, constant: 8),
            modelField.topAnchor.constraint(equalTo: modelLabel.topAnchor),
            modelField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            modelField.heightAnchor.constraint(equalToConstant: 24),

            testButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -12),
            testButton.topAnchor.constraint(equalTo: modelField.bottomAnchor, constant: 20),

            saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            saveButton.topAnchor.constraint(equalTo: modelField.bottomAnchor, constant: 20),

            llmStatusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            llmStatusLabel.topAnchor.constraint(equalTo: testButton.bottomAnchor, constant: 12),
            llmStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),

            testSpinner.trailingAnchor.constraint(equalTo: testButton.leadingAnchor, constant: -8),
            testSpinner.centerYAnchor.constraint(equalTo: testButton.centerYAnchor),
        ])

        item.view = view
        tabView.addTabViewItem(item)
    }

    // MARK: - Shortcut Tab

    private func setupShortcutTab() {
        let item = NSTabViewItem(identifier: "shortcut")
        item.label = "快捷键"
        let view = NSView()

        // --- Current shortcut ---
        let shortcutTitleLabel = makeTitleLabel("当前快捷键")
        shortcutDisplayField.translatesAutoresizingMaskIntoConstraints = false
        shortcutDisplayField.isEditable = false
        shortcutDisplayField.isBezeled = true
        shortcutDisplayField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        shortcutDisplayField.alignment = .center
        shortcutDisplayField.backgroundColor = .controlBackgroundColor

        recordShortcutButton.title = "录制快捷键"
        recordShortcutButton.bezelStyle = .rounded
        recordShortcutButton.translatesAutoresizingMaskIntoConstraints = false
        recordShortcutButton.target = self
        recordShortcutButton.action = #selector(startRecordingShortcut(_:))

        // --- Long press threshold ---
        let thresholdTitleLabel = makeTitleLabel("长按阈值")
        thresholdSlider.translatesAutoresizingMaskIntoConstraints = false
        thresholdSlider.minValue = 200
        thresholdSlider.maxValue = 1000
        thresholdSlider.altIncrementValue = 50
        thresholdSlider.isContinuous = true
        thresholdSlider.target = self
        thresholdSlider.action = #selector(thresholdChanged(_:))

        thresholdValueLabel.translatesAutoresizingMaskIntoConstraints = false
        thresholdValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        thresholdValueLabel.alignment = .center

        // --- Short press behavior ---
        let shortPressTitleLabel = makeTitleLabel("短按行为")
        shortPressPopup.translatesAutoresizingMaskIntoConstraints = false
        shortPressPopup.addItems(withTitles: ["无操作", "切换收听模式"])
        shortPressPopup.target = self
        shortPressPopup.action = #selector(shortPressBehaviorChanged(_:))

        resetShortcutButton.title = "恢复默认"
        resetShortcutButton.bezelStyle = .rounded
        resetShortcutButton.translatesAutoresizingMaskIntoConstraints = false
        resetShortcutButton.target = self
        resetShortcutButton.action = #selector(resetShortcutDefaults(_:))

        for sub in [
            shortcutTitleLabel, shortcutDisplayField, recordShortcutButton,
            thresholdTitleLabel, thresholdSlider, thresholdValueLabel,
            shortPressTitleLabel, shortPressPopup,
            resetShortcutButton,
        ] {
            view.addSubview(sub)
        }

        let margin: CGFloat = 20

        NSLayoutConstraint.activate([
            // Shortcut display
            shortcutTitleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: margin),
            shortcutTitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),

            shortcutDisplayField.topAnchor.constraint(equalTo: shortcutTitleLabel.bottomAnchor, constant: 8),
            shortcutDisplayField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            shortcutDisplayField.widthAnchor.constraint(equalToConstant: 160),
            shortcutDisplayField.heightAnchor.constraint(equalToConstant: 28),

            recordShortcutButton.centerYAnchor.constraint(equalTo: shortcutDisplayField.centerYAnchor),
            recordShortcutButton.leadingAnchor.constraint(equalTo: shortcutDisplayField.trailingAnchor, constant: 12),

            // Threshold
            thresholdTitleLabel.topAnchor.constraint(equalTo: shortcutDisplayField.bottomAnchor, constant: 20),
            thresholdTitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),

            thresholdSlider.topAnchor.constraint(equalTo: thresholdTitleLabel.bottomAnchor, constant: 6),
            thresholdSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            thresholdSlider.widthAnchor.constraint(equalToConstant: 260),

            thresholdValueLabel.centerYAnchor.constraint(equalTo: thresholdSlider.centerYAnchor),
            thresholdValueLabel.leadingAnchor.constraint(equalTo: thresholdSlider.trailingAnchor, constant: 12),

            // Short press behavior
            shortPressTitleLabel.topAnchor.constraint(equalTo: thresholdSlider.bottomAnchor, constant: 20),
            shortPressTitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),

            shortPressPopup.topAnchor.constraint(equalTo: shortPressTitleLabel.bottomAnchor, constant: 6),
            shortPressPopup.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),

            // Reset button
            resetShortcutButton.topAnchor.constraint(equalTo: shortPressPopup.bottomAnchor, constant: 20),
            resetShortcutButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
        ])

        item.view = view
        tabView.addTabViewItem(item)
    }

    // MARK: - Helpers

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .right
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        return label
    }

    private func makeTitleLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.boldSystemFont(ofSize: 12)
        label.textColor = .labelColor
        return label
    }

    // MARK: - Key Code Display

    private func keyCodeToDisplayName(_ keyCode: Int64) -> String {
        let map: [Int64: String] = [
            // Letters
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
            34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
            12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
            16: "Y", 6: "Z",
            // Numbers
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6",
            26: "7", 28: "8", 25: "9",
            // Modifiers
            54: "右 Command", 55: "左 Command",
            56: "左 Shift", 60: "右 Shift",
            58: "左 Option", 61: "右 Option",
            59: "左 Control", 62: "右 Control",
            63: "Fn",
            // Special keys
            49: "Space", 36: "Return", 53: "Escape", 48: "Tab",
            51: "Delete", 117: "Forward Delete",
            // Function keys
            122: "F1", 120: "F2", 99: "F3", 118: "F4",
            96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
            // Arrows
            123: "左箭头", 124: "右箭头", 125: "下箭头", 126: "上箭头",
            // Punctuation
            27: "-", 24: "=", 33: "[", 30: "]", 42: "\\",
            41: ";", 39: "'", 43: ",", 47: ".", 44: "/",
            50: "`",
        ]
        return map[keyCode] ?? "按键 \(keyCode)"
    }

    // MARK: - Settings Loading

    private func loadAllSettings() {
        loadASRSettings()
        loadLLMSettings()
        loadShortcutSettings()
    }

    private func loadASRSettings() {
        let selected = asrManager.effectiveSelectedEngineType
        appleRadio.state = (selected == .apple) ? .on : .off
        qwen3Radio.state = (selected == .qwen3) ? .on : .off
        modelPathField.stringValue = asrManager.qwen3ModelPath ?? ""
        size06Radio.state = (asrManager.qwen3ModelSize == .size0_6B) ? .on : .off
        updateASRStatus()
        updateQwen3ControlsEnabled()
    }

    private func loadLLMSettings() {
        let refiner = LLMRefiner()
        baseURLField.stringValue = refiner.baseURL ?? ""
        apiKeyField.stringValue = refiner.apiKey ?? ""
        modelField.stringValue = refiner.model ?? ""
    }

    private func loadShortcutSettings() {
        let shortcutManager = ShortcutManager.shared
        let keyCode = shortcutManager.shortcutKeyCode
        shortcutDisplayField.stringValue = keyCodeToDisplayName(keyCode)
        thresholdSlider.doubleValue = shortcutManager.longPressThreshold * 1000
        thresholdValueLabel.stringValue = "\(Int(thresholdSlider.doubleValue)) ms"
        shortPressPopup.selectItem(at: shortcutManager.shortPressBehavior == .toggleListening ? 1 : 0)
    }

    // MARK: - ASR Actions

    @objc private func asrEngineChanged(_ sender: NSButton) {
        if sender == appleRadio {
            asrManager.selectEngine(.apple)
        } else {
            asrManager.selectEngine(.qwen3)
        }
        loadASRSettings()
    }

    @objc private func downloadQwen3Model(_ sender: NSButton) {
        guard modelDownloadTask == nil else { return }

        let modelSize = asrManager.qwen3ModelSize
        setModelDownloadInProgress(true)
        setASRStatus("准备下载 \(modelSize.rawValue) 模型...", color: .secondaryLabelColor)

        modelDownloadTask = Task { [weak self] in
            do {
                guard let self else { return }
                let coordinator = SettingsQwenModelDownloadCoordinator(
                    asrManager: self.asrManager,
                    downloader: self.modelDownloader
                )
                let modelURL = try await coordinator.downloadQwen3Model(size: modelSize) { [weak self] progress in
                    self?.updateModelDownloadProgress(progress)
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.modelDownloadTask = nil
                    self.loadASRSettings()
                    self.modelDownloadProgress.doubleValue = 1
                    self.setASRStatus("模型下载完成：\(modelURL.path)", color: .systemGreen)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.modelDownloadTask = nil
                    self.loadASRSettings()
                    self.setASRStatus("模型下载失败：\(error.localizedDescription)", color: .systemRed)
                }
            }
        }
    }

    @objc private func browseModelPath(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择包含 Qwen3-ASR encoder、decoder、embedding 和词表的模型目录"
        panel.prompt = "选择"

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.asrManager.qwen3ModelPath = url.path
            self?.loadASRSettings()
        }
    }

    @objc private func qwen3SizeChanged(_ sender: NSButton) {
        asrManager.qwen3ModelSize = .size0_6B
        loadASRSettings()
    }

    private func updateASRStatus() {
        let path = asrManager.qwen3ModelPath
        if let path = path, !path.isEmpty {
            if asrManager.isQwen3ModelAvailable {
                asrStatusLabel.stringValue = "Qwen3-ASR 模型已配置：\(path)"
                asrStatusLabel.textColor = .systemGreen
            } else {
                asrStatusLabel.stringValue = "模型目录不完整或与当前模型大小不匹配：\(path)。请先下载模型，或浏览选择本地模型目录。"
                asrStatusLabel.textColor = .systemRed
            }
        } else {
            asrStatusLabel.stringValue = "Qwen3-ASR 需要先下载模型并选择本地模型目录，配置完成前不可切换。"
            asrStatusLabel.textColor = .systemOrange
        }
    }

    private func setASRStatus(_ text: String, color: NSColor) {
        asrStatusLabel.stringValue = text
        asrStatusLabel.textColor = color
    }

    private func updateModelDownloadProgress(_ progress: Qwen3ModelDownloadProgress) {
        modelDownloadProgress.doubleValue = progress.overallProgress
        let percent = Int(progress.overallProgress * 100)
        setASRStatus(
            "正在下载模型 \(percent)%（\(progress.fileIndex + 1)/\(progress.fileCount)：\(progress.fileName)）",
            color: .secondaryLabelColor
        )
    }

    private func setModelDownloadInProgress(_ isDownloading: Bool) {
        modelDownloadProgress.isHidden = !isDownloading
        downloadButton.isEnabled = !isDownloading
        browseButton.isEnabled = !isDownloading
        size06Radio.isEnabled = !isDownloading
    }

    private func updateQwen3ControlsEnabled() {
        guard modelDownloadTask == nil else {
            setModelDownloadInProgress(true)
            return
        }
        qwen3Radio.isEnabled = asrManager.isQwen3ModelAvailable
        modelPathField.isEnabled = true
        downloadButton.isEnabled = true
        browseButton.isEnabled = true
        size06Radio.isEnabled = true
    }

    // MARK: - LLM Actions

    @objc private func saveLLMSettings(_ sender: Any) {
        let refiner = LLMRefiner()
        let baseURL = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = apiKeyField.stringValue
        let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try refiner.setAPIKey(apiKey.isEmpty ? nil : apiKey)
        } catch {
            setLLMStatus("API Key 保存失败：\(error.localizedDescription)", color: .systemRed)
            return
        }

        refiner.baseURL = baseURL.isEmpty ? nil : baseURL
        refiner.model = model.isEmpty ? nil : model

        setLLMStatus("设置已保存。", color: .systemGreen)
    }

    @objc private func testConnection(_ sender: Any) {
        let baseURL = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = apiKeyField.stringValue
        let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseURL.isEmpty, !apiKey.isEmpty, !model.isEmpty else {
            setLLMStatus("请填写所有字段后再测试。", color: .systemOrange)
            return
        }

        testButton.isEnabled = false
        testSpinner.isHidden = false
        testSpinner.startAnimation(nil)
        setLLMStatus("正在测试连接...", color: .secondaryLabelColor)

        Task { [weak self] in
            let refiner = LLMRefiner()
            let result = await refiner.testConnection(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.testButton.isEnabled = true
                self.testSpinner.isHidden = true
                self.testSpinner.stopAnimation(nil)

                switch result {
                case .success(let message):
                    self.setLLMStatus(message, color: .systemGreen)
                case .failure(let error):
                    self.setLLMStatus("连接失败：\(error.localizedDescription)", color: .systemRed)
                }
            }
        }
    }

    private func setLLMStatus(_ text: String, color: NSColor) {
        llmStatusLabel.stringValue = text
        llmStatusLabel.textColor = color
    }

    // MARK: - Shortcut Actions

    @objc private func startRecordingShortcut(_ sender: NSButton) {
        guard let settingsWindow = window else { return }

        removeShortcutEventMonitors()

        // Close existing sheet if any
        if let sheet = shortcutRecordingSheet {
            settingsWindow.endSheet(sheet)
        }

        // Create sheet
        let sheet = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheet.title = "录制快捷键"

        let label = NSTextField(labelWithString: "按下要设置的快捷键...")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 14)
        label.alignment = .center

        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancelShortcutRecording(_:)))
        cancelButton.bezelStyle = .rounded
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        guard let sheetView = sheet.contentView else { return }
        sheetView.addSubview(label)
        sheetView.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: sheetView.centerXAnchor),
            label.topAnchor.constraint(equalTo: sheetView.topAnchor, constant: 20),
            cancelButton.centerXAnchor.constraint(equalTo: sheetView.centerXAnchor),
            cancelButton.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 16),
        ])

        shortcutRecordingSheet = sheet
        settingsWindow.makeKeyAndOrderFront(nil)

        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleRecordedKeyEvent(event)
            return nil // Suppress the event
        }
        if let localMonitor {
            shortcutEventMonitors.append(localMonitor)
        }

        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleRecordedKeyEvent(event)
        }
        if let globalMonitor {
            shortcutEventMonitors.append(globalMonitor)
        }

        settingsWindow.beginSheet(sheet) { [weak self] _ in
            self?.removeShortcutEventMonitors()
            self?.shortcutRecordingSheet = nil
        }
    }

    @objc private func cancelShortcutRecording(_ sender: NSButton) {
        guard let window = window, let sheet = shortcutRecordingSheet else { return }
        window.endSheet(sheet)
    }

    private func removeShortcutEventMonitors() {
        for monitor in shortcutEventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        shortcutEventMonitors.removeAll()
    }

    private func handleRecordedKeyEvent(_ event: NSEvent) {
        guard shortcutRecordingSheet != nil else { return }

        let keyCode = Int64(event.keyCode)

        // For flagsChanged events, only accept modifier keys.
        if event.type == .flagsChanged {
            let modifierKeyCodes: Set<Int64> = [54, 55, 56, 60, 58, 61, 59, 62, 63]
            guard modifierKeyCodes.contains(keyCode) else { return }
        }

        ShortcutManager.shared.shortcutKeyCode = keyCode
        shortcutDisplayField.stringValue = keyCodeToDisplayName(keyCode)

        guard let window = window, let sheet = shortcutRecordingSheet else { return }
        window.endSheet(sheet)
    }

    @objc private func thresholdChanged(_ sender: NSSlider) {
        let ms = sender.doubleValue
        thresholdValueLabel.stringValue = "\(Int(ms)) ms"
        ShortcutManager.shared.longPressThreshold = ms / 1000.0
    }

    @objc private func shortPressBehaviorChanged(_ sender: NSPopUpButton) {
        let behavior: ShortPressBehavior = sender.indexOfSelectedItem == 1 ? .toggleListening : .none
        ShortcutManager.shared.shortPressBehavior = behavior
    }

    @objc private func resetShortcutDefaults(_ sender: NSButton) {
        let manager = ShortcutManager.shared
        manager.shortcutKeyCode = 54  // Right Command
        manager.longPressThreshold = 0.5
        manager.shortPressBehavior = .toggleListening
        loadShortcutSettings()
    }

    // MARK: - Show

    /// Shows the settings window, optionally switching to a specific tab.
    func show(tab: SettingsTab = .llm) {
        loadAllSettings()
        tabView.selectTabViewItem(at: tab.rawValue)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.makeMain()
    }
}
