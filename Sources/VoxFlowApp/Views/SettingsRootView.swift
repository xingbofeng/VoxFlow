import AppKit
import SwiftUI

private enum ShortcutBinding: Equatable {
    case voice(VoiceAction)
    case workflow(HotKeyWorkflowShortcut)
}

enum SettingsShortcutRecorder {
    static func encodedShortcutKeyCode(
        eventType: NSEvent.EventType,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        allowsPureModifierShortcut: Bool
    ) -> Int64? {
        if eventType == .flagsChanged, !allowsPureModifierShortcut {
            return nil
        }
        return ShortcutManager.encodeShortcut(
            keyCode: Int64(keyCode),
            modifierMask: ShortcutManager.modifierMask(
                command: modifierFlags.contains(.command),
                shift: modifierFlags.contains(.shift),
                option: modifierFlags.contains(.option),
                control: modifierFlags.contains(.control)
            )
        )
    }
}

struct SettingsRootView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var llmProviderViewModel: LLMProviderViewModel
    @ObservedObject var asrProviderViewModel: ASRProviderViewModel
    let onCheckForUpdates: () -> Void
    @StateObject private var ttsCapabilityModelViewModel = CapabilityModelViewModel(kind: .tts)
    @StateObject private var translationCapabilityModelViewModel = CapabilityModelViewModel(kind: .translation)
    @State private var recordingShortcutBinding: ShortcutBinding?
    @State private var shortcutMonitor: Any?
    @State private var importedJSON = ""
    @State private var newAgentAlias = ""
    @State private var aliasTargetAgentID = ""
    @State private var showDeleteAllLocalModelsConfirmation = false
    @State private var showAgentCLIRegistrationConfirmation = false
    @State private var showAgentCLIUnregistrationConfirmation = false
    @AppStorage(RepositoryBackedLLMRefiner.enabledDefaultsKey) private var llmCorrectionEnabled = false
    @AppStorage(ContextBoostSettings.enabledDefaultsKey) private var contextBoostEnabled = ContextBoostSettings.defaultEnabled

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
            Text("将删除 \(viewModel.localModelStorageDescription()) 的本地语音识别模型文件，并把当前本地识别模型回退到系统自带。")
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
            llmProviderViewModel.loadIfNeeded()
            syncTranslationLLMAvailability()
        }
        .onChange(of: llmProviderViewModel.providers) { _, _ in
            syncTranslationLLMAvailability()
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

    private func syncTranslationLLMAvailability() {
        translationCapabilityModelViewModel.setLLMTranslationAvailable(
            LLMProviderAvailability.hasUsableProvider(in: llmProviderViewModel.providers)
        )
    }

    private var unresolvedBehaviorHelpText: String {
        """
        询问确认：先让你选择目标任务助手
        取消发送：保留文本，不发送给任务助手
        智能排序：按模型置信度排序候选
        默认发送：直接写入当前输入框
        """
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            sidebarGroupTitle("应用设置")

            settingsSidebarButton(.general)
            settingsSidebarButton(.vibeCoding)
            settingsSidebarButton(.selectionActions)
            settingsSidebarButton(.system)

            sidebarGroupTitle("模型配置")
                .padding(.top, 16)

            settingsSidebarButton(.dictationModels)
            settingsSidebarButton(.correctionModels)
            settingsSidebarButton(.ttsModels)
            settingsSidebarButton(.translationModels)

            sidebarGroupTitle("数据与隐私")
                .padding(.top, 16)

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
        case .selectionActions:
            selectionActionsSection
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
            title: "语音识别",
            subtitle: "选择语音识别方式和本地模型大小",
            systemImage: "waveform",
            tint: AppTheme.ColorToken.accent
        ) {
            ASRProviderView(viewModel: asrProviderViewModel, embedded: true)
        }
    }

    private var correctionModelsSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroupCard(
                title: "纠错与上下文",
                subtitle: "配置用于纠错、翻译和总结的智能模型服务",
                systemImage: "sparkles",
                tint: .blue
            ) {
                SettingsToggleRow(
                    title: "启用 AI 纠错",
                    subtitle: "听写完成后，使用默认智能模型润色文本",
                    systemImage: "sparkles",
                    tint: .blue,
                    isOn: $llmCorrectionEnabled
                )
                SettingsToggleRow(
                    title: "当前窗口图片文字识别上下文增强",
                    subtitle: "仅将当前窗口提取的前 K 条候选词临时加入模型纠错提示词",
                    systemImage: "text.viewfinder",
                    tint: .indigo,
                    isOn: $contextBoostEnabled
                )
                LLMProviderView(viewModel: llmProviderViewModel, embedded: true)
            }

            SettingsGroupCard(
                title: "易错词修正",
                subtitle: "控制本地确定性替换和自动学习策略",
                systemImage: "text.badge.checkmark",
                tint: AppTheme.ColorToken.accent
            ) {
                SettingsToggleRow(
                    title: "启用易错词修正",
                    subtitle: "在 AI 优化后、插入前应用本地规则",
                    systemImage: "checkmark.shield",
                    tint: AppTheme.ColorToken.accent,
                    isOn: voiceCorrectionEnabledBinding
                )
                SettingsToggleRow(
                    title: "自动学习候选词",
                    subtitle: "插入后观察同一个输入框的手动修改，提取高置信替换",
                    systemImage: "sparkle.magnifyingglass",
                    tint: .orange,
                    isOn: voiceCorrectionAutoLearningBinding
                )
                SettingsToggleRow(
                    title: "自动学习直接生效",
                    subtitle: "关闭后，学习结果先进入易错词页的候选规则",
                    systemImage: "bolt.badge.checkmark",
                    tint: .green,
                    isOn: voiceCorrectionAutoLearningImmediateBinding
                )
                SettingsToggleRow(
                    title: "影子模式",
                    subtitle: "只记录会命中的规则，不真正修改输入文本",
                    systemImage: "shield.lefthalf.filled",
                    tint: .orange,
                    isOn: voiceCorrectionShadowModeBinding
                )
            }
        }
    }

    private var ttsModelsSection: some View {
        SettingsGroupCard(
            title: "朗读",
            subtitle: "选择原文与译文朗读使用的本地语音模型",
            systemImage: "speaker.wave.2",
            tint: .green
        ) {
            CapabilityModelView(viewModel: ttsCapabilityModelViewModel)
        }
    }

    private var translationModelsSection: some View {
        SettingsGroupCard(
            title: "翻译",
            subtitle: "选择截图文字识别与翻译使用的本地模型和后备路径",
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
                VStack(alignment: .leading, spacing: 12) {
                    shortcutGroupHeader(
                        title: "语音快捷键",
                        subtitle: "控制语音输入与AI 编程的全局入口"
                    )

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
                        title: "任务助手",
                        subtitle: "结合当前窗口上下文与口述生成文本，完成后直接写入当前输入框",
                        buttonTitle: "设置快捷键",
                        badge: "不自动发送",
                        prominentWhenUnbound: true
                    )

                    Divider()
                        .padding(.leading, 70)

                    SettingsToggleRow(
                        title: "鼠标中键录音",
                        subtitle: "点击鼠标中键开始录音，再次点击结束并输入",
                        systemImage: "computermouse",
                        tint: .blue,
                        isOn: middleMouseRecordingBinding
                    )

                    Divider()
                        .padding(.leading, 2)

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
                        Text(viewModel.shortcutConflict ? "当前快捷键冲突，请为两个动作设置不同按键。" : "仅影响语音快捷键的短按/长按行为")
                            .font(.system(size: 12))
                            .foregroundStyle(viewModel.shortcutConflict ? Color.red : AppTheme.ColorToken.secondaryText)
                    }
                    .padding(12)
                    .background(AppTheme.ColorToken.panelBackground.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))

                    Divider()
                        .padding(.leading, 2)

                    shortcutGroupHeader(
                        title: "工作流快捷键",
                        subtitle: "图片文字识别相关操作可单独改键，清空后不会响应快捷键"
                    )

                    workflowShortcutRow(
                        shortcut: .palette,
                        title: "启动台",
                        subtitle: "打开 VoxFlow Palette，搜索最近资产与命令",
                        systemImage: "rectangle.grid.1x2",
                        tint: .teal
                    )

                    Divider()
                        .padding(.leading, 70)

                    workflowShortcutRow(
                        shortcut: .clipboardImageOCR,
                        title: "剪贴板图片文字识别",
                        subtitle: "识别剪贴板图片文字并粘贴到当前输入位置",
                        systemImage: "doc.viewfinder",
                        tint: .indigo
                    )

                    Divider()
                        .padding(.leading, 70)

                    workflowShortcutRow(
                        shortcut: .screenshotOCR,
                        title: "截图文字识别",
                        subtitle: "框选截图后识别、翻译或总结文字",
                        systemImage: "text.viewfinder",
                        tint: .orange
                    )

                    Divider()
                        .padding(.leading, 70)

                    shortcutGroupHeader(
                        title: "划词动作快捷键",
                        subtitle: "选中文本后打开动作 HUD，或直接翻译、总结、发给任务助手"
                    )

                    workflowShortcutRow(
                        shortcut: .selectionAction,
                        title: "划词动作",
                        subtitle: "选中文本后按快捷键打开动作卡",
                        systemImage: "text.cursor",
                        tint: .teal
                    )

                    Divider()
                        .padding(.leading, 70)

                    workflowShortcutRow(
                        shortcut: .selectionTranslate,
                        title: "直接翻译",
                        subtitle: "选中文本后按快捷键直接打开翻译结果",
                        systemImage: "translate",
                        tint: .teal
                    )

                    Divider()
                        .padding(.leading, 70)

                    workflowShortcutRow(
                        shortcut: .selectionSummarize,
                        title: "直接总结",
                        subtitle: "选中文本后按快捷键直接生成总结",
                        systemImage: "text.alignleft",
                        tint: .orange
                    )

                    Divider()
                        .padding(.leading, 70)

                    workflowShortcutRow(
                        shortcut: .selectionAgent,
                        title: "直接发给任务助手",
                        subtitle: "选中文本后按快捷键直接交给任务助手",
                        systemImage: "terminal",
                        tint: AppTheme.ColorToken.accent
                    )
                }
            }

            appUpdateCard
        }
    }

    private var appUpdateCard: some View {
        SettingsGroupCard(
            title: "应用更新",
            subtitle: "查看当前版本并手动检查新版本",
            systemImage: "arrow.down.circle",
            tint: .green
        ) {
            HStack(spacing: 14) {
                SettingsRowIcon(systemImage: "app.badge", tint: .green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前版本")
                        .font(.system(size: 15, weight: .semibold))
                    Text("VoxFlow v\(AppVersionInfo.current().displayText)")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                Spacer(minLength: 12)
                Button("检查更新") {
                    onCheckForUpdates()
                }
                .buttonStyle(.borderedProminent)
            }
            .settingsRow()
        }
    }

    private var vibeCodingSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroupCard(
                title: "AI 编程控制台",
                subtitle: "用语音把指令发给正在工作的终端助手",
                systemImage: "terminal",
                tint: AppTheme.ColorToken.accent
            ) {
                SettingsToggleRow(
                    title: "启用AI 编程控制台",
                    subtitle: "开启后，现有语音输入快捷键会进入AI 编程控制台",
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
                            Text("在 Ghostty、iTerm2 或 Terminal 中用以下命令启动任务助手")
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
                    subtitle: "命中明确的任务助手名称或别名时，不调用模型、无需二次确认",
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
                        Text("未识别任务助手名称")
                            .font(.system(size: 15, weight: .semibold))
                        Text("低置信结果按所选方式处理")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        Picker("未识别任务助手名称", selection: Binding(
                            get: { viewModel.agentDispatchUnresolvedBehavior },
                            set: { value in perform { try viewModel.setAgentDispatchUnresolvedBehavior(value) } }
                        )) {
                            Text("询问确认").tag("confirm")
                            Text("取消发送").tag("cancel")
                            Text("智能判断").tag("model")
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
                    title: "协作通道状态上报",
                    subtitle: "不使用心跳，仅在任务变化时低频同步任务助手摘要与会话引用",
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

    private var selectionActionsSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroupCard(
                title: "划词动作",
                subtitle: "选中文本后翻译、总结或交给任务助手",
                systemImage: "text.cursor",
                tint: .teal
            ) {
                selectionActionCapabilityRow(
                    title: "手动唤起",
                    subtitle: "第一期不会自动弹出动作卡，避免打扰现有阅读和输入流程",
                    systemImage: "hand.tap",
                    tint: .teal
                )
            }

            SettingsGroupCard(
                title: "动作卡",
                subtitle: "保持轻量，只显示第一期三个动作",
                systemImage: "rectangle.3.group",
                tint: .teal
            ) {
                selectionActionCapabilityRow(
                    title: "翻译",
                    subtitle: "自动翻译或润色选中文本",
                    systemImage: "translate",
                    tint: .teal
                )
                selectionActionCapabilityRow(
                    title: "总结",
                    subtitle: "把长段文本压缩成简洁要点",
                    systemImage: "text.alignleft",
                    tint: .orange
                )
                selectionActionCapabilityRow(
                    title: "任务助手",
                    subtitle: "把选中文本作为上下文交给现有任务助手 HUD",
                    systemImage: "terminal",
                    tint: AppTheme.ColorToken.accent
                )
            }

            SettingsGroupCard(
                title: "结果面板",
                subtitle: "复用截图结果卡的文本操作体验",
                systemImage: "rectangle.and.text.magnifyingglass",
                tint: .indigo
            ) {
                selectionActionCapabilityRow(
                    title: "流式结果",
                    subtitle: "长文本翻译和总结会逐步显示已生成内容",
                    systemImage: "text.line.first.and.arrowtriangle.forward",
                    tint: .indigo
                )
                selectionActionCapabilityRow(
                    title: "写回与复制",
                    subtitle: "支持复制、替换原文、插入下一行；写入失败时自动复制",
                    systemImage: "doc.on.doc",
                    tint: .green
                )
                selectionActionCapabilityRow(
                    title: "朗读",
                    subtitle: "朗读原文、译文或总结结果",
                    systemImage: "speaker.wave.2",
                    tint: .blue
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
                systemToggle(.clipboardImageOCR, "剪贴板图片文字识别", "剪贴板里是图片时，Command+Shift+V 先识别图片文字再粘贴", "doc.viewfinder", tint: .indigo)
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
                    subtitle: "用于“任务助手”的当前窗口文字识别，上下文截图不会保存",
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
                    "AI 诊断采集",
                    "默认关闭；开启后单独保存原始调用内容，保留 7 天且最多 100 份",
                    "doc.text.magnifyingglass",
                    tint: .orange
                )
                Button("立即删除 AI 诊断内容", role: .destructive) {
                    viewModel.clearLLMTraceDiagnostics()
                }
                .buttonStyle(.bordered)

                Text("AI 诊断文件不会写入主数据库或自动上传。关闭 AI 诊断采集会立即删除全部诊断文件。")
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

    private func sidebarGroupTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.ColorToken.secondaryText)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
    }

    private var selectedInputDeviceName: String {
        viewModel.inputDevices.first(where: { $0.id == viewModel.selectedInputDeviceID })?.name
            ?? "系统默认麦克风"
    }

    private var selectedRecognitionLanguageName: String {
        viewModel.selectedRecognitionLanguage.displayName
    }

    private func shortcutKeyIcon(for action: VoiceAction) -> String {
        guard let keyCode = shortcutKeyCode(for: action) else {
            return action.systemImage
        }
        return KeyCodeMapping.iconName(for: keyCode)
    }

    private func shortcutKeyIcon(
        for workflowShortcut: HotKeyWorkflowShortcut,
        fallback: String
    ) -> String {
        guard let keyCode = shortcutKeyCode(for: workflowShortcut) else {
            return fallback
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

    private func shortcutKeyCode(for workflowShortcut: HotKeyWorkflowShortcut) -> Int64? {
        switch workflowShortcut {
        case .palette:
            return viewModel.paletteShortcutKeyCode
        case .clipboardImageOCR:
            return viewModel.clipboardImageOCRShortcutKeyCode
        case .screenshotOCR:
            return viewModel.screenshotOCRShortcutKeyCode
        case .selectionAction:
            return viewModel.selectionActionShortcutKeyCode
        case .selectionTranslate:
            return viewModel.selectionTranslateShortcutKeyCode
        case .selectionSummarize:
            return viewModel.selectionSummarizeShortcutKeyCode
        case .selectionAgent:
            return viewModel.selectionAgentShortcutKeyCode
        case .cancel:
            return HotKeyShortcutRouting.escapeKeyCode
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

    private var middleMouseRecordingBinding: Binding<Bool> {
        Binding(
            get: { viewModel.middleMouseRecordingEnabled },
            set: { value in perform { try viewModel.setMiddleMouseRecordingEnabled(value) } }
        )
    }

    private var voiceCorrectionEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.voiceCorrectionEnabled },
            set: { value in perform { try viewModel.setVoiceCorrectionEnabled(value) } }
        )
    }

    private var voiceCorrectionAutoLearningBinding: Binding<Bool> {
        Binding(
            get: { viewModel.voiceCorrectionAutoLearningEnabled },
            set: { value in perform { try viewModel.setVoiceCorrectionAutoLearningEnabled(value) } }
        )
    }

    private var voiceCorrectionAutoLearningImmediateBinding: Binding<Bool> {
        Binding(
            get: { viewModel.voiceCorrectionAutoLearningAppliesImmediately },
            set: { value in perform { try viewModel.setVoiceCorrectionAutoLearningAppliesImmediately(value) } }
        )
    }

    private var voiceCorrectionShadowModeBinding: Binding<Bool> {
        Binding(
            get: { viewModel.voiceCorrectionShadowMode },
            set: { value in perform { try viewModel.setVoiceCorrectionShadowMode(value) } }
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
        let binding = ShortcutBinding.voice(action)
        let isRecording = recordingShortcutBinding == binding
        let keyCode = shortcutKeyCode(for: action)
        let isUnbound = keyCode == nil
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
            }
            Spacer(minLength: 16)
            ShortcutKeycapsView(
                keyCode: keyCode,
                isRecording: isRecording,
                recordingTitle: "按下新快捷键"
            )
            shortcutActionButton(
                title: isRecording ? "取消" : buttonTitle,
                prominent: prominentWhenUnbound && isUnbound,
                binding: binding
            )
        }
        .settingsRow()
    }

    private func workflowShortcutRow(
        shortcut: HotKeyWorkflowShortcut,
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        let binding = ShortcutBinding.workflow(shortcut)
        let isRecording = recordingShortcutBinding == binding
        let keyCode = shortcutKeyCode(for: shortcut)
        let isUnbound = keyCode == nil
        return HStack(spacing: 14) {
            SettingsRowIcon(
                systemImage: shortcutKeyIcon(for: shortcut, fallback: systemImage),
                tint: tint
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer(minLength: 16)
            ShortcutKeycapsView(
                keyCode: keyCode,
                isRecording: isRecording,
                recordingTitle: "按下新快捷键"
            )
            if !isUnbound {
                Button {
                    perform { try viewModel.updateWorkflowShortcut(shortcut, keyCode: nil) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .background(AppTheme.ColorToken.panelBackground.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .help("清空快捷键")
            }
            shortcutActionButton(
                title: isRecording ? "取消" : "修改",
                prominent: isUnbound,
                binding: binding
            )
        }
        .settingsRow()
    }

    private func selectionActionCapabilityRow(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 14) {
            SettingsRowIcon(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
        }
        .settingsRow()
    }

    private func shortcutGroupHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func shortcutActionButton(title: String, prominent: Bool, binding: ShortcutBinding) -> some View {
        if prominent {
            Button(title) {
                toggleShortcutRecording(for: binding)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(title) {
                toggleShortcutRecording(for: binding)
            }
            .buttonStyle(.bordered)
        }
    }

    private func toggleShortcutRecording(for binding: ShortcutBinding = .voice(.dictation)) {
        if recordingShortcutBinding == binding {
            stopShortcutRecording()
            return
        }
        recordingShortcutBinding = binding
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
        recordingShortcutBinding = nil
        ShortcutCaptureState.shared.isCapturing = false
    }

    private func recordShortcut(from event: NSEvent) {
        let binding = recordingShortcutBinding ?? .voice(.dictation)
        let allowsPureModifierShortcut: Bool
        switch binding {
        case .voice:
            allowsPureModifierShortcut = true
        case .workflow:
            allowsPureModifierShortcut = false
        }
        guard let keyCode = SettingsShortcutRecorder.encodedShortcutKeyCode(
            eventType: event.type,
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            allowsPureModifierShortcut: allowsPureModifierShortcut
        ) else {
            return
        }
        guard keyCode > 0 else {
            viewModel.report(error: SettingsViewModelError.invalidShortcutKeyCode)
            stopShortcutRecording()
            return
        }
        perform {
            switch binding {
            case let .voice(action):
                try viewModel.updateActionShortcut(action: action, keyCode: keyCode)
            case let .workflow(shortcut):
                try viewModel.updateWorkflowShortcut(shortcut, keyCode: keyCode)
            }
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

private struct ShortcutKeycapsView: View {
    let keyCode: Int64?
    let isRecording: Bool
    let recordingTitle: String

    var body: some View {
        if isRecording {
            HStack(spacing: 6) {
                Image(systemName: "record.circle")
                    .font(.system(size: 12, weight: .semibold))
                Text(recordingTitle)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(AppTheme.ColorToken.accent)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(AppTheme.ColorToken.selectionBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.ColorToken.selectionBorder, lineWidth: AppTheme.Border.panelLineWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if let keyCode {
            HStack(spacing: 4) {
                ForEach(KeyCodeMapping.keycapLabels(for: keyCode), id: \.self) { label in
                    ShortcutKeycap(label: label)
                }
            }
            .accessibilityLabel(KeyCodeMapping.displayName(for: keyCode))
        } else {
            Text("未设置")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(AppTheme.ColorToken.panelBackground.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct ShortcutKeycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(AppTheme.ColorToken.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .frame(minWidth: 28)
            .frame(height: 28)
            .background(AppTheme.ColorToken.panelBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
        case .vibeCoding: return "AI 编程"
        case .selectionActions: return "划词动作"
        case .dictationModels: return "语音识别"
        case .correctionModels: return "纠错与上下文"
        case .ttsModels: return "朗读"
        case .translationModels: return "翻译"
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
