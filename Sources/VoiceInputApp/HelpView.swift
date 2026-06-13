import SwiftUI

struct HelpView: View {
    let versionInfo: AppVersionInfo
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var asrProviderViewModel: ASRProviderViewModel
    let onOpenPermissions: () -> Void

    init(
        versionInfo: AppVersionInfo = .current(),
        settingsViewModel: SettingsViewModel,
        asrProviderViewModel: ASRProviderViewModel,
        onOpenPermissions: @escaping () -> Void
    ) {
        self.versionInfo = versionInfo
        self.settingsViewModel = settingsViewModel
        self.asrProviderViewModel = asrProviderViewModel
        self.onOpenPermissions = onOpenPermissions
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("帮助")
                            .font(.system(size: 30, weight: .bold))
                        Text("使用指南、常用入口和权限诊断")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    }
                    Spacer()
                    Text("v\(versionInfo.displayText)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.ColorToken.accent)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(AppTheme.ColorToken.selectionBackground)
                        .clipShape(Capsule())
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: 12)],
                    spacing: 12
                ) {
                    HelpFeatureCard(
                        title: shortcutDisplayName,
                        subtitle: shortcutSubtitle,
                        systemImage: shortcutIconName,
                        tint: AppTheme.ColorToken.accent
                    )
                    HelpFeatureCard(
                        title: "安全回退",
                        subtitle: "识别或修正失败时保留原始文本",
                        systemImage: "arrow.uturn.backward.circle",
                        tint: AppTheme.ColorToken.accent
                    )
                    HelpFeatureCard(
                        title: "本地隐私",
                        subtitle: "API Key 仅保存在系统 Keychain",
                        systemImage: "lock.shield",
                        tint: AppTheme.ColorToken.accent
                    )
                }

                HelpSectionCard(
                    title: "常用入口",
                    subtitle: "获取更新、提交反馈和查看隐私说明",
                    systemImage: "link",
                    tint: AppTheme.ColorToken.accent
                ) {
                    HelpLinkRow(
                        title: "项目主页",
                        subtitle: "查看功能介绍和使用文档",
                        systemImage: "house",
                        url: "https://github.com/xingbofeng/VoiceInput"
                    )
                    HelpLinkRow(
                        title: "版本发布",
                        subtitle: "下载最新稳定版本",
                        systemImage: "shippingbox",
                        url: "https://github.com/xingbofeng/VoiceInput/releases/latest"
                    )
                    HelpLinkRow(
                        title: "问题反馈",
                        subtitle: "报告问题或提出建议",
                        systemImage: "bubble.left.and.exclamationmark.bubble.right",
                        url: "https://github.com/xingbofeng/VoiceInput/issues"
                    )
                    HelpLinkRow(
                        title: "隐私说明",
                        subtitle: "了解本地数据和网络请求规则",
                        systemImage: "hand.raised",
                        url: "https://github.com/xingbofeng/VoiceInput/blob/main/docs/PRIVACY.md"
                    )
                }

                HelpSectionCard(
                    title: "权限检查",
                    subtitle: "确认听写和文本输入所需的系统权限",
                    systemImage: "checkmark.shield",
                    tint: AppTheme.ColorToken.accent
                ) {
                    HelpPermissionRow(
                        title: "麦克风",
                        subtitle: "用于捕获语音",
                        systemImage: "mic",
                        status: settingsViewModel.microphonePermission.title,
                        satisfied: settingsViewModel.microphonePermission == .granted
                    )
                    HelpPermissionRow(
                        title: "辅助功能",
                        subtitle: "用于向当前应用输入文本",
                        systemImage: "accessibility",
                        status: settingsViewModel.accessibilityGranted ? "已授权" : "未授权",
                        satisfied: settingsViewModel.accessibilityGranted
                    )
                    HelpPermissionRow(
                        title: "语音识别",
                        subtitle: "系统自带模型需要",
                        systemImage: "waveform",
                        status: speechPermissionTitle,
                        satisfied: speechPermissionSatisfied
                    )
                    Button {
                        settingsViewModel.load()
                        onOpenPermissions()
                    } label: {
                        Label("查看完整状态与权限", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(30)
            .frame(maxWidth: 1_080)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.ColorToken.pageBackground)
        .tint(AppTheme.ColorToken.accent)
        .onAppear {
            settingsViewModel.load()
            asrProviderViewModel.load()
        }
    }

    private var shortcutDisplayName: String {
        KeyCodeMapping.displayName(for: settingsViewModel.shortcutKeyCode)
    }

    private var shortcutIconName: String {
        KeyCodeMapping.iconName(for: settingsViewModel.shortcutKeyCode)
    }

    private var shortcutSubtitle: String {
        switch settingsViewModel.shortPressBehavior {
        case .toggleListening:
            return "短按切换，长按按住说话"
        case .none:
            return "按住说话，松手输入"
        }
    }

    private var localModelIsDefault: Bool {
        asrProviderViewModel.providers.contains {
            $0.id == ASRProviderID.qwen3 && $0.isDefault
        }
    }

    private var speechPermissionSatisfied: Bool {
        localModelIsDefault || settingsViewModel.speechPermission == .granted
    }

    private var speechPermissionTitle: String {
        localModelIsDefault ? "当前模型不需要" : settingsViewModel.speechPermission.title
    }
}

private struct HelpFeatureCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.icon))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .appPanel(cornerRadius: 14)
    }
}

private struct HelpSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let content: Content

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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.icon))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
            }
            VStack(spacing: 9) {
                content
            }
        }
        .padding(20)
        .appPanel(cornerRadius: 14)
    }
}

private struct HelpLinkRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let url: String
    @State private var isHovered = false

    var body: some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack(spacing: 13) {
                    Image(systemName: systemImage)
                        .frame(width: 24)
                        .foregroundStyle(AppTheme.ColorToken.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.ColorToken.primaryText)
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 58)
                .background(
                    isHovered
                        ? AppTheme.ColorToken.panelBackground
                        : AppTheme.ColorToken.controlBackground.opacity(0.72)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                        .stroke(isHovered ? AppTheme.ColorToken.subtleStroke : Color.clear)
                )
                .contentShape(Rectangle())
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }
    }
}

private struct HelpPermissionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let status: String
    let satisfied: Bool

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: systemImage)
                .frame(width: 24)
                .foregroundStyle(satisfied ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            Text(status)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(satisfied ? Color.green : Color.orange)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background((satisfied ? Color.green : Color.orange).opacity(0.09))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .background(AppTheme.ColorToken.controlBackground.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
    }
}
