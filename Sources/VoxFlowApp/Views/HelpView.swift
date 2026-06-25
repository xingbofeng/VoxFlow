import SwiftUI

enum HelpExternalLinks {
    static let projectHomepage = "https://xingbofeng.github.io/VoxFlow/"
    static let githubRepository = "https://github.com/xingbofeng/VoxFlow"
    static let latestRelease = "https://github.com/xingbofeng/VoxFlow/releases/latest"
    static let issues = "https://github.com/xingbofeng/VoxFlow/issues"
    static let privacy = "https://github.com/xingbofeng/VoxFlow/blob/main/docs/PRIVACY.md"
}

struct HelpView: View {
    let versionInfo: AppVersionInfo
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var asrProviderViewModel: ASRProviderViewModel
    let onOpenPermissions: () -> Void
    let onCheckForUpdates: () -> Void
    @State private var showingWeChatQRCode = false

    init(
        versionInfo: AppVersionInfo = .current(),
        settingsViewModel: SettingsViewModel,
        asrProviderViewModel: ASRProviderViewModel,
        onOpenPermissions: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void
    ) {
        self.versionInfo = versionInfo
        self.settingsViewModel = settingsViewModel
        self.asrProviderViewModel = asrProviderViewModel
        self.onOpenPermissions = onOpenPermissions
        self.onCheckForUpdates = onCheckForUpdates
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
                        title: "命令面板",
                        subtitle: "搜索应用、命令和最近资产",
                        systemImage: "command.square",
                        tint: AppTheme.ColorToken.accent
                    )
                    HelpFeatureCard(
                        title: "截图 OCR",
                        subtitle: "框选截图并识别文字",
                        systemImage: "text.viewfinder",
                        tint: AppTheme.ColorToken.accent
                    )
                    HelpFeatureCard(
                        title: "AI 编程",
                        subtitle: "语音触发终端助手工作流",
                        systemImage: "terminal",
                        tint: AppTheme.ColorToken.accent
                    )
                    HelpFeatureCard(
                        title: "文件转写与笔记",
                        subtitle: "导入音频文件，沉淀语音笔记",
                        systemImage: "waveform.path.badge.plus",
                        tint: AppTheme.ColorToken.accent
                    )
                    HelpFeatureCard(
                        title: "易错词",
                        subtitle: "维护本地热词和纠错规则",
                        systemImage: "text.badge.checkmark",
                        tint: AppTheme.ColorToken.accent
                    )
                    HelpFeatureCard(
                        title: "安全回退",
                        subtitle: "识别、修正或生成失败时保留原始文本",
                        systemImage: "arrow.uturn.backward.circle",
                        tint: AppTheme.ColorToken.accent
                    )
                    HelpFeatureCard(
                        title: "本地隐私",
                        subtitle: "访问密钥仅保存在系统 Keychain",
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
                        subtitle: "打开产品落地页和使用介绍",
                        systemImage: "house",
                        url: HelpExternalLinks.projectHomepage
                    )
                    HelpLinkRow(
                        title: "GitHub",
                        subtitle: "查看源码、文档和开发进度",
                        systemImage: "curlybraces.square",
                        iconStyle: .github,
                        url: HelpExternalLinks.githubRepository
                    )
                    HelpActionRow(
                        title: "添加作者微信交流",
                        subtitle: "扫码添加作者微信",
                        systemImage: "qrcode.viewfinder"
                    ) {
                        showingWeChatQRCode = true
                    }
                    HelpActionRow(
                        title: "检查更新",
                        subtitle: "立即检查是否有可用新版本",
                        systemImage: "arrow.triangle.2.circlepath"
                    ) {
                        onCheckForUpdates()
                    }
                    HelpLinkRow(
                        title: "版本发布",
                        subtitle: "下载最新稳定版本",
                        systemImage: "shippingbox",
                        url: HelpExternalLinks.latestRelease
                    )
                    HelpLinkRow(
                        title: "问题反馈",
                        subtitle: "报告问题或提出建议",
                        systemImage: "bubble.left.and.exclamationmark.bubble.right",
                        url: HelpExternalLinks.issues
                    )
                    HelpLinkRow(
                        title: "隐私说明",
                        subtitle: "了解本地数据和网络请求规则",
                        systemImage: "hand.raised",
                        url: HelpExternalLinks.privacy
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
                        subtitle: "Apple 语音识别的系统状态",
                        systemImage: "waveform",
                        status: settingsViewModel.speechPermission.title,
                        satisfied: settingsViewModel.speechPermission == .granted
                    )
                    HelpPermissionRow(
                        title: "屏幕录制",
                        subtitle: "用于当前窗口文字识别，不保存截图",
                        systemImage: "rectangle.inset.filled.and.person.filled",
                        status: PermissionSummary.statusText(settingsViewModel.screenRecordingGranted),
                        satisfied: settingsViewModel.screenRecordingGranted
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
            settingsViewModel.loadIfNeeded()
            asrProviderViewModel.loadIfNeeded()
        }
        .overlay {
            if showingWeChatQRCode {
                WeChatQRCodeOverlay {
                    showingWeChatQRCode = false
                }
                .transition(.opacity)
            }
        }
    }

    private var shortcutDisplayName: String {
        let keyboardShortcut = KeyCodeMapping.displayName(for: settingsViewModel.shortcutKeyCode)
        guard settingsViewModel.middleMouseRecordingEnabled else {
            return keyboardShortcut
        }
        return "\(keyboardShortcut) / 鼠标中键"
    }

    private var shortcutIconName: String {
        KeyCodeMapping.iconName(for: settingsViewModel.shortcutKeyCode)
    }

    private var shortcutSubtitle: String {
        if settingsViewModel.middleMouseRecordingEnabled {
            switch settingsViewModel.shortPressBehavior {
            case .toggleListening:
                return "快捷键短按切换；中键点击开始，再次点击结束"
            case .none:
                return "快捷键按住说话；中键点击开始，再次点击结束"
            }
        } else {
            switch settingsViewModel.shortPressBehavior {
            case .toggleListening:
                return "短按切换，长按按住说话"
            case .none:
                return "按住说话，松手输入"
            }
        }
    }

}

