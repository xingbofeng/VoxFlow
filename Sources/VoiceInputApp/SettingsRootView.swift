import AppKit
import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var llmProviderViewModel: LLMProviderViewModel
    @ObservedObject var asrProviderViewModel: ASRProviderViewModel
    @State private var isRecordingShortcut = false
    @State private var shortcutMonitor: Any?
    @State private var importedJSON = ""
    @AppStorage(RepositoryBackedLLMRefiner.enabledDefaultsKey) private var llmCorrectionEnabled = false

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(viewModel.selectedSection.pageTitle)
                        .font(.system(size: 30, weight: .bold))
                    ActionFeedbackView(
                        message: viewModel.lastActionMessage,
                        error: viewModel.lastError,
                        onDismiss: viewModel.clearFeedback
                    )
                    sectionContent
                }
                .padding(30)
                .frame(maxWidth: 1_080, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .background(AppTheme.ColorToken.pageBackground)
        .tint(AppTheme.ColorToken.accent)
        .onAppear {
            viewModel.load()
        }
        .onDisappear {
            stopShortcutRecording()
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("应用设置")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            settingsSidebarButton(.general)
            settingsSidebarButton(.models)
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
        case .models:
            modelsSection
        case .system:
            systemSection
        case .dataPrivacy:
            dataPrivacySection
        }
    }

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroupCard(
                title: "OpenAI 兼容模型",
                subtitle: "配置用于文本修正的全局模型",
                systemImage: "network",
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
            SettingsGroupCard(
                title: "听写模型",
                subtitle: "选择语音识别方式和本地模型大小",
                systemImage: "waveform",
                tint: AppTheme.ColorToken.accent
            ) {
                ASRProviderView(viewModel: asrProviderViewModel, embedded: true)
            }
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroupCard(
                title: "输入设备",
                subtitle: "选择用于语音输入的麦克风",
                systemImage: "mic",
                tint: .orange
            ) {
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
                            Text(selectedInputDeviceName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppTheme.ColorToken.primaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(selectedInputDeviceName)
                            Text("点击更换输入设备")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    }
                    .settingsRow()
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
            }

            SettingsGroupCard(
                title: "快捷键",
                subtitle: "自定义全局快捷键和触发行为",
                systemImage: "keyboard",
                tint: .purple
            ) {
                VStack(spacing: 12) {
                    HStack(spacing: 14) {
                        SettingsRowIcon(systemImage: shortcutKeyIcon, tint: AppTheme.ColorToken.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("录制快捷键")
                                .font(.system(size: 15, weight: .semibold))
                            Text(isRecordingShortcut ? "按下想用于听写的按键" : "当前：\(shortcutDisplayName)")
                                .font(.system(size: 12))
                                .foregroundStyle(isRecordingShortcut ? AppTheme.ColorToken.accent : AppTheme.ColorToken.secondaryText)
                        }
                        Spacer()
                        Button(isRecordingShortcut ? "正在录制..." : "录制") {
                            toggleShortcutRecording()
                        }
                        .buttonStyle(.bordered)
                    }
                    .settingsRow()

                    HStack(spacing: 14) {
                        SettingsRowIcon(systemImage: "switch.2", tint: .green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("短按行为")
                                .font(.system(size: 15, weight: .semibold))
                            Text(shortPressBehaviorDescription)
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        }
                        Spacer()
                        Toggle("", isOn: shortPressToggleBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .settingsRow()
                }
            }
        }
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
            }

            SettingsGroupCard(
                title: "启动与外观",
                subtitle: "自定义应用启动行为和状态显示",
                systemImage: "paintpalette",
                tint: .pink
            ) {
                systemToggle(.darkMode, "深色模式", "使用深色配色方案显示应用界面", "moon", tint: .pink)
                systemToggle(.launchAtLogin, "开机自动启动", "登录系统时自动启动 VoiceInput", "power", tint: .pink)
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
                    subtitle: "系统自带模型需要此权限",
                    systemImage: "waveform",
                    status: speechPermissionTitle,
                    granted: speechPermissionSatisfied,
                    pane: .speech
                )

                VStack(alignment: .leading, spacing: 6) {
                    Label("权限信息", systemImage: "info.circle")
                        .font(.system(size: 13, weight: .semibold))
                    Text("如果文本输入失败，请检查辅助功能权限。切换到本地听写模型时，不需要 Apple 语音识别权限。")
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
            }

            SettingsGroupCard(
                title: "数据管理",
                subtitle: "导出、导入或清理本地数据",
                systemImage: "externaldrive",
                tint: .orange
            ) {
                HStack(spacing: 10) {
                    Button("导出数据") { perform { _ = try viewModel.exportDataJSON() } }
                    Button("清空历史", role: .destructive) { perform { try viewModel.clearHistory() } }
                    Button("清空缓存", role: .destructive) { perform { try viewModel.clearCache() } }
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

                Text("诊断信息仅保存在本机 Application Support/VoiceInput。VoiceInput 不会自动上传音频、转录文本或崩溃日志。")
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

    private var shortcutDisplayName: String {
        KeyCodeMapping.displayName(for: viewModel.shortcutKeyCode)
    }

    private var shortcutKeyIcon: String {
        KeyCodeMapping.iconName(for: viewModel.shortcutKeyCode)
    }

    private var shortPressBehaviorDescription: String {
        switch viewModel.shortPressBehavior {
        case .toggleListening:
            return "短按切换听写：按一次开始，再按一次停止"
        case .none:
            return "短按不触发：仅长按录音，松开完成"
        }
    }

    private var isLocalASRDefault: Bool {
        asrProviderViewModel.providers.contains {
            $0.id == ASRProviderID.qwen3 && $0.isDefault
        }
    }

    private var speechPermissionSatisfied: Bool {
        isLocalASRDefault || viewModel.speechPermission == .granted
    }

    private var speechPermissionTitle: String {
        isLocalASRDefault ? "当前模型不需要" : viewModel.speechPermission.title
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

    private func toggleShortcutRecording() {
        if isRecordingShortcut {
            stopShortcutRecording()
            return
        }
        isRecordingShortcut = true
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
        isRecordingShortcut = false
    }

    private func recordShortcut(from event: NSEvent) {
        let keyCode = Int64(event.keyCode)
        guard keyCode > 0 else {
            viewModel.report(error: SettingsViewModelError.invalidShortcutKeyCode)
            stopShortcutRecording()
            return
        }
        perform {
            try viewModel.updateShortcut(
                keyCode: keyCode,
                longPressThreshold: viewModel.longPressThreshold,
                shortPressBehavior: viewModel.shortPressBehavior
            )
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

private extension View {
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
        case .models: return "模型"
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
