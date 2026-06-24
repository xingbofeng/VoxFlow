import AppKit
import SwiftUI

enum UpdatePromptAction {
    case download
    case remindLater
    case ignore
}

@MainActor
final class UpdatePromptPresenter {
    func presentUpdateAvailable(release: RemoteRelease, currentVersion: String) -> UpdatePromptAction {
        let action = UpdatePromptWindowController.runUpdateAvailable(
            release: release,
            currentVersion: currentVersion
        )
        if action == .download {
            NSWorkspace.shared.open(release.downloadURL)
        }
        return action
    }

    func presentUpToDate(currentVersion: String) {
        _ = UpdatePromptWindowController.runMessage(
            title: "当前已是最新版",
            message: "VoxFlow \(currentVersion) 已是当前稳定版本。",
            primaryTitle: "好"
        )
    }

    func presentFailure() {
        _ = UpdatePromptWindowController.runMessage(
            title: "检查更新失败",
            message: "暂时无法获取最新版本信息，请稍后再试。",
            primaryTitle: "好"
        )
    }
}

@MainActor
private final class UpdatePromptWindowController: NSWindowController {
    private var selectedAction: UpdatePromptAction = .remindLater

    static func runUpdateAvailable(release: RemoteRelease, currentVersion: String) -> UpdatePromptAction {
        let controller = UpdatePromptWindowController(
            title: "发现新版本 VoxFlow \(release.version)",
            message: informativeText(for: release, currentVersion: currentVersion),
            iconName: "arrow.down.circle.fill",
            primaryTitle: "下载更新",
            secondaryTitle: "稍后提醒",
            destructiveTitle: "忽略此版本"
        )
        return controller.run()
    }

    static func runMessage(title: String, message: String, primaryTitle: String) -> UpdatePromptAction {
        let controller = UpdatePromptWindowController(
            title: title,
            message: message,
            iconName: title == "检查更新失败" ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
            primaryTitle: primaryTitle,
            secondaryTitle: nil,
            destructiveTitle: nil
        )
        return controller.run()
    }

    private init(
        title: String,
        message: String,
        iconName: String,
        primaryTitle: String,
        secondaryTitle: String?,
        destructiveTitle: String?
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoxFlow 更新"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentViewController = NSHostingController(
            rootView: UpdatePromptView(
                title: title,
                message: message,
                iconName: iconName,
                primaryTitle: primaryTitle,
                secondaryTitle: secondaryTitle,
                destructiveTitle: destructiveTitle,
                onAction: { [weak self] action in
                    self?.finish(action)
                }
            )
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func run() -> UpdatePromptAction {
        guard let window else { return selectedAction }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return selectedAction
    }

    private func finish(_ action: UpdatePromptAction) {
        selectedAction = action
        if let window {
            NSApp.stopModal()
            window.orderOut(nil)
        }
    }

    private static func informativeText(for release: RemoteRelease, currentVersion: String) -> String {
        let notes = release.releaseNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = notes.isEmpty ? "打开发布页查看详细更新内容。" : String(notes.prefix(600))
        return """
        当前版本：\(currentVersion)
        最新版本：\(release.version)

        \(summary)
        """
    }
}

private struct UpdatePromptView: View {
    let title: String
    let message: String
    let iconName: String
    let primaryTitle: String
    let secondaryTitle: String?
    let destructiveTitle: String?
    let onAction: (UpdatePromptAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: iconName)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                if let destructiveTitle {
                    Button(destructiveTitle) {
                        onAction(.ignore)
                    }
                    .buttonStyle(.bordered)
                }

                Spacer(minLength: 0)

                if let secondaryTitle {
                    Button(secondaryTitle) {
                        onAction(.remindLater)
                    }
                    .buttonStyle(.bordered)
                }

                Button(primaryTitle) {
                    onAction(primaryTitle == "下载更新" ? .download : .remindLater)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .frame(minHeight: 260)
        .background(AppTheme.ColorToken.pageBackground)
    }
}
