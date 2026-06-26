import AppKit
import SwiftUI

@MainActor
final class ScreenRecordingResultPanelController {
    private var panel: NSPanel?
    private let repository: any MediaRecordRepository
    private let clock: any AppClock
    private let onDelete: () -> Void

    init(
        repository: any MediaRecordRepository,
        clock: any AppClock,
        onDelete: @escaping () -> Void
    ) {
        self.repository = repository
        self.clock = clock
        self.onDelete = onDelete
    }

    func present(record: MediaRecord) {
        close()
        let didCopyFile = copyFile(record)
        let rootView = ScreenRecordingResultHUDView(
            record: record,
            initialDidCopyFile: didCopyFile,
            onOpen: { [weak self] in self?.open(record) },
            onCopyFile: { [weak self] in _ = self?.copyFile(record) },
            onDownload: { [weak self] in self?.download(record) },
            onRevealInFinder: { [weak self] in self?.revealInFinder(record) },
            onDelete: { [weak self] in self?.delete(record) },
            onClose: { [weak self] in self?.close() }
        )
        let hostingController = NSHostingController(rootView: rootView)
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.contentViewController = hostingController
        if let visibleFrame = NSScreen.main?.visibleFrame {
            let origin = CGPoint(
                x: visibleFrame.maxX - 380,
                y: visibleFrame.minY + 28
            )
            panel.setFrame(CGRect(origin: origin, size: CGSize(width: 360, height: 300)), display: false)
        }
        self.panel = panel
        panel.orderFront(nil)
    }

    func close() {
        panel?.close()
        panel = nil
    }

    private func open(_ record: MediaRecord) {
        guard let url = videoURL(for: record) else { return }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    private func copyFile(_ record: MediaRecord) -> Bool {
        guard let url = videoURL(for: record) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([url as NSURL])
    }

    private func download(_ record: MediaRecord) {
        guard let url = videoURL(for: record) else { return }
        do {
            let destination = try uniqueDownloadURL(for: url)
            try FileManager.default.copyItem(at: url, to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            NSSound.beep()
        }
    }

    private func revealInFinder(_ record: MediaRecord) {
        guard let url = videoURL(for: record) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func delete(_ record: MediaRecord) {
        try? repository.softDelete(id: record.id, deletedAt: clock.now)
        if let url = videoURL(for: record) {
            try? FileManager.default.removeItem(at: url)
        }
        close()
        onDelete()
    }

    private func videoURL(for record: MediaRecord) -> URL? {
        record.videoPath.map(URL.init(fileURLWithPath:))
    }

    private func uniqueDownloadURL(for sourceURL: URL) throws -> URL {
        guard let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let pathExtension = sourceURL.pathExtension
        var destination = downloadsDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let fileName = pathExtension.isEmpty
                ? "\(baseName)-\(suffix)"
                : "\(baseName)-\(suffix).\(pathExtension)"
            destination = downloadsDirectory.appendingPathComponent(fileName)
            suffix += 1
        }
        return destination
    }
}

private struct ScreenRecordingResultHUDView: View {
    let record: MediaRecord
    let onOpen: () -> Void
    let onCopyFile: () -> Void
    let onDownload: () -> Void
    let onRevealInFinder: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void
    @State private var didCopyFile: Bool
    @State private var didDownloadFile = false

    init(
        record: MediaRecord,
        initialDidCopyFile: Bool,
        onOpen: @escaping () -> Void,
        onCopyFile: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onRevealInFinder: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.record = record
        self.onOpen = onOpen
        self.onCopyFile = onCopyFile
        self.onDownload = onDownload
        self.onRevealInFinder = onRevealInFinder
        self.onDelete = onDelete
        self.onClose = onClose
        _didCopyFile = State(initialValue: initialDidCopyFile)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("录屏已保存")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
            videoPreview
            HStack(spacing: 8) {
                resultActionButton("打开", systemImage: "arrow.up.right.square", help: "打开文件", action: onOpen)
                resultActionButton(
                    didCopyFile ? "已复制" : "复制",
                    systemImage: didCopyFile ? "checkmark" : "doc.on.doc",
                    help: "复制文件"
                ) {
                    onCopyFile()
                    didCopyFile = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        didCopyFile = false
                    }
                }
                resultActionButton(
                    didDownloadFile ? "已下载" : "下载",
                    systemImage: didDownloadFile ? "checkmark" : "square.and.arrow.down",
                    help: "下载到 Downloads"
                ) {
                    onDownload()
                    didDownloadFile = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        didDownloadFile = false
                    }
                }
                resultActionButton("Finder", systemImage: "folder", help: "在 Finder 中显示", action: onRevealInFinder)
                resultActionButton("删除", systemImage: "trash", help: "删除", role: .destructive, action: onDelete)
                Spacer()
            }
        }
        .padding(12)
        .frame(width: 360, height: 300)
        .background(AppTheme.ColorToken.panelBackground.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func resultActionButton(
        _ title: String,
        systemImage: String,
        help: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .labelStyle(.iconOnly)
                .frame(width: 42, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Color.red : AppTheme.ColorToken.primaryText)
        .background(AppTheme.ColorToken.controlBackground.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(help)
    }

    private var videoPreview: some View {
        ZStack {
            AppTheme.ColorToken.controlBackground.opacity(0.45)
            if let videoPath = record.videoPath {
                MediaVideoPlayerView(url: URL(fileURLWithPath: videoPath))
            } else {
                Image(systemName: "video.slash")
                    .font(.system(size: 34))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