private struct WeChatQRCodeOverlay: View {
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Button(action: dismiss) {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("添加作者微信交流")
                            .font(.system(size: 18, weight: .semibold))
                        Text("扫码添加作者微信，反馈问题或交流使用体验。")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    }
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .appControlSurface(cornerRadius: 8)
                }

                if let image = WeChatQRCodeImage.load() {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 320, height: 408)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: 1)
                        )
                } else {
                    ContentUnavailableView(
                        "二维码加载失败",
                        systemImage: "qrcode",
                        description: Text("请确认资源已打包到 App。")
                    )
                    .frame(width: 320, height: 240)
                }
            }
            .padding(22)
            .frame(width: 380)
            .background(AppTheme.ColorToken.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
            .contentShape(Rectangle())
            .onTapGesture {}
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand(perform: dismiss)
    }
}

private enum WeChatQRCodeImage {
    static func load() -> NSImage? {
        guard let url = VoxFlowAppResourceBundle.url(
            forResource: "AuthorWeChatQRCode",
            withExtension: "jpg"
        ) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

private struct HelpFeatureCard: View {
    private static let cardHeight: CGFloat = 132

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
                .lineLimit(2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: Self.cardHeight, alignment: .topLeading)
        .frame(height: Self.cardHeight)
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
    var iconStyle: HelpRowIconStyle = .system
    let url: String
    @State private var isHovered = false

    var body: some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack(spacing: 13) {
                    HelpRowIcon(systemImage: systemImage, style: iconStyle)
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

private enum HelpRowIconStyle {
    case system
    case github
}

private struct HelpRowIcon: View {
    let systemImage: String
    let style: HelpRowIconStyle

    var body: some View {
        Group {
            switch style {
            case .system:
                Image(systemName: systemImage)
                    .foregroundStyle(AppTheme.ColorToken.accent)
            case .github:
                if let image = GitHubMarkImage.load() {
                    Image(nsImage: image)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(AppTheme.ColorToken.accent)
                } else {
                    Image(systemName: systemImage)
                        .foregroundStyle(AppTheme.ColorToken.accent)
                }
            }
        }
        .frame(width: 24)
    }
}

enum GitHubMarkImage {
    static func load() -> NSImage? {
        guard let url = VoxFlowAppResourceBundle.url(forResource: "GitHubMark", withExtension: "png") else {
            return nil
        }
        guard let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        return image
    }
}

private struct HelpActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
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
                Image(systemName: "qrcode")
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
