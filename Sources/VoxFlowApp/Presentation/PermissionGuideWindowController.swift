import AppKit
import SwiftUI

struct PermissionStatusItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let status: String
    let granted: Bool
    let settingsURL: URL?

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        status: String,
        granted: Bool,
        settingsURL: URL? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.status = status
        self.granted = granted
        self.settingsURL = settingsURL
    }
}

enum PermissionGuideLayout {
    static func windowHeight(itemCount: Int) -> CGFloat {
        min(560, max(470, CGFloat(itemCount) * 78 + 280))
    }
}

enum PermissionGuideDestination {
    static func primarySettingsURL(
        items: [PermissionStatusItem],
        fallback: URL?
    ) -> URL? {
        items.first { !$0.granted && $0.settingsURL != nil }?.settingsURL
            ?? items.first { $0.settingsURL != nil }?.settingsURL
            ?? fallback
    }
}

@MainActor
final class PermissionGuideWindowController: NSWindowController {
    private static let logger = AppLogger.general

    init(
        title: String,
        subtitle: String,
        items: [PermissionStatusItem],
        settingsURL: URL?
    ) {
        Self.logger.debug(
            "permission_guide_init itemCount=\(items.count) hasDefaultURL=\(settingsURL != nil)"
        )
        let windowHeight = PermissionGuideLayout.windowHeight(itemCount: items.count)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: windowHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .windowBackgroundColor
        panel.center()

        super.init(window: panel)

        let rootView = PermissionGuideView(
            title: title,
            subtitle: subtitle,
            items: items,
            windowHeight: windowHeight,
            onDone: { [weak panel] in
                Self.logger.debug("permission_guide_done pressed")
                panel?.close()
            },
            onOpenSettings: PermissionGuideDestination.primarySettingsURL(
                items: items,
                fallback: settingsURL
            ).map { url in
                { [weak panel] in
                    Self.logger.info("permission_guide_open_settings url=\(url)")
                    NSWorkspace.shared.open(url)
                    panel?.close()
                }
            },
            onOpenItemSettings: { [weak panel] item in
                guard let url = item.settingsURL else { return }
                Self.logger.info("permission_guide_open_item_settings title=\(item.title) url=\(url)")
                NSWorkspace.shared.open(url)
                panel?.close()
            }
        )
        panel.contentView = NSHostingView(rootView: rootView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        Self.logger.debug("permission_guide_present")
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        if let window {
            WindowPlacementPolicy.placeOnVisibleScreenIfNeeded(window)
        }
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct PermissionGuideView: View {
    let title: String
    let subtitle: String
    let items: [PermissionStatusItem]
    let windowHeight: CGFloat
    let onDone: () -> Void
    let onOpenSettings: (() -> Void)?
    let onOpenItemSettings: (PermissionStatusItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.ColorToken.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.icon))
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ForEach(items) { item in
                    permissionRow(item)
                }
            }

            Text("权限刚刚修改后，请回到码上写重新检查。")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Spacer()
                Button("完成", action: onDone)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                if let onOpenSettings {
                    Button("打开系统设置", action: onOpenSettings)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
            .layoutPriority(1)
        }
        .padding(28)
        .frame(width: 520, height: windowHeight, alignment: .topLeading)
        .background(AppTheme.ColorToken.pageBackground)
        .tint(AppTheme.ColorToken.accent)
    }

    private func permissionRow(_ item: PermissionStatusItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(item.granted ? Color.green : Color.orange)
                .frame(width: 40, height: 40)
                .background((item.granted ? Color.green : Color.orange).opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.icon))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(item.status)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(item.granted ? Color.green : Color.orange)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background((item.granted ? Color.green : Color.orange).opacity(0.09))
                .clipShape(Capsule())
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .appControlSurface(cornerRadius: AppTheme.Radius.row)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenItemSettings(item)
        }
        .help(item.settingsURL == nil ? "" : "打开\(item.title)权限设置")
    }
}
