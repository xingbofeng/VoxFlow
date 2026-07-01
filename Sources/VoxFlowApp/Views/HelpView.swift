import SwiftUI

enum HelpExternalLinks {
    static let projectHomepage = "https://mashangxie.app/"
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
    @State private var showingSupportCommunityPanel = false

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
                        Text(L10n.localize("help.page.title", comment: "Help view heading"))
                            .font(.system(size: 30, weight: .bold))
                        Text(L10n.localize("help.page.subtitle", comment: "Help view subtitle"))
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
                        title: L10n.localize("help.cards.command_panel_title", comment: "Help command panel card title"),
                        subtitle: L10n.localize("help.cards.command_panel_subtitle", comment: "Help command panel card subtitle"),
                        systemImage: "command.square",
                        tint: AppTheme.ColorToken.accent
                    )
                    HelpFeatureCard(
                        title: L10n.localize("help.cards.screenshot_ocr_title", comment: "Help screenshot OCR card title"),
                        subtitle: L10n.localize("help.cards.screenshot_ocr_subtitle", comment: "Help screenshot OCR card subtitle"),
                        systemImage: "text.viewfinder",
                        tint: AppTheme.ColorToken.accent
                    )
                    HelpFeatureCard(
                        title: L10n.localize("help.cards.ai_coding_title", comment: "Help AI coding card title"),
                        subtitle: L10n.localize("help.cards.ai_coding_subtitle", comment: "Help AI coding card subtitle"),
                        systemImage: "terminal",
                        tint: AppTheme.ColorToken.accent
                    )
                    HelpFeatureCard(
                        title: L10n.localize("help.cards.transcription_notes_title", comment: "Help transcription notes card title"),
                        subtitle: L10n.localize("help.cards.transcription_notes_subtitle", comment: "Help transcription notes card subtitle"),
                        systemImage: "waveform.path.badge.plus",
                        tint: AppTheme.ColorToken.accent
                    )
                    HelpFeatureCard(
                        title: L10n.localize("help.cards.easy_correction_title", comment: "Help easy correction card title"),
                        subtitle: L10n.localize("help.cards.easy_correction_subtitle", comment: "Help easy correction card subtitle"),
                        systemImage: "text.badge.checkmark",
                        tint: AppTheme.ColorToken.accent
                    )
                    HelpFeatureCard(
                        title: L10n.localize("help.cards.safe_fallback_title", comment: "Help safe fallback card title"),
                        subtitle: L10n.localize("help.cards.safe_fallback_subtitle", comment: "Help safe fallback card subtitle"),
                        systemImage: "arrow.uturn.backward.circle",
                        tint: AppTheme.ColorToken.accent
                    )
                    HelpFeatureCard(
                        title: L10n.localize("help.cards.local_privacy_title", comment: "Help local privacy card title"),
                        subtitle: L10n.localize("help.cards.local_privacy_subtitle", comment: "Help local privacy card subtitle"),
                        systemImage: "lock.shield",
                        tint: AppTheme.ColorToken.accent
                    )
                }

                HelpSectionCard(
                    title: L10n.localize("help.section.quick_links_title", comment: "Quick links section title"),
                    subtitle: L10n.localize("help.section.quick_links_subtitle", comment: "Quick links section subtitle"),
                    systemImage: "link",
                    tint: AppTheme.ColorToken.accent
                ) {
                    HelpLinkRow(
                        title: L10n.localize("help.links.project_homepage_title", comment: "Project homepage quick link title"),
                        subtitle: L10n.localize("help.links.project_homepage_subtitle", comment: "Project homepage quick link subtitle"),
                        systemImage: "house",
                        url: HelpExternalLinks.projectHomepage
                    )
                    HelpLinkRow(
                        title: L10n.localize("help.links.github_title", comment: "GitHub quick link title"),
                        subtitle: L10n.localize("help.links.github_subtitle", comment: "GitHub quick link subtitle"),
                        systemImage: "curlybraces.square",
                        iconStyle: .github,
                        url: HelpExternalLinks.githubRepository
                    )
                    HelpActionRow(
                        title: L10n.localize("help.actions.community_title", comment: "Community support action title"),
                        subtitle: L10n.localize("help.actions.community_subtitle", comment: "Community support action subtitle"),
                        systemImage: "star"
                    ) {
                        showingSupportCommunityPanel = true
                    }
                    HelpActionRow(
                        title: L10n.localize("help.actions.check_updates_title", comment: "Check updates action title"),
                        subtitle: L10n.localize("help.actions.check_updates_subtitle", comment: "Check updates action subtitle"),
                        systemImage: "arrow.triangle.2.circlepath"
                    ) {
                        onCheckForUpdates()
                    }
                    HelpLinkRow(
                        title: L10n.localize("help.links.release_title", comment: "Release notes quick link title"),
                        subtitle: L10n.localize("help.links.release_subtitle", comment: "Release notes quick link subtitle"),
                        systemImage: "shippingbox",
                        url: HelpExternalLinks.latestRelease
                    )
                    HelpLinkRow(
                        title: L10n.localize("help.links.feedback_title", comment: "Issue feedback quick link title"),
                        subtitle: L10n.localize("help.links.feedback_subtitle", comment: "Issue feedback quick link subtitle"),
                        systemImage: "bubble.left.and.exclamationmark.bubble.right",
                        url: HelpExternalLinks.issues
                    )
                    HelpLinkRow(
                        title: L10n.localize("help.links.privacy_title", comment: "Privacy quick link title"),
                        subtitle: L10n.localize("help.links.privacy_subtitle", comment: "Privacy quick link subtitle"),
                        systemImage: "hand.raised",
                        url: HelpExternalLinks.privacy
                    )
                }

                HelpSectionCard(
                    title: L10n.localize("help.section.permissions_title", comment: "Permissions section title"),
                    subtitle: L10n.localize("help.section.permissions_subtitle", comment: "Permissions section subtitle"),
                    systemImage: "checkmark.shield",
                    tint: AppTheme.ColorToken.accent
                ) {
                    HelpPermissionRow(
                        title: L10n.localize("help.permissions.microphone_title", comment: "Microphone permission row title"),
                        subtitle: L10n.localize("help.permissions.microphone_subtitle", comment: "Microphone permission row subtitle"),
                        systemImage: "mic",
                        status: settingsViewModel.microphonePermission.title,
                        satisfied: settingsViewModel.microphonePermission == .granted
                    )
                    HelpPermissionRow(
                        title: L10n.localize("help.permissions.accessibility_title", comment: "Accessibility permission row title"),
                        subtitle: L10n.localize("help.permissions.accessibility_subtitle", comment: "Accessibility permission row subtitle"),
                        systemImage: "accessibility",
                        status: PermissionSummary.statusText(settingsViewModel.accessibilityGranted),
                        satisfied: settingsViewModel.accessibilityGranted
                    )
                    HelpPermissionRow(
                        title: L10n.localize("help.permissions.speech_title", comment: "Speech permission row title"),
                        subtitle: L10n.localize("help.permissions.speech_subtitle", comment: "Speech permission row subtitle"),
                        systemImage: "waveform",
                        status: settingsViewModel.speechPermission.title,
                        satisfied: settingsViewModel.speechPermission == .granted
                    )
                    HelpPermissionRow(
                        title: L10n.localize("help.permissions.screen_recording_title", comment: "Screen recording permission row title"),
                        subtitle: L10n.localize("help.permissions.screen_recording_subtitle", comment: "Screen recording permission row subtitle"),
                        systemImage: "rectangle.inset.filled.and.person.filled",
                        status: PermissionSummary.statusText(settingsViewModel.screenRecordingGranted),
                        satisfied: settingsViewModel.screenRecordingGranted
                    )
                    Button {
                        settingsViewModel.load()
                        onOpenPermissions()
                    } label: {
                        Label(L10n.localize("help.permissions.open_settings", comment: "Open permissions detail button"), systemImage: "arrow.right")
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
            if showingSupportCommunityPanel {
                SupportCommunityOverlay {
                    showingSupportCommunityPanel = false
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
        return L10n.format("help.shortcuts.display_name_with_middle_mouse", comment: "Help shortcut title with middle mouse support",
            keyboardShortcut
        )
    }

    private var shortcutIconName: String {
        KeyCodeMapping.iconName(for: settingsViewModel.shortcutKeyCode)
    }

    private var shortcutSubtitle: String {
        if settingsViewModel.middleMouseRecordingEnabled {
            switch settingsViewModel.shortPressBehavior {
            case .toggleListening:
                return L10n.localize("help.shortcuts.subtitle_toggle_with_middle_mouse", comment: "Shortcut tooltip for middle mouse and toggle listening mode")
            case .none:
                return L10n.localize("help.shortcuts.subtitle_hold_with_middle_mouse", comment: "Shortcut tooltip for middle mouse and hold-to-speak mode")
            }
        } else {
            switch settingsViewModel.shortPressBehavior {
            case .toggleListening:
                return L10n.localize("help.shortcuts.subtitle_toggle", comment: "Shortcut tooltip for toggle listening mode")
            case .none:
                return L10n.localize("help.shortcuts.subtitle_hold", comment: "Shortcut tooltip for hold-to-speak mode")
            }
        }
    }

}

private struct SupportCommunityOverlay: View {
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
                        Text(L10n.localize("help.overlay.title", comment: "Support community panel title"))
                            .font(.system(size: 18, weight: .semibold))
                        Text(L10n.localize("help.overlay.subtitle", comment: "Support community panel subtitle"))
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

                HelpLinkRow(
                    title: L10n.localize("help.overlay.github_star_title", comment: "Support community github star link title"),
                    subtitle: L10n.localize("help.overlay.github_star_subtitle", comment: "Support community github star link subtitle"),
                    systemImage: "star",
                    iconStyle: .github,
                    url: HelpExternalLinks.githubRepository
                )

                HStack(alignment: .top, spacing: 14) {
                    SupportQRCodeCard(
                        title: L10n.localize("help.overlay.wechat_title", comment: "Author WeChat QR card title"),
                        subtitle: L10n.localize("help.overlay.wechat_subtitle", comment: "Author WeChat QR card subtitle"),
                        resourceName: "AuthorWeChatQRCode"
                    )
                    SupportQRCodeCard(
                        title: L10n.localize("help.overlay.user_group_title", comment: "User group QR card title"),
                        subtitle: L10n.localize("help.overlay.user_group_subtitle", comment: "User group QR card subtitle"),
                        resourceName: "UserGroupQRCode"
                    )
                }
            }
            .padding(22)
            .frame(width: 680)
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

private struct SupportQRCodeCard: View {
    let title: String
    let subtitle: String
    let resourceName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .lineLimit(2)
            }

            if let image = QRCodeImage.load(resourceName: resourceName) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300, height: 386)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: 1)
                    )
            } else {
                ContentUnavailableView(
                    L10n.localize("help.qr_unavailable.title", comment: "QR code loading failed title"),
                    systemImage: "qrcode",
                    description: Text(L10n.localize("help.qr_unavailable.description", comment: "QR code loading failed message"))
                )
                .frame(width: 300, height: 240)
            }
        }
        .frame(width: 300, alignment: .topLeading)
    }
}

private enum QRCodeImage {
    static func load(resourceName: String) -> NSImage? {
        guard let url = VoxFlowAppResourceBundle.url(
            forResource: resourceName,
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
