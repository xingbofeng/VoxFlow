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
                sectionTitle: "字幕",
                statusText: "无麦克风音频",
                errorMessage: nil,
                actions: [
                    RecordingSubtitleDetailActionPresentation(
                        kind: .addSubtitle,
                        title: "添加字幕",
                        help: "这段录屏没有麦克风音频，无法添加字幕",
                        isEnabled: false
                    )
                ]
            )
        }

        switch record.subtitleStatus {
        case .none:
            return RecordingSubtitleDetailPresentation(
                sectionTitle: "字幕",
                statusText: record.subtitleStatus.displayTitle,
                errorMessage: nil,
                actions: [
                    RecordingSubtitleDetailActionPresentation(
                        kind: .addSubtitle,
                        title: "添加字幕",
                        help: "添加字幕"
                    )
                ]
            )
        case .generating:
            return RecordingSubtitleDetailPresentation(
                sectionTitle: "字幕",
                statusText: record.subtitleStatus.displayTitle,
                errorMessage: nil,
                actions: [
                    RecordingSubtitleDetailActionPresentation(
                        kind: .progress,
                        title: "生成中…",
                        help: "字幕生成中…",
                        isEnabled: false,
                        showsProgress: true
                    )
                ]
            )
        case .draftReady:
            return RecordingSubtitleDetailPresentation(
                sectionTitle: "字幕",
                statusText: record.subtitleStatus.displayTitle,
                errorMessage: nil,
                actions: [
                    RecordingSubtitleDetailActionPresentation(
                        kind: .openEditor,
                        title: "查看/编辑字幕",
                        help: "查看/编辑字幕"
                    ),
                    RecordingSubtitleDetailActionPresentation(
                        kind: .burn,
                        title: "烧录字幕",
                        help: "烧录字幕"
                    )
                ]
            )
        case .burning:
            return RecordingSubtitleDetailPresentation(
                sectionTitle: "字幕",
                statusText: record.subtitleStatus.displayTitle,
                errorMessage: nil,
                actions: [
                    RecordingSubtitleDetailActionPresentation(
                        kind: .progress,
                        title: "烧录中…",
                        help: "字幕烧录中…",
                        isEnabled: false,
                        showsProgress: true
                    )
                ]
            )
        case .burned:
            return RecordingSubtitleDetailPresentation(
                sectionTitle: "字幕",
                statusText: record.subtitleStatus.displayTitle,
                errorMessage: nil,
                actions: [
                    RecordingSubtitleDetailActionPresentation(
                        kind: .openSubtitledVideo,
                        title: "打开带字幕视频",
                        help: "打开带字幕视频"
                    ),
                    RecordingSubtitleDetailActionPresentation(
                        kind: .openOriginalVideo,
                        title: "查看原视频",
                        help: "查看原视频"
                    ),
                    RecordingSubtitleDetailActionPresentation(
                        kind: .openEditor,
                        title: "查看/编辑字幕",
                        help: "查看/编辑字幕"
                    )
                ]
            )
        case .failed:
            return RecordingSubtitleDetailPresentation(
                sectionTitle: "字幕",
                statusText: record.subtitleStatus.displayTitle,
                errorMessage: record.subtitleErrorMessage,
                actions: [
                    RecordingSubtitleDetailActionPresentation(
                        kind: .retry,
                        title: "重试",
                        help: "重试生成字幕"
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
        .alert("生成带字幕视频？", isPresented: $showBurnConfirm) {
            Button("取消", role: .cancel) {}
            Button("生成带字幕视频") {
                viewModel.startSubtitleBurn(id: record.id)
            }
        } message: {
            Text("将生成一个新的 mp4，原始录屏会保留。")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            if record.mediaType == .screenRecording {
                Text("录屏详情")
                    .font(.system(size: 16, weight: .semibold))
            } else {
                Text("截图详情")
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
            .help("关闭")
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
                        Text("视频不可用")
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
                        Text("图片不可用")
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
            Text("元信息")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)

            metaRow(label: "时间", value: ScreenshotRecordView.dateFormatter.string(from: record.createdAt))
            if record.mediaType == .screenRecording {
                metaRow(label: "时长", value: formatDuration(record.durationMs))
                metaRow(label: "分辨率", value: formatResolution(record.width, record.height))
                metaRow(label: "文件大小", value: formatFileSize(record.fileSizeBytes))
                metaRow(label: "声音", value: audioModeTitle(record.audioMode))
            } else {
                metaRow(label: "字数", value: "\(record.charCount)")
            }
            metaRow(label: "收藏", value: record.isFavorited ? "已收藏" : "未收藏")
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
                metaRow(label: "状态", value: presentation.statusText)
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
            Text("识别文字")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            if record.ocrText.isEmpty {
                Text("未识别到文字")
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
                Text("翻译")
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
                recordActionIcon("arrow.up.right.square", help: "打开文件") {
                    viewModel.openFile(id: record.id)
                }
                recordActionIcon("doc.on.doc", help: "复制文件") {
                    viewModel.copyFile(id: record.id)
                }
                recordActionIcon("folder", help: "在 Finder 中显示") {
                    viewModel.revealInFinder(id: record.id)
                }
            } else {
                recordActionIcon("photo.on.rectangle", help: "复制图片") {
                    viewModel.copyImage(id: record.id)
                }
                if !record.ocrText.isEmpty {
                    recordActionIcon("doc.on.doc", help: "复制文字") {
                        viewModel.copyText(id: record.id)
                    }
                }
            }
            recordActionIcon(
                record.isFavorited ? "star.fill" : "star",
                help: record.isFavorited ? "取消收藏" : "收藏",
                tint: record.isFavorited ? .yellow : nil
            ) {
                viewModel.toggleFavorite(id: record.id)
            }
            recordActionIcon("trash", help: "删除", tint: .red) {
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
        guard width > 0, height > 0 else { return "未知分辨率" }
        return "\(width)×\(height)"
    }

    private func formatFileSize(_ bytes: Int) -> String {
        guard bytes > 0 else { return "未知大小" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func audioModeTitle(_ audioMode: MediaAudioMode) -> String {
        switch audioMode {
        case .none:
            return "无声"
        case .microphone:
            return "麦克风"
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
