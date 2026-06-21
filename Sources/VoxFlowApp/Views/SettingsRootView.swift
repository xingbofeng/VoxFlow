import AppKit
import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var llmProviderViewModel: LLMProviderViewModel
    @ObservedObject var asrProviderViewModel: ASRProviderViewModel
    @StateObject private var ttsCapabilityModelViewModel = CapabilityModelViewModel(kind: .tts)
    @StateObject private var translationCapabilityModelViewModel = CapabilityModelViewModel(kind: .translation)
    @State private var recordingShortcutAction: VoiceAction?
    @State private var shortcutMonitor: Any?
    @State private var importedJSON = ""
    @State private var newAgentAlias = ""
    @State private var aliasTargetAgentID = ""
    @State private var showDeleteAllLocalModelsConfirmation = false
    @State private var showAgentCLIRegistrationConfirmation = false
    @State private var showAgentCLIUnregistrationConfirmation = false
    @AppStorage(RepositoryBackedLLMRefiner.enabledDefaultsKey) private var llmCorrectionEnabled = false

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(viewModel.selectedSection.pageTitle)
                        .font(.system(size: 30, weight: .bold))
                    sectionContent
                }
                .padding(30)
                .frame(maxWidth: 1_080, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .background(AppTheme.ColorToken.pageBackground)
        .tint(AppTheme.ColorToken.accent)
        .actionFeedbackOverlay(
            message: actionFeedbackMessage,
            error: actionFeedbackError,
            onDismiss: clearActionFeedback
        )
        .confirmationDialog(
            "删除全部本地模型？",
            isPresented: $showDeleteAllLocalModelsConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除全部本地模型", role: .destructive) {
                perform { try viewModel.deleteAllLocalModels() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除 \(viewModel.localModelStorageDescription()) 的本地 ASR 模型文件，并把当前本地识别 Provider 回退到系统自带。")
        }
        .confirmationDialog(
            "注册终端命令？",
            isPresented: $showAgentCLIRegistrationConfirmation,
            titleVisibility: .visible
        ) {
            Button("确认注册") {
                viewModel.registerAgentCLI()
            }
            Button("取消", role: .cancel) {}
        } message: {
            let preview = viewModel.agentCLIRegistrationPreview()
            Text("将安装 voxflow/vox 命令，并在 \(preview.profileURL.path) 追加：\n\n\(preview.shellBlock)")
        }
        .confirmationDialog(
            "卸载终端命令？",
            isPresented: $showAgentCLIUnregistrationConfirmation,
            titleVisibility: .visible
        ) {
            Button("卸载命令", role: .destructive) {
                viewModel.unregisterAgentCLI()
            }
            Button("取消", role: .cancel) {}
        } message: {
            let preview = viewModel.agentCLIRegistrationPreview()
            Text("将移除 VoxFlow 管理的 voxflow/vox 命令链接，并从 \(preview.profileURL.path) 删除 VoxFlow PATH 配置。")
        }
        .onAppear {
            viewModel.loadIfNeeded()
        }
        .onDisappear {
            stopShortcutRecording()
        }
    }

    private var actionFeedbackMessage: String? {
        viewModel.lastActionMessage
            ?? llmProviderViewModel.lastActionMessage
            ?? asrProviderViewModel.lastActionMessage
    }

    private var actionFeedbackError: String? {
        viewModel.lastError
            ?? llmProviderViewModel.lastError
            ?? asrProviderViewModel.lastError
    }

    private func clearActionFeedback() {
        viewModel.clearFeedback()
        llmProviderViewModel.clearFeedback()
        asrProviderViewModel.clearFeedback()
    }

    private var unresolvedBehaviorHelpText: String {
        """
        询问确认：让你选择队员
        取消发送：保留文本不发送
        模型判断：用 LLM 排序候选
        默认发送：写入当前输入框
        """
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("应用设置")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            settingsSidebarButton(.general)
            settingsSidebarButton(.vibeCoding)
            settingsSidebarButton(.dictationModels)
            settingsSidebarButton(.correctionModels)
            settingsSidebarButton(.ttsModels)
            settingsSidebarButton(.translationModels)
            settingsSidebarButton(.system)

            Text("数据与隐私")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 4)

            settingsSidebarButton(.dataPrivacy)
            Spacer()
            Text("v\(AppVersionInfo.current().displayText)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .padding(.horizontal, 12)
        }
        .padding(16)
        .frame(width: 220)
        .background(AppTheme.ColorToken.sidebarBackground)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch viewModel.selectedSection {
        case .general:
            generalSection
        case .vibeCoding:
            vibeCodingSection
        case .dictationModels:
            dictationModelsSection
        case .correctionModels:
            correctionModelsSection
        case .ttsModels:
            ttsModelsSection
        case .translationModels:
            translationModelsSection
        case .system:
            systemSection
        case .dataPrivacy:
            dataPrivacySection
        }
    }

    private var dictationModelsSection: some View {
        SettingsGroupCard(
            title: "ASR 模型",
            subtitle: "选择语音识别方式和本地模型大小",
            systemImage: "waveform",
            tint: AppTheme.ColorToken.accent
        ) {
            ASRProviderView(viewModel: asrProviderViewModel, embedded: true)
        }
    }

    private var correctionModelsSection: some View {
        SettingsGroupCard(
            title: "LLM 模型",
            subtitle: "配置用于纠错、翻译 fallback 和总结的 OpenAI 兼容模型",
            systemImage: "sparkles",
            tint: .blue
        ) {
            SettingsToggleRow(
                title: "启用 LLM 纠错",
                subtitle: "听写完成后使用默认 OpenAI 兼容模型润色文本",
                systemImage: "sparkles",
                tint: .blue,
                isOn: $llmCorrectionEnabled
            )
            LLMProviderView(viewModel: llmProviderViewModel, embedded: true)
        }
    }

    private var ttsModelsSection: some View {
        SettingsGroupCard(
            title: "TTS 模型",
            subtitle: "选择 HUD 原文和译文朗读使用的本地语音合成模型",
            systemImage: "speaker.wave.2",
            tint: .green
        ) {
            CapabilityModelView(viewModel: ttsCapabilityModelViewModel)
        }
    }

    private var translationModelsSection: some View {
        SettingsGroupCard(
            title: "翻译模型",
            subtitle: "选择截图 OCR 翻译使用的本地模型和 fallback 路径",
            systemImage: "globe.asia.australia",
            tint: .teal
        ) {
            CapabilityModelView(viewModel: translationCapabilityModelViewModel)
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            inputLanguageCard
                .frame(maxWidth: .infinity, alignment: .leading)

            SettingsGroupCard(
                title: "快捷键",
                subtitle: "自定义全局快捷键和触发行为",
                systemImage: "keyboard",
                tint: .purple
            ) {
                VStack(spacing: 12) {
                    actionShortcutRow(
                        action: .dictation,
                        title: "语音转录",
                        subtitle: "按住快捷键说话，松开后转写并输入",
                        buttonTitle: "修改"
                    )

                    Divider()
                        .padding(.leading, 70)

                    actionShortcutRow(
                        action: .agentCompose,
                        title: "帮我说",
                        subtitle: "结合当前窗口和口述生成文本，完成后写入当前输入框",
                        buttonTitle: "设置快捷键",
                        badge: "不自动发送",
                        prominentWhenUnbound: true
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 14) {
                            Text("触发方式")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppTheme.ColorToken.primaryText)
                            Picker("触发方式", selection: shortPressTriggerBinding) {
                                Text("按住").tag(false)
                                Text("切换").tag(true)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                            Spacer(minLength: 0)
                        }
                        Text(viewModel.shortcutConflict ? "当前快捷键冲突，请为两个动作设置不同按键。" : "两个动作不能使用相同触发方式")
                            .font(.system(size: 12))
                            .foregroundStyle(viewModel.shortcutConflict ? Color.red : AppTheme.ColorToken.secondaryText)
                    }
                    .padding(12)
                    .background(AppTheme.ColorToken.panelBackground.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
                }
            }
        }
    }

    private var vibeCodingSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroupCard(
                title: "Vibe Coding 指挥中心",
                subtitle: "用语音把指令发给正在工作的终端 Agent",
                systemImage: "terminal",
                tint: AppTheme.ColorToken.accent
            ) {
                SettingsToggleRow(
                    title: "启用指挥中心",
                    subtitle: "开启后，现有语音输入快捷键会进入 Vibe Coding 指挥 HUD",
                    systemImage: "terminal",
                    tint: AppTheme.ColorToken.accent,
                    isOn: Binding(
                        get: { viewModel.agentDispatchEnabled },
                        set: { enabled in perform { try viewModel.setAgentDispatchEnabled(enabled) } }
                    )
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("注册终端命令")
                                .font(.system(size: 15, weight: .semibold))
                            Text("在 Ghostty、iTerm2 或 Terminal 中用以下命令启动队员")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        }
                        Spacer()
                        Button("复制示例") { viewModel.copyAgentCLIExamples() }
                            .buttonStyle(.bordered)
                        Button("卸载命令", role: .destructive) {
                            showAgentCLIUnregistrationConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        Button("注册命令") { showAgentCLIRegistrationConfirmation = true }
                            .buttonStyle(.borderedProminent)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("vox flow codex")
                        Text("vox flow --claude")
                        Text("vox flow --codebuddy")
                    }
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)

                    if let status = viewModel.agentCLIRegistrationStatus {
                        Text(status.isOnCurrentPath
                             ? "已注册，可在新终端中直接使用"
                             : "已注册到 \(status.binDirectory.path)，请新开终端后使用")
                            .font(.system(size: 12))
                            .foregroundStyle(status.isOnCurrentPath ? Color.green : Color.orange)
                    }
                }
                .settingsRow()

                SettingsToggleRow(
                    title: "准确命名时直接发送",
                    subtitle: "唯一准确命中队员名或用户别名时，不调用模型、不二次确认",
                    systemImage: "paperplane.fill",
                    tint: .green,
                    isOn: Binding(
                        get: { viewModel.agentDispatchExactDirectEnabled },
                        set: { enabled in perform { try viewModel.setAgentDispatchExactDirectEnabled(enabled) } }
                    )
                )

                HStack(spacing: 14) {
                    SettingsRowIcon(systemImage: "questionmark.bubble", tint: .orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("未命中队员名")
                            .font(.system(size: 15, weight: .semibold))
                        Text("低置信结果按所选方式处理")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        Picker("未命中队员名", selection: Binding(
                            get: { viewModel.agentDispatchUnresolvedBehavior },
                            set: { value in perform { try viewModel.setAgentDispatchUnresolvedBehavior(value) } }
                        )) {
                            Text("询问确认").tag("confirm")
                            Text("取消发送").tag("cancel")
                            Text("模型判断").tag("model")
                            Text("默认发送").tag("default")
                        }
                        .labelsHidden()
                        .frame(width: 180, alignment: .trailing)

                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                            .help(unresolvedBehaviorHelpText)
                    }
                    .frame(width: 248, alignment: .trailing)
                }
                .settingsRow()

                SettingsToggleRow(
                    title: "MCP 自报身份",
                    subtitle: "不做心跳，仅在任务变化时低频更新队员摘要和会话引用",
                    systemImage: "person.text.rectangle",
                    tint: .teal,
                    isOn: Binding(
                        get: { viewModel.agentDispatchMCPEnabled },
                        set: { enabled in perform { try viewModel.setAgentDispatchMCPEnabled(enabled) } }
                    )
                )
            }

        }
    }

    private var inputLanguageCard: some View {
        SettingsGroupCard(
            title: "输入与语言",
            subtitle: "选择麦克风和默认识别语言",
            systemImage: "mic",
            tint: .orange
        ) {
            HStack(alignment: .top, spacing: 12) {
                inputDeviceRow
                recognitionLanguageRow
            }
        }
    }

    private var inputDeviceRow: some View {
        Menu {
            ForEach(viewModel.inputDevices, id: \.id) { device in
                Button {
                    perform { try viewModel.selectInputDevice(id: device.id) }
                } label: {
                    if device.id == viewModel.selectedInputDeviceID {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 14) {
                SettingsRowIcon(systemImage: "mic", tint: .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("输入设备")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                    Text(selectedInputDeviceName)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(selectedInputDeviceName)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            .settingsRow()
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recognitionLanguageRow: some View {
        Menu {
            ForEach(viewModel.recognitionLanguages, id: \.rawValue) { language in
                Button {
                    perform { try viewModel.setRecognitionLanguage(language) }
                } label: {
                    if language == viewModel.selectedRecognitionLanguage {
                        Label(language.displayName, systemImage: "checkmark")
                    } else {
                        Text(language.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 14) {
                SettingsRowIcon(systemImage: "globe.asia.australia", tint: .teal)
                VStack(alignment: .leading, spacing: 4) {
                    Text("识别语言")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                    Text(selectedRecognitionLanguageName)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            .settingsRow()
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroupCard(
                title: "音频反馈",
                subtitle: "管理录音时的声音行为",
                systemImage: "speaker.wave.2",
                tint: .blue
            ) {
                SettingsToggleRow(
                    title: "录音时静音",
                    subtitle: "录音时自动静音其他正在播放的音频",
                    systemImage: "speaker.slash",
                    tint: .blue,
                    isOn: muteBinding
                )
                SettingsToggleRow(
                    title: "音频反馈提示音",
                    subtitle: "在录音开始、处理和完成时播放提示音",
                    systemImage: "bell",
                    tint: .blue,
                    isOn: soundBinding
                )
            }

            SettingsGroupCard(
                title: "声音增强",
                subtitle: "自动调节麦克风音量，获得更清晰的录音效果",
                systemImage: "waveform.path",
                tint: .green
            ) {
                SettingsToggleRow(
                    title: "启用声音增强",
                    subtitle: "自动放大较弱的声音，使音量更加均匀",
                    systemImage: "waveform.path",
                    tint: .green,
                    isOn: enhancementBinding
                )
            }

            SettingsGroupCard(
                title: "性能优化",
                subtitle: "优化应用性能和资源占用",
                systemImage: "bolt",
                tint: .yellow
            ) {
                systemToggle(.keepMicrophoneActive, "保持麦克风活跃", "录音结束后保持麦克风权限活跃，减少下次启动延迟", "bolt", tint: .yellow)
                systemToggle(.localModelLivePreview, "本地模型实时预览", "录音时为本地模型显示快速预览", "waveform", tint: .yellow)
                systemToggle(.autoReleaseLocalModel, "自动释放本地模型内存", "空闲 15 分钟后释放本地模型内存", "internaldrive", tint: .yellow)
            }

            SettingsGroupCard(
                title: "文本输出",
                subtitle: "配置文本的插入和剪贴板处理方式",
                systemImage: "textformat",
                tint: .indigo
            ) {
                systemToggle(.avoidClipboard, "不使用剪贴板", "使用键盘输入代替剪贴板粘贴", "clipboard", tint: .indigo)
                systemToggle(.restoreClipboard, "还原剪贴板内容", "输出完成后恢复之前的剪贴板内容", "clipboard.fill", tint: .indigo)
                systemToggle(.clipboardImageOCR, "剪贴板图片 OCR", "剪贴板里是图片时，Command+Shift+V 先识别图片文字再粘贴", "doc.viewfinder", tint: .indigo)
            }

            SettingsGroupCard(
                title: "启动与外观",
                subtitle: "自定义应用启动行为和状态显示",
                systemImage: "paintpalette",
                tint: .pink
            ) {
                systemToggle(.darkMode, "深色模式", "使用深色配色方案显示应用界面", "moon", tint: .pink)
                systemToggle(.launchAtLogin, "开机自动启动", "登录系统时自动启动码上写", "power", tint: .pink)
                systemToggle(.grayMenuBarIcon, "灰色菜单栏图标", "让菜单栏图标使用低对比灰色", "paintpalette", tint: .pink)
                systemToggle(.capsLockIndicator, "CapsLock 指示灯", "使用 CapsLock LED 指示录音状态", "lightbulb", tint: .pink)
            }
        }
    }

    private var dataPrivacySection: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroupCard(
                title: "状态与权限",
                subtitle: "管理系统访问权限",
                systemImage: "shield",
                tint: .green
            ) {
                permissionRow(
                    title: "麦克风",
                    subtitle: "用于录制你的声音",
                    systemImage: "mic",
                    status: viewModel.microphonePermission.title,
                    granted: viewModel.microphonePermission == .granted,
                    pane: .microphone
                )
                permissionRow(
                    title: "辅助功能",
                    subtitle: "用于将转写文本输入到当前应用",
                    systemImage: "accessibility",
                    status: viewModel.accessibilityGranted ? "已授权" : "未授权",
                    granted: viewModel.accessibilityGranted,
                    pane: .accessibility
                )
                permissionRow(
                    title: "语音识别",
                    subtitle: "显示 Apple 语音识别的真实系统授权状态",
                    systemImage: "waveform",
                    status: viewModel.speechPermission.title,
                    granted: viewModel.speechPermission == .granted,
                    pane: .speech
                )
                permissionRow(
                    title: "屏幕录制",
                    subtitle: "用于“帮我说”的当前窗口 OCR，上下文截图不会保存",
                    systemImage: "rectangle.inset.filled.and.person.filled",
                    status: PermissionSummary.statusText(viewModel.screenRecordingGranted),
                    granted: viewModel.screenRecordingGranted,
                    pane: .screenRecording
                )

                VStack(alignment: .leading, spacing: 6) {
                    Label("权限信息", systemImage: "info.circle")
                        .font(.system(size: 13, weight: .semibold))
                    Text("如果文本输入失败，请检查辅助功能权限。本地模型不依赖 Apple 语音识别，但这里仍展示其真实系统状态。")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            SettingsGroupCard(
                title: "隐私与分析",
                subtitle: "控制数据共享和本地诊断设置",
                systemImage: "chart.bar",
                tint: .purple
            ) {
                SettingsToggleRow(
                    title: "使用分析",
                    subtitle: "共享匿名使用统计，不收集个人数据、音频或转写文本",
                    systemImage: "chart.bar",
                    tint: .purple,
                    isOn: analyticsBinding
                )
                systemToggle(.crashLogs, "崩溃日志", "仅在本地保存崩溃信息和堆栈，用于排查问题", "ladybug", tint: .purple)
                systemToggle(
                    .llmTraceDiagnostics,
                    "LLM 诊断采集",
                    "默认关闭；开启后单独保存原始调用内容，保留 7 天且最多 100 份",
                    "doc.text.magnifyingglass",
                    tint: .orange
                )
                Button("立即删除 LLM 诊断内容", role: .destructive) {
                    viewModel.clearLLMTraceDiagnostics()
                }
                .buttonStyle(.bordered)

                Text("LLM 诊断文件不会写入主数据库或自动上传。关闭诊断采集会立即删除全部诊断文件。")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingsRow()
            }

            SettingsGroupCard(
                title: "数据管理",
                subtitle: "导出、导入或清理本地数据",
                systemImage: "externaldrive",
                tint: .orange
            ) {
                HStack(spacing: 14) {
                    SettingsRowIcon(
                        systemImage: viewModel.storageStatus.isHealthy ? "internaldrive" : "exclamationmark.triangle",
                        tint: viewModel.storageStatus.isHealthy ? .green : .orange
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.storageStatus.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.ColorToken.primaryText)
                        Text(viewModel.storageStatus.message)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Text(viewModel.storageStatus.badgeText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(viewModel.storageStatus.isHealthy ? Color.green : Color.orange)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background((viewModel.storageStatus.isHealthy ? Color.green : Color.orange).opacity(0.09))
                        .clipShape(Capsule())
                }
                .settingsRow()

                HStack(spacing: 10) {
                    Button("打开数据目录") { viewModel.openApplicationSupportFolder() }
                    Button("导出数据") { perform { _ = try viewModel.exportDataJSON() } }
                    Button("清空历史", role: .destructive) { perform { try viewModel.clearHistory() } }
                    Button("删除全部本地模型", role: .destructive) {
                        showDeleteAllLocalModelsConfirmation = true
                    }
                    Button("重置设置", role: .destructive) {
                        perform {
                            try viewModel.resetSettings()
                        }
                    }
                }
                .buttonStyle(.bordered)

                TextEditor(text: $importedJSON)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.ColorToken.panelStroke)
                    )
                Button("导入设置") {
                    perform { try viewModel.importSettingsJSON(importedJSON) }
                }
                .buttonStyle(.bordered)
            }

            SettingsGroupCard(
                title: "崩溃报告",
                subtitle: "查看本地诊断文件；内容不会自动上传",
                systemImage: "ladybug",
                tint: .orange
            ) {
                HStack(spacing: 10) {
                    Button {
                        viewModel.load()
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    Button {
                        viewModel.openApplicationSupportFolder()
                    } label: {
                        Label("打开文件夹", systemImage: "folder")
                    }
                }
                .buttonStyle(.bordered)

                Text("诊断信息仅保存在本机数据目录 Application Support/VoxFlow。码上写不会自动上传音频、转录文本或崩溃日志。")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingsRow()
            }
        }
    }

    private func settingsSidebarButton(_ section: SettingsSection) -> some View {
        Button {
            viewModel.selectedSection = section
        } label: {
            HStack(spacing: 11) {
                Image(systemName: section.systemImage)
                    .frame(width: 22)
                    .foregroundStyle(
                        viewModel.selectedSection == section
                            ? AppTheme.ColorToken.accent
                            : AppTheme.ColorToken.sidebarText
                    )
                Text(section.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        viewModel.selectedSection == section
                            ? AppTheme.ColorToken.primaryText
                            : AppTheme.ColorToken.sidebarText
                    )
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(
                viewModel.selectedSection == section
                    ? AppTheme.ColorToken.selectionBackground
                    : Color.clear
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        viewModel.selectedSection == section
                            ? AppTheme.ColorToken.accent.opacity(0.25)
                            : Color.clear
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var selectedInputDeviceName: String {
        viewModel.inputDevices.first(where: { $0.id == viewModel.selectedInputDeviceID })?.name
            ?? "系统默认麦克风"
    }

    private var selectedRecognitionLanguageName: String {
        viewModel.selectedRecognitionLanguage.displayName
    }

    private func shortcutDisplayName(for action: VoiceAction) -> String {
        guard let keyCode = shortcutKeyCode(for: action) else {
            return "未设置"
        }
        return KeyCodeMapping.displayName(for: keyCode)
    }

    private func shortcutKeyIcon(for action: VoiceAction) -> String {
        guard let keyCode = shortcutKeyCode(for: action) else {
            return action.systemImage
        }
        return KeyCodeMapping.iconName(for: keyCode)
    }

    private func shortcutKeyCode(for action: VoiceAction) -> Int64? {
        switch action {
        case .dictation:
            return viewModel.dictationShortcutKeyCode ?? viewModel.shortcutKeyCode
        case .agentCompose:
            return viewModel.agentComposeShortcutKeyCode
        case .agentDispatch:
            return nil
        }
    }

    private var shortPressBehaviorDescription: String {
        switch viewModel.shortPressBehavior {
        case .toggleListening:
            return "短按切换听写：按一次开始，再按一次停止"
        case .none:
            return "短按不触发：仅长按录音，松开完成"
        }
    }

    private func permissionRow(
        title: String,
        subtitle: String,
        systemImage: String,
        status: String,
        granted: Bool,
        pane: SystemSettingsPane
    ) -> some View {
        HStack(spacing: 14) {
            SettingsRowIcon(systemImage: systemImage, tint: granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            Text(status)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(granted ? Color.green : Color.orange)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background((granted ? Color.green : Color.orange).opacity(0.09))
                .clipShape(Capsule())
            if !granted {
                Button {
                    if let url = viewModel.systemSettingsURL(for: pane) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("去设置")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                }
                .buttonStyle(.bordered)
            }
            Button {
                viewModel.load()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("重新检查")
        }
        .settingsRow()
    }

    private func systemToggle(
        _ option: SettingsSystemOption,
        _ title: String,
        _ subtitle: String,
        _ icon: String,
        tint: Color = .gray
    ) -> some View {
        SettingsToggleRow(
            title: title,
            subtitle: subtitle,
            systemImage: icon,
            tint: tint,
            isOn: Binding(
                get: { viewModel.systemOption(option) },
                set: { value in perform { try viewModel.setSystemOption(option, enabled: value) } }
            )
        )
    }

    private var shortPressToggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.shortPressBehavior == .toggleListening },
            set: { isEnabled in
                perform {
                    try viewModel.updateShortcut(
                        keyCode: viewModel.shortcutKeyCode,
                        longPressThreshold: viewModel.longPressThreshold,
                        shortPressBehavior: isEnabled ? .toggleListening : .none
                    )
                }
            }
        )
    }

    private var shortPressTriggerBinding: Binding<Bool> {
        shortPressToggleBinding
    }

    private var soundBinding: Binding<Bool> {
        Binding(
            get: { viewModel.soundFeedbackEnabled },
            set: { value in
                perform {
                    try viewModel.updateAudioOptions(
                        soundFeedback: value,
                        voiceEnhancement: viewModel.voiceEnhancementEnabled
                    )
                }
            }
        )
    }

    private var enhancementBinding: Binding<Bool> {
        Binding(
            get: { viewModel.voiceEnhancementEnabled },
            set: { value in
                perform {
                    try viewModel.updateAudioOptions(
                        soundFeedback: viewModel.soundFeedbackEnabled,
                        voiceEnhancement: value
                    )
                }
            }
        )
    }

    private var muteBinding: Binding<Bool> {
        Binding(
            get: { viewModel.muteWhileRecordingEnabled },
            set: { value in
                perform {
                    try viewModel.updatePerformanceOptions(
                        muteWhileRecording: value,
                        performanceOptimization: viewModel.performanceOptimizationEnabled
                    )
                }
            }
        )
    }

    private var analyticsBinding: Binding<Bool> {
        Binding(
            get: { viewModel.analyticsEnabled },
            set: { value in perform { try viewModel.setAnalyticsEnabled(value) } }
        )
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            viewModel.report(error: error)
        }
    }

    private func actionShortcutRow(
        action: VoiceAction,
        title: String,
        subtitle: String,
        buttonTitle: String,
        badge: String? = nil,
        prominentWhenUnbound: Bool = false
    ) -> some View {
        let isRecording = recordingShortcutAction == action
        let displayName = shortcutDisplayName(for: action)
        let isUnbound = shortcutKeyCode(for: action) == nil
        return HStack(spacing: 14) {
            SettingsRowIcon(systemImage: shortcutKeyIcon(for: action), tint: action == .agentCompose ? .green : AppTheme.ColorToken.accent)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    if let badge {
                        Text(badge)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.ColorToken.accent)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(AppTheme.ColorToken.selectionBackground)
                            .clipShape(Capsule())
                    }
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                Text(isRecording ? "按下想用于\(title)的按键" : displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isRecording ? AppTheme.ColorToken.accent : (isUnbound ? AppTheme.ColorToken.secondaryText : AppTheme.ColorToken.primaryText))
            }
            Spacer()
            shortcutActionButton(
                title: isRecording ? "正在录制..." : buttonTitle,
                prominent: prominentWhenUnbound && isUnbound,
                action: action
            )
        }
        .settingsRow()
    }

    @ViewBuilder
    private func shortcutActionButton(title: String, prominent: Bool, action: VoiceAction) -> some View {
        if prominent {
            Button(title) {
                toggleShortcutRecording(for: action)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(title) {
                toggleShortcutRecording(for: action)
            }
            .buttonStyle(.bordered)
        }
    }

    private func toggleShortcutRecording(for action: VoiceAction = .dictation) {
        if recordingShortcutAction == action {
            stopShortcutRecording()
            return
        }
        recordingShortcutAction = action
        ShortcutCaptureState.shared.isCapturing = true
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            recordShortcut(from: event)
            return nil
        }
    }

    private func stopShortcutRecording() {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
            self.shortcutMonitor = nil
        }
        recordingShortcutAction = nil
        ShortcutCaptureState.shared.isCapturing = false
    }

    private func recordShortcut(from event: NSEvent) {
        let keyCode = ShortcutManager.encodeShortcut(
            keyCode: Int64(event.keyCode),
            modifierMask: ShortcutManager.modifierMask(
                command: event.modifierFlags.contains(.command),
                shift: event.modifierFlags.contains(.shift),
                option: event.modifierFlags.contains(.option),
                control: event.modifierFlags.contains(.control)
            )
        )
        let action = recordingShortcutAction ?? .dictation
        guard keyCode > 0 else {
            viewModel.report(error: SettingsViewModelError.invalidShortcutKeyCode)
            stopShortcutRecording()
            return
        }
        perform {
            try viewModel.updateActionShortcut(action: action, keyCode: keyCode)
        }
        stopShortcutRecording()
    }

}

private struct SettingsGroupCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.09))
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(tint)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
            }
            VStack(spacing: 10) {
                content
            }
        }
        .padding(20)
        .appPanel(cornerRadius: 14)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            SettingsRowIcon(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .settingsRow()
    }
}

private struct SettingsRowIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.icon, style: .continuous)
            .fill(tint.opacity(0.09))
            .frame(width: 42, height: 42)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tint)
            }
    }
}

extension View {
    func settingsRow() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.ColorToken.controlBackground.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private extension SettingsSection {
    var pageTitle: String {
        switch self {
        case .general: return "通用"
        case .vibeCoding: return "Vibe Coding"
        case .dictationModels: return "ASR 模型"
        case .correctionModels: return "LLM 模型"
        case .ttsModels: return "TTS 模型"
        case .translationModels: return "翻译模型"
        case .system: return "系统设置"
        case .dataPrivacy: return "数据与隐私"
        }
    }
}

extension AudioRecorder.PermissionStatus {
    var title: String {
        switch self {
        case .granted: return "已授权"
        case .denied: return "未授权"
        case .notDetermined: return "未请求"
        }
    }
}
