import AppKit
import SwiftUI

struct RecordingSubtitleDetailActionPresentation: Equatable, Identifiable {
    enum Kind: Equatable, Hashable {
        case addSubtitle
        case progress
        case openEditor
        case burn
        case openSubtitledVideo
        case openOriginalVideo
        case retry
    }

    let kind: Kind
    let title: String
    let help: String
    let isEnabled: Bool
    let showsProgress: Bool

    var id: Kind { kind }

    init(
        kind: Kind,
        title: String,
        help: String,
        isEnabled: Bool = true,
        showsProgress: Bool = false
    ) {
        self.kind = kind
        self.title = title
        self.help = help
        self.isEnabled = isEnabled
        self.showsProgress = showsProgress
    }
}

struct RecordingSubtitleDetailPresentation: Equatable {
    let sectionTitle: String
    let statusText: String
    let errorMessage: String?
    let actions: [RecordingSubtitleDetailActionPresentation]

    static func make(for record: MediaRecord) -> RecordingSubtitleDetailPresentation? {
        guard record.mediaType == .screenRecording else { return nil }

        if record.audioMode != .microphone {
            return RecordingSubtitleDetailPresentation(
                sectionTitle: L10n.localize("screenshot.record.detail.subtitle_section_title", comment: ""),
                statusText: L10n.localize("screenshot.record.detail.subtitle_status_no_microphone", comment: ""),
                errorMessage: nil,
                actions: [
                    RecordingSubtitleDetailActionPresentation(
                        kind: .addSubtitle,
                        title: L10n.localize("screenshot.record.detail.subtitle_action_add", comment: ""),
                        help: L10n.localize("screenshot.record.detail.subtitle_action_add_no_audio_help", comment: ""),
                        isEnabled: false
                    )
                ]
            )
        }

        switch record.subtitleStatus {
        case .none:
            return RecordingSubtitleDetailPresentation(
                sectionTitle: L10n.localize("screenshot.record.detail.subtitle_section_title", comment: ""),
                statusText: record.subtitleStatus.displayTitle,
                errorMessage: nil,
                actions: [
                    RecordingSubtitleDetailActionPresentation(
                        kind: .addSubtitle,
                        title: L10n.localize("screenshot.record.detail.subtitle_action_add", comment: ""),
                        help: L10n.localize("screenshot.record.detail.subtitle_action_add_help", comment: "")
                    )
                ]
            )
        case .generating:
            return RecordingSubtitleDetailPresentation(
                sectionTitle: L10n.localize("screenshot.record.detail.subtitle_section_title", comment: ""),
                statusText: record.subtitleStatus.displayTitle,
                errorMessage: nil,
                actions: [
                    RecordingSubtitleDetailActionPresentation(
                        kind: .progress,
                        title: L10n.localize("screenshot.record.detail.subtitle_action_generating", comment: ""),
                        help: L10n.localize("screenshot.record.detail.subtitle_action_generating_help", comment: ""),
                        isEnabled: false,
                        showsProgress: true
                    )
                ]
            )
        case .draftReady:
            return RecordingSubtitleDetailPresentation(
                sectionTitle: L10n.localize("screenshot.record.detail.subtitle_section_title", comment: ""),
                statusText: record.subtitleStatus.displayTitle,
                errorMessage: nil,
                actions: [
                    RecordingSubtitleDetailActionPresentation(
                        kind: .openEditor,
                        title: L10n.localize("screenshot.record.detail.subtitle_action_view_edit", comment: ""),
                        help: L10n.localize("screenshot.record.detail.subtitle_action_view_edit_help", comment: "")
                    ),
                    RecordingSubtitleDetailActionPresentation(
                        kind: .burn,
                        title: L10n.localize("screenshot.record.detail.subtitle_action_burn", comment: ""),
                        help: L10n.localize("screenshot.record.detail.subtitle_action_burn_help", comment: "")
                    )
                ]
            )
        case .burning:
            return RecordingSubtitleDetailPresentation(
                sectionTitle: L10n.localize("screenshot.record.detail.subtitle_section_title", comment: ""),
                statusText: record.subtitleStatus.displayTitle,
                errorMessage: nil,
                actions: [
                    RecordingSubtitleDetailActionPresentation(
                        kind: .progress,
                        title: L10n.localize("screenshot.record.detail.subtitle_action_burning", comment: ""),
                        help: L10n.localize("screenshot.record.detail.subtitle_action_burning_help", comment: ""),
                        isEnabled: false,
                        showsProgress: true
                    )
                ]
            )
        case .burned:
            return RecordingSubtitleDetailPresentation(
                sectionTitle: L10n.localize("screenshot.record.detail.subtitle_section_title", comment: ""),
                statusText: record.subtitleStatus.displayTitle,
                errorMessage: nil,
                actions: [
                    RecordingSubtitleDetailActionPresentation(
                        kind: .openSubtitledVideo,
                        title: L10n.localize("screenshot.record.detail.subtitle_action_open_subtitled_video", comment: ""),
                        help: L10n.localize("screenshot.record.detail.subtitle_action_open_subtitled_video_help", comment: "")
                    ),
                    RecordingSubtitleDetailActionPresentation(
                        kind: .openOriginalVideo,
                        title: L10n.localize("screenshot.record.detail.subtitle_action_open_original_video", comment: ""),
                        help: L10n.localize("screenshot.record.detail.subtitle_action_open_original_video_help", comment: "")
                    ),
                    RecordingSubtitleDetailActionPresentation(
                        kind: .openEditor,
                        title: L10n.localize("screenshot.record.detail.subtitle_action_view_edit", comment: ""),
                        help: L10n.localize("screenshot.record.detail.subtitle_action_view_edit_help", comment: "")
                    )
                ]
            )
        case .failed:
            return RecordingSubtitleDetailPresentation(
                sectionTitle: L10n.localize("screenshot.record.detail.subtitle_section_title", comment: ""),
                statusText: record.subtitleStatus.displayTitle,
                errorMessage: record.subtitleErrorMessage,
                actions: [
                    RecordingSubtitleDetailActionPresentation(
                        kind: .retry,
                        title: L10n.localize("screenshot.record.detail.subtitle_action_retry", comment: ""),
                        help: L10n.localize("screenshot.record.detail.subtitle_action_retry_help", comment: "")
                    )
                ]
            )
        }
    }
}

