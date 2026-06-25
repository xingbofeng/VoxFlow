import AppKit
import SwiftUI

enum UpdatePromptAction {
    case download
    case remindNextTime
    case remindTomorrow
    case ignore
}

@MainActor
protocol UpdatePromptPresenting: AnyObject {
    func presentUpdateAvailable(release: RemoteRelease, currentVersion: String) async -> UpdatePromptAction
    func presentUpToDate(currentVersion: String) async
    func presentFailure() async
    func dismissActivePromptAsNextTime()
}

struct UpdatePromptPresentation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let iconName: String
    let primaryTitle: String
    let secondaryTitle: String?
    let destructiveTitle: String?
}

@MainActor
final class UpdatePromptPresentationStore: ObservableObject {
    @Published private(set) var presentation: UpdatePromptPresentation?
    var isHostVisible = false

    private var continuation: CheckedContinuation<UpdatePromptAction, Never>?

    func present(_ presentation: UpdatePromptPresentation) async -> UpdatePromptAction {
        finish(.remindNextTime)
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.presentation = presentation
        }
    }

    func finish(_ action: UpdatePromptAction) {
        presentation = nil
        continuation?.resume(returning: action)
        continuation = nil
    }
}

@MainActor
final class UpdatePromptPresenter: UpdatePromptPresenting {
    private let presentationStore: UpdatePromptPresentationStore?

    init(presentationStore: UpdatePromptPresentationStore? = nil) {
        self.presentationStore = presentationStore
    }

    func presentUpdateAvailable(release: RemoteRelease, currentVersion: String) async -> UpdatePromptAction {
        let presentation = UpdatePromptPresentation(
            title: "发现新版本 VoxFlow \(release.version)",
            message: Self.informativeText(for: release, currentVersion: currentVersion),
            iconName: "arrow.down.circle.fill",
            primaryTitle: "下载更新",
            secondaryTitle: "明天提醒",
            destructiveTitle: "跳过此版本"
        )
        let action = await present(presentation)
        if action == .download {
            NSWorkspace.shared.open(release.downloadURL)
        }
        return action
    }

    func presentUpToDate(currentVersion: String) async {
        _ = await present(
            UpdatePromptPresentation(
                title: "当前已是最新版",
                message: "VoxFlow \(currentVersion) 已是当前稳定版本。",
                iconName: "checkmark.circle.fill",
                primaryTitle: "好",
                secondaryTitle: nil,
                destructiveTitle: nil
            )
        )
    }

    func presentFailure() async {
        _ = await present(
            UpdatePromptPresentation(
                title: "检查更新失败",
                message: "暂时无法获取最新版本信息，请稍后再试。",
                iconName: "exclamationmark.triangle.fill",
                primaryTitle: "好",
                secondaryTitle: nil,
                destructiveTitle: nil
            )
        )
    }

    func dismissActivePromptAsNextTime() {
        presentationStore?.finish(.remindNextTime)
        UpdatePromptWindowController.dismissActive(action: .remindNextTime)
    }

    private func present(_ presentation: UpdatePromptPresentation) async -> UpdatePromptAction {
        if let presentationStore, presentationStore.isHostVisible {
            return await presentationStore.present(presentation)
        }
        return UpdatePromptWindowController.run(presentation: presentation)
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

@MainActor
private final class UpdatePromptWindowController: NSWindowController, NSWindowDelegate {
    private static weak var activeController: UpdatePromptWindowController?
    private var selectedAction: UpdatePromptAction = .remindNextTime

    static func run(presentation: UpdatePromptPresentation) -> UpdatePromptAction {
        let controller = UpdatePromptWindowController(presentation: presentation)
        return controller.run()
    }

    static func dismissActive(action: UpdatePromptAction) {
        activeController?.finish(action)
    }

    private init(presentation: UpdatePromptPresentation) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 260),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "VoxFlow 更新"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: UpdatePromptView(
                presentation: presentation,
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
        WindowPlacementPolicy.centerOnMainScreen(window)
        window.makeKeyAndOrderFront(nil)
        Self.activeController = self
        NSApp.runModal(for: window)
        if Self.activeController === self {
            Self.activeController = nil
        }
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

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish(.remindNextTime)
        return false
    }
}

struct UpdatePromptOverlayView: View {
    let presentation: UpdatePromptPresentation
    let onAction: (UpdatePromptAction) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    onAction(.remindNextTime)
                }

            UpdatePromptView(
                presentation: presentation,
                onAction: onAction
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 28, y: 12)
            .contentShape(Rectangle())
            .onTapGesture {}
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand {
            onAction(.remindNextTime)
        }
    }
}

private struct UpdatePromptView: View {
    let presentation: UpdatePromptPresentation
    let onAction: (UpdatePromptAction) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: presentation.iconName)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.accent)
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(presentation.title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AppTheme.ColorToken.primaryText)
                        Text(presentation.message)
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .padding(.trailing, 28)
                }

                HStack(spacing: 10) {
                    if let destructiveTitle = presentation.destructiveTitle {
                        Button(destructiveTitle) {
                            onAction(.ignore)
                        }
                        .buttonStyle(.bordered)
                    }

                    if let secondaryTitle = presentation.secondaryTitle {
                        Button(secondaryTitle) {
                            onAction(.remindTomorrow)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(presentation.primaryTitle) {
                        onAction(presentation.primaryTitle == "下载更新" ? .download : .remindNextTime)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(24)

            Button {
                onAction(.remindNextTime)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
            .help("关闭，下次提醒")
            .padding(16)
        }
        .frame(width: 480)
        .background(Color(nsColor: .textBackgroundColor))
        .tint(AppTheme.ColorToken.accent)
    }
}
