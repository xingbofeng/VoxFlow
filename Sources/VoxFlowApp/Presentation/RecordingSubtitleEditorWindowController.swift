import AppKit
import SwiftUI

/// 字幕编辑确认窗口控制器：作为独立 panel 打开，不挤在详情栏里。
@MainActor
final class RecordingSubtitleEditorWindowController {
    private var panel: NSPanel?
    private let coordinator: RecordingSubtitleCoordinator

    init(coordinator: RecordingSubtitleCoordinator) {
        self.coordinator = coordinator
    }

    func present(recordID: String, preferredScreen: NSScreen? = nil) {
        close()
        let size = CGSize(width: 880, height: 560)
        let rootView = RecordingSubtitleEditorView(
            recordID: recordID,
            coordinator: coordinator,
            onClose: { [weak self] in self?.close() }
        )
        let hostingController = NSHostingController(rootView: rootView)
        let panel = NSPanel(
            contentRect: Self.centerFrame(size: size, screen: preferredScreen),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.contentViewController = hostingController
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel?.close()
        panel = nil
    }

    private static func centerFrame(size: CGSize, screen preferredScreen: NSScreen?) -> CGRect {
        guard let screen = preferredScreen ?? NSScreen.main else {
            return CGRect(origin: .zero, size: size)
        }
        let visibleFrame = screen.visibleFrame
        let origin = CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
        return CGRect(origin: origin, size: size)
    }
}