struct ScreenshotRecordDetailView: View {
    let initialRecord: MediaRecord
    @ObservedObject var viewModel: ScreenshotRecordViewModel
    let onClose: () -> Void

    @State private var escapeMonitor: Any?
    @State private var showBurnConfirm = false

    private var record: MediaRecord {
        viewModel.records.first(where: { $0.id == initialRecord.id }) ?? initialRecord
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 960, height: 720)
        .background(AppTheme.ColorToken.pageBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 8)
        .onExitCommand(perform: onClose)
        .onAppear { attachEscapeMonitorIfNeeded() }
        .onDisappear { detachEscapeMonitor() }
        .actionFeedbackOverlay(
            message: viewModel.lastActionMessage,
            error: viewModel.lastError,
            onDismiss: viewModel.clearFeedback
        )
        .alert(L10n.localize("screenshot.record.detail.burn_confirm_title", comment: ""), isPresented: $showBurnConfirm) {
            Button(L10n.localize("screenshot.record.detail.burn_confirm_cancel", comment: ""), role: .cancel) {}
            Button(L10n.localize("screenshot.record.detail.burn_confirm_action", comment: "")) {
                viewModel.startSubtitleBurn(id: record.id)
            }
        } message: {
            Text(L10n.localize("screenshot.record.detail.burn_confirm_message", comment: ""))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            if record.mediaType == .screenRecording {
                Text(L10n.localize("screenshot.record.detail.header_screen_recording", comment: ""))
                    .font(.system(size: 16, weight: .semibold))
            } else {
                Text(L10n.localize("screenshot.record.detail.header_screenshot", comment: ""))
                    .font(.system(size: 16, weight: .semibold))
            }
            Spacer()
            Button(action: { onClose() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help(L10n.localize("screenshot.record.detail.action_close_help", comment: ""))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Content

    private var content: some View {
        HStack(spacing: 0) {
            mediaPanel
            Divider()
            infoPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mediaPanel: some View {
        Group {
            if record.mediaType == .screenRecording {
                videoPanel
            } else {
                imagePanel
            }
        }
    }

    private var videoPanel: some View {
        GeometryReader { proxy in
            ZStack {
                AppTheme.ColorToken.controlBackground.opacity(0.22)
                if let videoPath = record.primaryVideoPath {
                    MediaVideoPlayerView(url: URL(fileURLWithPath: videoPath))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText.opacity(0.3))
                        Text(L10n.localize("screenshot.record.detail.media_unavailable_video", comment: ""))
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
    }

    private var imagePanel: some View {
        GeometryReader { proxy in
            ZStack {
                AppTheme.ColorToken.controlBackground.opacity(0.22)
                if let image = viewModel.loadImage(for: record) {
                    ScrollView(.vertical) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: max(1, proxy.size.width - 32))
                            .padding(16)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText.opacity(0.3))
                        Text(L10n.localize("screenshot.record.detail.media_unavailable_image", comment: ""))
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            metaSection
            if RecordingSubtitleDetailPresentation.make(for: record) != nil {
                subtitleSection
            }
            ocrSection
            translatedSection
            Spacer(minLength: 0)
            actionButtons
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
        .frame(maxHeight: .infinity)
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.localize("screenshot.record.detail.meta_title", comment: ""))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)

            metaRow(
                label: L10n.localize("screenshot.record.detail.meta_label_time", comment: ""),
                value: ScreenshotRecordView.dateFormatter.string(from: record.createdAt)
            )
            if record.mediaType == .screenRecording {
                metaRow(
                    label: L10n.localize("screenshot.record.detail.meta_label_duration", comment: ""),
                    value: formatDuration(record.durationMs)
                )
                metaRow(
                    label: L10n.localize("screenshot.record.detail.meta_label_resolution", comment: ""),
                    value: formatResolution(record.width, record.height)
                )
                metaRow(
                    label: L10n.localize("screenshot.record.detail.meta_label_file_size", comment: ""),
                    value: formatFileSize(record.fileSizeBytes)
                )
                metaRow(
                    label: L10n.localize("screenshot.record.detail.meta_label_audio", comment: ""),
                    value: audioModeTitle(record.audioMode)
                )
            } else {
                metaRow(
                    label: L10n.localize("screenshot.record.detail.meta_label_char_count", comment: ""),
                    value: "\(record.charCount)"
                )
            }
            metaRow(
                label: L10n.localize("screenshot.record.detail.meta_label_favorite", comment: ""),
                value: record.isFavorited
                    ? L10n.localize("screenshot.record.detail.meta_value_favorited", comment: "")
                    : L10n.localize("screenshot.record.detail.meta_value_unfavorited", comment: "")
            )
        }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
        }
    }

    // MARK: - 字幕区域

    @ViewBuilder
    private var subtitleSection: some View {
        if let presentation = RecordingSubtitleDetailPresentation.make(for: record) {
            VStack(alignment: .leading, spacing: 8) {
                Text(presentation.sectionTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                metaRow(label: L10n.localize("screenshot.record.detail.status_label", comment: ""), value: presentation.statusText)
                if let errorMessage = presentation.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .lineLimit(2)
                }
                subtitleActions(presentation)
            }
        }
    }

    @ViewBuilder
    private func subtitleActions(_ presentation: RecordingSubtitleDetailPresentation) -> some View {
        let usesVerticalLayout = presentation.actions.contains { $0.kind == .openSubtitledVideo }
        if usesVerticalLayout {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(presentation.actions) { action in
                    subtitleActionView(action)
                }
            }
        } else {
            HStack(spacing: 6) {
                ForEach(presentation.actions) { action in
                    subtitleActionView(action)
                }
            }
        }
    }

    @ViewBuilder
    private func subtitleActionView(_ action: RecordingSubtitleDetailActionPresentation) -> some View {
        if action.showsProgress {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(action.title)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            .help(action.help)
        } else {
            Button(action.title) {
                performSubtitleAction(action.kind)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!action.isEnabled)
            .help(action.help)
        }
    }

    private func performSubtitleAction(_ kind: RecordingSubtitleDetailActionPresentation.Kind) {
        switch kind {
        case .addSubtitle:
            viewModel.addSubtitle(id: record.id)
        case .progress:
            break
        case .openEditor:
            viewModel.openSubtitleEditor(id: record.id)
        case .burn:
            showBurnConfirm = true
        case .openSubtitledVideo:
            viewModel.openSubtitledVideo(id: record.id)
        case .openOriginalVideo:
            viewModel.openOriginalVideo(id: record.id)
        case .retry:
            viewModel.retrySubtitle(id: record.id)
        }
    }

    private var ocrSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.localize("screenshot.record.detail.ocr_title", comment: ""))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            if record.ocrText.isEmpty {
                Text(L10n.localize("screenshot.record.detail.ocr_no_text", comment: ""))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText.opacity(0.6))
            } else {
                ScrollView {
                    Text(record.ocrText)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .layoutPriority(1)
    }

    private var translatedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let translated = record.translatedText, !translated.isEmpty {
                Text(L10n.localize("screenshot.record.detail.translation_title", comment: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                ScrollView {
                    Text(translated)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 100)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            if record.mediaType == .screenRecording {
                recordActionIcon(
                    "arrow.up.right.square",
                    help: L10n.localize("screenshot.record.action.open_file_help", comment: "")
                ) {
                    viewModel.openFile(id: record.id)
                }
                recordActionIcon(
                    "doc.on.doc",
                    help: L10n.localize("screenshot.record.action.copy_file_help", comment: "")
                ) {
                    viewModel.copyFile(id: record.id)
                }
                recordActionIcon(
                    "folder",
                    help: L10n.localize("screenshot.record.action.reveal_in_finder_help", comment: "")
                ) {
                    viewModel.revealInFinder(id: record.id)
                }
            } else {
                recordActionIcon(
                    "photo.on.rectangle",
                    help: L10n.localize("screenshot.record.action.copy_image_help", comment: "")
                ) {
                    viewModel.copyImage(id: record.id)
                }
                if !record.ocrText.isEmpty {
                    recordActionIcon(
                        "doc.on.doc",
                        help: L10n.localize("screenshot.record.action.copy_text_help", comment: "")
                    ) {
                        viewModel.copyText(id: record.id)
                    }
                }
            }
            recordActionIcon(
                record.isFavorited ? "star.fill" : "star",
                help: record.isFavorited
                    ? L10n.localize("screenshot.record.action.unfavorite_help", comment: "")
                    : L10n.localize("screenshot.record.action.favorite_help", comment: ""),
                tint: record.isFavorited ? .yellow : nil
            ) {
                viewModel.toggleFavorite(id: record.id)
            }
            recordActionIcon(
                "trash",
                help: L10n.localize("screenshot.record.action.delete_help", comment: ""),
                tint: .red
            ) {
                viewModel.deleteRecord(id: record.id)
                onClose()
            }
            Spacer(minLength: 0)
        }
    }

    private func recordActionIcon(
        _ systemName: String,
        help: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14))
                .foregroundStyle(tint ?? AppTheme.ColorToken.secondaryText)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func formatDuration(_ durationMs: Int) -> String {
        let totalSeconds = max(0, durationMs / 1_000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatResolution(_ width: Int, _ height: Int) -> String {
        guard width > 0, height > 0 else {
            return L10n.localize("screenshot.record.format.unknown_resolution", comment: "")
        }
        return "\(width)×\(height)"
    }

    private func formatFileSize(_ bytes: Int) -> String {
        guard bytes > 0 else {
            return L10n.localize("screenshot.record.format.unknown_file_size", comment: "")
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func audioModeTitle(_ audioMode: MediaAudioMode) -> String {
        switch audioMode {
        case .none:
            return L10n.localize("screenshot.record.audio.no_sound", comment: "")
        case .microphone:
            return L10n.localize("screenshot.record.audio.microphone", comment: "")
        }
    }

    private func attachEscapeMonitorIfNeeded() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == Self.escapeKeyCode else {
                return event
            }
            onClose()
            return nil
        }
    }

    private func detachEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    private static let escapeKeyCode: UInt16 = 53
}
