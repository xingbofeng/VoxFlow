import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ScreenRecordingResultPanelController {
    private var panel: NSPanel?
    private let repository: any MediaRecordRepository
    private let clock: any AppClock
    private let coordinator: RecordingSubtitleCoordinator
    private let onDelete: () -> Void
    private let hudState = RecordingSubtitleHUDState()
    private var currentRecordID: String?

    init(
        repository: any MediaRecordRepository,
        clock: any AppClock,
        coordinator: RecordingSubtitleCoordinator,
        onDelete: @escaping () -> Void
    ) {
        self.repository = repository
        self.clock = clock
        self.coordinator = coordinator
        self.onDelete = onDelete
    }

    func present(record: MediaRecord) {
        close()
        currentRecordID = record.id
        hudState.update(record: record, state: coordinator.currentState(for: record.id))
        let rootView = ScreenRecordingResultHUDView(
            record: record,
            hudState: hudState,
            initialDidCopyFile: false,
            onOpen: { [weak self] in self?.open(record) ?? false },
            onCopyFile: { [weak self] in _ = self?.copyFile(record) },
            onDownload: { [weak self] in self?.download(record) ?? false },
            onRevealInFinder: { [weak self] in self?.revealInFinder(record) ?? false },
            onDelete: { [weak self] in self?.delete(record) ?? false },
            onSubtitle: { [weak self] in self?.handleSubtitleAction() },
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
        panel.isMovableByWindowBackground = true
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
        currentRecordID = nil
    }

    /// 协调器字幕状态变化时刷新 HUD（仅当 HUD 正展示该记录）。
    func handleSubtitleStateChange(recordID: String) {
        guard recordID == currentRecordID else { return }
        let latestRecord = (try? repository.record(id: recordID)) ?? hudState.record
        if let latestRecord {
            hudState.update(record: latestRecord, state: coordinator.currentState(for: recordID))
        } else {
            hudState.update(state: coordinator.currentState(for: recordID))
        }
    }

    var presentationScreen: NSScreen? {
        panel?.screen
    }

    @discardableResult
    private func open(_ record: MediaRecord) -> Bool {
        guard let url = existingFileURL(for: currentRecord(fallback: record)) else {
            NSSound.beep()
            return false
        }
        NSWorkspace.shared.open(url)
        return true
    }

    @discardableResult
    private func copyFile(_ record: MediaRecord) -> Bool {
        guard let url = existingFileURL(for: currentRecord(fallback: record)) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([url as NSURL])
    }

    @discardableResult
    private func download(_ record: MediaRecord) -> Bool {
        guard let url = existingFileURL(for: currentRecord(fallback: record)) else {
            NSSound.beep()
            return false
        }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = url.lastPathComponent
        panel.isExtensionHidden = false
        if let contentType = UTType(filenameExtension: url.pathExtension) {
            panel.allowedContentTypes = [contentType]
        }
        guard panel.runModal() == .OK, let destination = panel.url else {
            return false
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    @discardableResult
    private func revealInFinder(_ record: MediaRecord) -> Bool {
        guard let url = existingFileURL(for: currentRecord(fallback: record)) else {
            NSSound.beep()
            return false
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        activateFinder()
        return true
    }

    @discardableResult
    private func delete(_ record: MediaRecord) -> Bool {
        let record = currentRecord(fallback: record)
        try? repository.softDelete(id: record.id, deletedAt: clock.now)
        coordinator.cancelInFlightTasks(recordID: record.id)
        for path in filePathsToDelete(for: record) {
            try? FileManager.default.removeItem(atPath: path)
        }
        close()
        onDelete()
        return true
    }

    private func activateFinder() {
        var scriptError: NSDictionary?
        _ = NSAppleScript(source: "tell application id \"com.apple.finder\" to activate")?
            .executeAndReturnError(&scriptError)

        guard let finder = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.finder"
        }) else {
            return
        }
        _ = finder.activate(options: [.activateAllWindows])
    }

    private func handleSubtitleAction() {
        guard let id = currentRecordID else { return }
        let state = coordinator.currentState(for: id)
        if state.status == .burned, let record = try? repository.record(id: id), let path = record.subtitledVideoPath {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return
        }
        coordinator.addSubtitle(recordID: id)
    }

    private func currentRecord(fallback record: MediaRecord) -> MediaRecord {
        (try? repository.record(id: record.id)) ?? hudState.record ?? record
    }

    private func existingFileURL(for record: MediaRecord) -> URL? {
        for path in filePathCandidates(for: record) where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private func filePathsToDelete(for record: MediaRecord) -> [String] {
        filePathCandidates(for: record) + [
            record.subtitleDraftPath,
            record.subtitleSrtPath
        ].compactMap { $0 }
    }

    private func filePathCandidates(for record: MediaRecord) -> [String] {
        [
            record.primaryFilePath,
            record.videoPath,
            record.imagePath,
            record.subtitledVideoPath
        ]
        .compactMap { $0 }
        .reduce(into: [String]()) { result, path in
            if !result.contains(path) {
                result.append(path)
            }
        }
    }

}

/// HUD 字幕状态：可观察，供视图在协调器状态变化时刷新。
@MainActor
final class RecordingSubtitleHUDState: ObservableObject {
    @Published var record: MediaRecord?
    @Published var state: RecordingSubtitleState = .none

    func update(record: MediaRecord, state: RecordingSubtitleState) {
        self.record = record
        self.state = state
    }

    func update(state: RecordingSubtitleState) {
        self.state = state
    }
}

struct ScreenRecordingResultHUDActionPresentation: Equatable, Identifiable {
    enum Kind: Equatable, Hashable {
        case open
        case copyFile
        case download
        case revealInFinder
        case delete
        case subtitle
    }

    let kind: Kind
    let accessibilityTitle: String
    let systemImage: String
    let help: String
    let isEnabled: Bool
    let isDestructive: Bool
    let showsSpinner: Bool
    let isIconOnly: Bool
    let allowsVisibleTitle: Bool
    let width: CGFloat
    let height: CGFloat

    var id: Kind { kind }

    init(
        kind: Kind,
        accessibilityTitle: String,
        systemImage: String,
        help: String,
        isEnabled: Bool = true,
        isDestructive: Bool = false,
        showsSpinner: Bool = false,
        isIconOnly: Bool = true,
        allowsVisibleTitle: Bool = false,
        width: CGFloat = 42,
        height: CGFloat = 32
    ) {
        self.kind = kind
        self.accessibilityTitle = accessibilityTitle
        self.systemImage = systemImage
        self.help = help
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
        self.showsSpinner = showsSpinner
        self.isIconOnly = isIconOnly
        self.allowsVisibleTitle = allowsVisibleTitle
        self.width = width
        self.height = height
    }
}

enum ScreenRecordingResultHUDPresentation {
    static func actions(
        for record: MediaRecord,
        subtitleState: RecordingSubtitleState,
        didCopyFile: Bool,
        didDownloadFile: Bool,
        isDeleteConfirmationPending: Bool = false
    ) -> [ScreenRecordingResultHUDActionPresentation] {
        [
            ScreenRecordingResultHUDActionPresentation(
                kind: .open,
                accessibilityTitle: L10n.localize("recording.hud.action_open", comment: ""),
                systemImage: "arrow.up.right.square",
                help: L10n.localize("recording.hud.action_open_help", comment: "")
            ),
            ScreenRecordingResultHUDActionPresentation(
                kind: .copyFile,
                accessibilityTitle: didCopyFile ? L10n.localize("recording.hud.action_copy_done", comment: "") : L10n.localize("recording.hud.action_copy", comment: ""),
                systemImage: didCopyFile ? "checkmark" : "doc.on.doc",
                help: L10n.localize("recording.hud.action_copy_help", comment: "")
            ),
            ScreenRecordingResultHUDActionPresentation(
                kind: .download,
                accessibilityTitle: didDownloadFile ? L10n.localize("recording.hud.action_download_done", comment: "") : L10n.localize("recording.hud.action_download", comment: ""),
                systemImage: didDownloadFile ? "checkmark" : "square.and.arrow.down",
                help: L10n.localize("recording.hud.action_download_help", comment: "")
            ),
            ScreenRecordingResultHUDActionPresentation(
                kind: .revealInFinder,
                accessibilityTitle: "Finder",
                systemImage: "folder",
                help: L10n.localize("recording.hud.action_reveal_in_finder_help", comment: "")
            ),
            ScreenRecordingResultHUDActionPresentation(
                kind: .delete,
                accessibilityTitle: isDeleteConfirmationPending ? L10n.localize("recording.hud.action_delete_confirm", comment: "") : L10n.localize("recording.hud.action_delete", comment: ""),
                systemImage: isDeleteConfirmationPending ? "trash.fill" : "trash",
                help: isDeleteConfirmationPending ? L10n.localize("recording.hud.action_delete_confirm_help", comment: "") : L10n.localize("recording.hud.action_delete_help", comment: ""),
                isDestructive: true
            ),
            subtitleAction(for: record, state: subtitleState)
        ]
    }

    private static func subtitleAction(
        for record: MediaRecord,
        state: RecordingSubtitleState
    ) -> ScreenRecordingResultHUDActionPresentation {
        let canAdd = record.mediaType == .screenRecording && record.audioMode == .microphone
        if !canAdd {
            return ScreenRecordingResultHUDActionPresentation(
                kind: .subtitle,
                accessibilityTitle: L10n.localize("subtitle.hud.action_add_subtitle", comment: ""),
                systemImage: "captions.bubble",
                help: L10n.localize("subtitle.error.no_microphone_track", comment: ""),
                isEnabled: false
            )
        }

        switch state.status {
        case .none:
            return ScreenRecordingResultHUDActionPresentation(
                kind: .subtitle,
                accessibilityTitle: L10n.localize("subtitle.hud.action_add_subtitle", comment: ""),
                systemImage: "captions.bubble",
                help: L10n.localize("subtitle.hud.action_add_subtitle", comment: "")
            )
        case .generating:
            return ScreenRecordingResultHUDActionPresentation(
                kind: .subtitle,
                accessibilityTitle: L10n.localize("subtitle.status.generating", comment: ""),
                systemImage: "captions.bubble",
                help: L10n.localize("subtitle.hud.subtitle_generating_help", comment: ""),
                isEnabled: false,
                showsSpinner: true
            )
        case .draftReady:
            return ScreenRecordingResultHUDActionPresentation(
                kind: .subtitle,
                accessibilityTitle: L10n.localize("subtitle.hud.action_edit_subtitle", comment: ""),
                systemImage: "captions.bubble",
                help: L10n.localize("subtitle.hud.action_edit_subtitle", comment: "")
            )
        case .burning:
            return ScreenRecordingResultHUDActionPresentation(
                kind: .subtitle,
                accessibilityTitle: L10n.localize("subtitle.status.burning", comment: ""),
                systemImage: "captions.bubble",
                help: L10n.localize("subtitle.hud.subtitle_burning_help", comment: ""),
                isEnabled: false,
                showsSpinner: true
            )
        case .burned:
            return ScreenRecordingResultHUDActionPresentation(
                kind: .subtitle,
                accessibilityTitle: L10n.localize("subtitle.hud.action_open_subtitled_video", comment: ""),
                systemImage: "captions.bubble.fill",
                help: L10n.localize("subtitle.hud.action_open_subtitled_video", comment: "")
            )
        case .failed:
            return ScreenRecordingResultHUDActionPresentation(
                kind: .subtitle,
                accessibilityTitle: L10n.localize("subtitle.hud.action_regenerate_subtitle", comment: ""),
                systemImage: "arrow.clockwise",
                help: L10n.localize("subtitle.hud.action_regenerate_subtitle", comment: "")
            )
        }
    }
}

private struct ScreenRecordingResultHUDView: View {
    let record: MediaRecord
    @ObservedObject var hudState: RecordingSubtitleHUDState
    let onOpen: () -> Bool
    let onCopyFile: () -> Void
    let onDownload: () -> Bool
    let onRevealInFinder: () -> Bool
    let onDelete: () -> Bool
    let onSubtitle: () -> Void
    let onClose: () -> Void
    @State private var didCopyFile: Bool
    @State private var didDownloadFile = false
    @State private var feedbackText: String?
    @State private var hoveredHelp: String?
    @State private var isDeleteConfirmationPending = false

    init(
        record: MediaRecord,
        hudState: RecordingSubtitleHUDState,
        initialDidCopyFile: Bool,
        onOpen: @escaping () -> Bool,
        onCopyFile: @escaping () -> Void,
        onDownload: @escaping () -> Bool,
        onRevealInFinder: @escaping () -> Bool,
        onDelete: @escaping () -> Bool,
        onSubtitle: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.record = record
        self.hudState = hudState
        self.onOpen = onOpen
        self.onCopyFile = onCopyFile
        self.onDownload = onDownload
        self.onRevealInFinder = onRevealInFinder
        self.onDelete = onDelete
        self.onSubtitle = onSubtitle
        self.onClose = onClose
        _didCopyFile = State(initialValue: initialDidCopyFile)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HStack {
                    Text(L10n.localize("recording.result.title_saved", comment: ""))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .overlay(TextResultPanelDragHandle())

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help(L10n.localize("recording.result.action_close", comment: ""))
            }
            videoPreview
            HStack(spacing: 8) {
                ForEach(actionPresentations) { presentation in
                    resultActionButton(presentation) {
                        performAction(presentation.kind)
                    }
                }
                Spacer()
            }
        }
        .padding(12)
        .frame(width: 360, height: 300)
        .background(AppTheme.ColorToken.panelBackground.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if let statusText = feedbackText ?? hoveredHelp {
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AppTheme.ColorToken.controlBackground.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.leading, 16)
                    .padding(.bottom, 52)
                    .transition(.opacity)
            }
        }
    }

    private var actionPresentations: [ScreenRecordingResultHUDActionPresentation] {
        let displayRecord = hudState.record ?? record
        return ScreenRecordingResultHUDPresentation.actions(
            for: displayRecord,
            subtitleState: hudState.state,
            didCopyFile: didCopyFile,
            didDownloadFile: didDownloadFile,
            isDeleteConfirmationPending: isDeleteConfirmationPending
        )
    }

    private func resultActionButton(
        _ presentation: ScreenRecordingResultHUDActionPresentation,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                if presentation.showsSpinner {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(presentation.accessibilityTitle)
                } else {
                    Label(presentation.accessibilityTitle, systemImage: presentation.systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .labelStyle(.iconOnly)
                }
            }
            .frame(width: presentation.width, height: presentation.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!presentation.isEnabled)
        .foregroundStyle(presentation.isDestructive ? Color.red : AppTheme.ColorToken.primaryText)
        .background(AppTheme.ColorToken.controlBackground.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(presentation.help)
        .onHover { hovering in
            if hovering {
                hoveredHelp = presentation.help
            } else if hoveredHelp == presentation.help {
                hoveredHelp = nil
            }
        }
    }

    private func performAction(_ kind: ScreenRecordingResultHUDActionPresentation.Kind) {
        if kind != .delete {
            isDeleteConfirmationPending = false
        }
        switch kind {
        case .open:
            showFeedback(onOpen() ? L10n.localize("recording.feedback.opened_file", comment: "") : L10n.localize("recording.feedback.file_not_found", comment: ""))
        case .copyFile:
            onCopyFile()
            didCopyFile = true
            showFeedback(L10n.localize("recording.feedback.file_copied", comment: ""))
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                didCopyFile = false
            }
        case .download:
            if onDownload() {
                didDownloadFile = true
                showFeedback(L10n.localize("recording.feedback.file_saved", comment: ""))
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    didDownloadFile = false
                }
            } else {
                showFeedback(L10n.localize("recording.feedback.save_cancelled", comment: ""))
            }
        case .revealInFinder:
            showFeedback(onRevealInFinder() ? L10n.localize("recording.feedback.revealed_in_finder", comment: "") : L10n.localize("recording.feedback.file_not_found", comment: ""))
        case .delete:
            if isDeleteConfirmationPending {
                isDeleteConfirmationPending = false
                showFeedback(onDelete() ? L10n.localize("recording.feedback.recording_deleted", comment: "") : L10n.localize("recording.feedback.delete_failed", comment: ""))
            } else {
                isDeleteConfirmationPending = true
                showFeedback(L10n.localize("recording.feedback.delete_confirmation", comment: ""), durationNanoseconds: 4_000_000_000)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    if isDeleteConfirmationPending {
                        isDeleteConfirmationPending = false
                    }
                }
            }
        case .subtitle:
            onSubtitle()
        }
    }

    private func showFeedback(_ text: String, durationNanoseconds: UInt64 = 1_800_000_000) {
        feedbackText = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: durationNanoseconds)
            if feedbackText == text {
                feedbackText = nil
            }
        }
    }

    private var videoPreview: some View {
        ZStack {
            AppTheme.ColorToken.controlBackground.opacity(0.45)
            let displayRecord = hudState.record ?? record
            if let videoPath = displayRecord.primaryVideoPath {
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
