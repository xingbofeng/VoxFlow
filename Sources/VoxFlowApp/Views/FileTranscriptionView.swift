import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct FileTranscriptionView: View {
    @ObservedObject var viewModel: FileTranscriptionViewModel
    let onSaveAsNote: (String) -> Void
    @StateObject private var playback = FilePlaybackController()
    @State private var isImporterPresented = false
    @State private var deletingJobID: String?
    @State private var selectedJobID: String?
    @State private var expandedDiagnosticJobIDs: Set<String> = []
    @State private var translatingJobID: String?
    @State private var comparisonJobIDs: Set<String> = []

    init(
        viewModel: FileTranscriptionViewModel,
        onSaveAsNote: @escaping (String) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onSaveAsNote = onSaveAsNote
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                header
                compactUploadArea
                mainContent
                statusBar
            }
            .frame(maxWidth: 1320, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.vertical, 34)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(AppTheme.ColorToken.pageBackground)
        .tint(AppTheme.ColorToken.accent)
        .actionFeedbackOverlay(
            message: viewModel.lastActionMessage,
            error: viewModel.lastError,
            tone: viewModel.lastActionTone,
            onDismiss: viewModel.clearFeedback
        )
        .confirmationDialog(
            L10n.localize("transcribe.delete.confirm_title", comment: "Delete transcription task confirmation title"),
            isPresented: Binding(
                get: { deletingJobID != nil },
                set: { if !$0 { deletingJobID = nil } }
            )
        ) {
            Button(L10n.localize("transcribe.action.delete", comment: "Delete action"), role: .destructive) {
                deleteCurrentJob()
            }
            Button(L10n.localize("transcribe.action.cancel", comment: "Cancel action"), role: .cancel) {
                deletingJobID = nil
            }
        } message: {
            Text(L10n.localize("transcribe.delete.confirm_message", comment: "Delete transcription task confirmation message"))
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.audio, .movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            do {
                _ = try viewModel.enqueueFiles(result.get())
            } catch {
                viewModel.report(error: error)
            }
        }
        .onDisappear {
            playback.stop()
        }
        .onAppear {
            if selectedJobID == nil {
                selectedJobID = viewModel.jobs.first?.id
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.grid) {
            VStack(alignment: .leading, spacing: 5) {
                Label(
                    L10n.localize("transcribe.title", comment: "File transcription title"),
                    systemImage: "waveform.path.badge.plus"
                )
                .font(.system(size: 22, weight: .semibold))
                Text(L10n.localize("transcribe.header.subtitle", comment: "File transcription subtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            Button {
                isImporterPresented = true
            } label: {
                Label(
                    L10n.localize("transcribe.action.select_file", comment: "Select file action"),
                    systemImage: "plus"
                )
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Compact upload area

    private var compactUploadArea: some View {
        Button {
            isImporterPresented = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.accent.opacity(0.72))
                Text(L10n.localize("transcribe.drop_area.placeholder", comment: "Drag files placeholder"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                Text(L10n.localize("transcribe.drop_area.supported_formats", comment: "Supported file formats"))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 118)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(AppTheme.ColorToken.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(
                    AppTheme.ColorToken.accent.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url {
                        Task { @MainActor in
                            do {
                                let jobs = try viewModel.enqueueFiles([url], startImmediatelyWhenIdle: true)
                                if selectedJobID == nil {
                                    selectedJobID = jobs.first?.id
                                }
                            } catch {
                                viewModel.report(error: error)
                            }
                        }
                    }
                }
            }
            return true
        }
    }

    // MARK: - Main content (queue + results)

    private var mainContent: some View {
        HStack(alignment: .top, spacing: 0) {
            queuePanel
                .frame(width: 380)
            Divider()
                .padding(.vertical, 4)
            resultsPanel
        }
        .padding(14)
        .frame(minHeight: 480, maxHeight: 540)
        .appPanel(cornerRadius: 16)
    }

    private var queuePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.localize("transcribe.queue.title", comment: "Transcription queue title"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)

            ScrollView {
                LazyVStack(spacing: AppTheme.Spacing.grid) {
                    if viewModel.jobs.isEmpty {
                        Text(L10n.localize(
                            "transcribe.queue.empty",
                            comment: "Empty queue placeholder"
                        ))
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                    }
                    ForEach(viewModel.jobs, id: \.id) { job in
                        queueCard(job)
                    }
                }
            }
        }
        .padding(.trailing, 14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func queueCard(_ job: TranscriptionJobRecord) -> some View {
        let isSelected = selectedJobID == job.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: statusIcon(job))
                    .foregroundStyle(statusColor(job))
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.sourceFileName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(FileTranscriptionPresentation.metadataLine(for: job))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                Spacer()
            }

            Label(viewModel.statusTitle(for: job), systemImage: statusIcon(job))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(statusColor(job))

            if job.status == TranscriptionJobStatus.running.rawValue,
               job.segmentCount > 0 {
                Text(L10n.format(
                    "transcribe.queue.processing_segment",
                    comment: "Processing N of M segment",
                    job.segmentCompleted + 1,
                    job.segmentCount
                ))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.ColorToken.accentDark)
            }

            ProgressView(value: job.progress)
                .opacity(job.status == TranscriptionJobStatus.running.rawValue ? 1 : 0.55)

            advancedDetailsToggle(job)

            HStack(spacing: 6) {
                queueActionButton(job)
                if job.status == TranscriptionJobStatus.running.rawValue {
                    Button {
                        viewModel.cancel(jobID: job.id)
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .help(L10n.localize("transcribe.action.cancel_job", comment: "Cancel transcription job"))
                }
                Button {
                    deletingJobID = job.id
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .help(L10n.localize("transcribe.action.delete_job", comment: "Delete transcription job"))
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .fill(isSelected ? AppTheme.ColorToken.accent.opacity(0.08) : AppTheme.ColorToken.panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(
                    isSelected ? AppTheme.ColorToken.accent.opacity(0.35) : Color.clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedJobID = job.id
        }
    }

    @ViewBuilder
    private func advancedDetailsToggle(_ job: TranscriptionJobRecord) -> some View {
        let hasDiagnostic = job.providerMode != nil
            || job.partialFailureSummary != nil
            || job.status == TranscriptionJobStatus.failed.rawValue
            || job.status == TranscriptionJobStatus.partiallyFailed.rawValue
            || job.status == TranscriptionJobStatus.interrupted.rawValue
        if hasDiagnostic {
            DisclosureGroup(isExpanded: Binding(
                get: { expandedDiagnosticJobIDs.contains(job.id) },
                set: { isExpanded in
                    if isExpanded {
                        expandedDiagnosticJobIDs.insert(job.id)
                    } else {
                        expandedDiagnosticJobIDs.remove(job.id)
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.localize(
                        "transcribe.diagnostic.summary",
                        comment: "Diagnostic summary line"
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)

                    if let mode = job.providerMode {
                        Text("• " + FileTranscriptionPresentation.providerModeLabel(mode))
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    }
                    if let summary = job.partialFailureSummary {
                        Text("• \(summary)")
                            .font(.system(size: 11))
                            .foregroundStyle(.red.opacity(0.85))
                    }
                    if let error = job.errorMessage, !error.isEmpty {
                        Text("• \(error)")
                            .font(.system(size: 11))
                            .foregroundStyle(.red.opacity(0.85))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text(L10n.localize(
                    "transcribe.diagnostic.toggle",
                    comment: "Advanced details toggle"
                ))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func queueActionButton(_ job: TranscriptionJobRecord) -> some View {
        if job.status == TranscriptionJobStatus.running.rawValue {
            Button {
                playback.toggle(job: job)
            } label: {
                Image(systemName: playback.isPlaying(jobID: job.id) ? "pause.fill" : "play.fill")
            }
            .disabled(!FileManager.default.fileExists(atPath: job.sourceFilePath))
            .help(L10n.localize("transcribe.action.play", comment: "Play"))
        } else {
            Button {
                start(job)
            } label: {
                Image(systemName: job.status == TranscriptionJobStatus.queued.rawValue
                    ? "waveform" : "arrow.clockwise")
            }
            .help(viewModel.primaryActionTitle(for: job))
        }
    }

    // MARK: - Results panel

    private var resultsPanel: some View {
        let selectedJob = viewModel.jobs.first { $0.id == selectedJobID }
            ?? viewModel.jobs.first
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.localize("transcribe.results.title", comment: "Results panel title"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                    if let job = selectedJob {
                        Text(resultSubtitle(for: job))
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let job = selectedJob {
                    resultsActions(job)
                }
            }

            if let job = selectedJob {
                resultTextSurface(job)
            } else {
                Text(L10n.localize(
                    "transcribe.results.empty",
                    comment: "No result yet placeholder"
                ))
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(.leading, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func resultTextSurface(_ job: TranscriptionJobRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let text = job.finalText, !text.isEmpty {
                        if comparisonJobIDs.contains(job.id),
                           let translated = job.translatedText,
                           !translated.isEmpty {
                            translationComparison(original: text, translated: translated)
                        } else {
                        Text(text)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .foregroundStyle(AppTheme.ColorToken.primaryText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text(L10n.localize(
                            "transcribe.results.empty",
                            comment: "No result yet placeholder"
                        ))
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !comparisonJobIDs.contains(job.id),
                       let translated = job.translatedText,
                       !translated.isEmpty {
                        Divider()
                        Text(L10n.localize(
                            "transcribe.results.translation_section",
                            comment: "Translation section header"
                        ))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        Text(translated)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .foregroundStyle(AppTheme.ColorToken.primaryText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appControlSurface(cornerRadius: AppTheme.Radius.card)

            advancedDetailsToggle(job)
        }
    }

    private func translationComparison(original: String, translated: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            comparisonColumn(
                title: L10n.localize("transcribe.export.original_section", comment: "Original text section header"),
                text: original
            )
            Divider()
            comparisonColumn(
                title: L10n.localize("transcribe.results.translation_section", comment: "Translation section header"),
                text: translated
            )
        }
    }

    private func comparisonColumn(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            Text(text)
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(AppTheme.ColorToken.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func resultsActions(_ job: TranscriptionJobRecord) -> some View {
        HStack(spacing: 6) {
            Button {
                do {
                    try viewModel.copyResult(jobID: job.id)
                } catch {
                    viewModel.report(error: error)
                }
            } label: {
                Label(
                    L10n.localize("transcribe.action.copy", comment: "Copy transcription result"),
                    systemImage: "doc.on.doc"
                )
            }
            .disabled(job.finalText?.isEmpty != false)
            .help(L10n.localize("transcribe.action.copy", comment: "Copy transcription result"))

            Button {
                do {
                    let note = try viewModel.saveAsNote(jobID: job.id)
                    onSaveAsNote(note.id)
                } catch {
                    viewModel.report(error: error)
                }
            } label: {
                Label(
                    L10n.localize("transcribe.action.save_as_note", comment: "Save as note"),
                    systemImage: "note.text"
                )
            }
            .disabled(job.finalText?.isEmpty != false)
            .help(L10n.localize("transcribe.action.save_as_note", comment: "Save as note"))

            translateButton(job)

            Button {
                saveJobToFile(job)
            } label: {
                Label(
                    L10n.localize("notes.action.save", comment: "Save"),
                    systemImage: "square.and.arrow.down"
                )
            }
            .disabled(job.finalText?.isEmpty != false)
            .help(L10n.localize("notes.action.save", comment: "Save"))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @ViewBuilder
    private func translateButton(_ job: TranscriptionJobRecord) -> some View {
        let canTranslate = job.finalText?.isEmpty == false
            && job.translationStatus != TranslationStatus.running.rawValue
        let isTranslating = job.translationStatus == TranslationStatus.running.rawValue
        let hasTranslation = job.translatedText?.isEmpty == false
        let isShowingComparison = comparisonJobIDs.contains(job.id)
        Button {
            if hasTranslation {
                if isShowingComparison {
                    comparisonJobIDs.remove(job.id)
                } else {
                    comparisonJobIDs.insert(job.id)
                }
                return
            }
            Task {
                translatingJobID = job.id
                await viewModel.translateFullText(jobID: job.id)
                if viewModel.jobs.first(where: { $0.id == job.id })?.translatedText?.isEmpty == false {
                    comparisonJobIDs.insert(job.id)
                }
                translatingJobID = nil
            }
        } label: {
            if isTranslating {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label(
                    isShowingComparison
                        ? L10n.localize("transcribe.export.original_section", comment: "Original text section header")
                        : L10n.localize("transcribe.action.translate_full_text", comment: "Translate full text"),
                    systemImage: "character.bubble"
                )
            }
        }
        .disabled(!canTranslate)
        .help(L10n.localize("transcribe.action.translate_full_text", comment: "Translate full text"))
    }

    private func saveJobToFile(_ job: TranscriptionJobRecord) {
        do {
            let format: FileTranscriptionExportFormat = job.translatedText?.isEmpty == false
                ? .bilingualMarkdown
                : .markdown
            let output = try viewModel.export(jobID: job.id, format: format)
            let panel = NSSavePanel()
            panel.title = L10n.localize("notes.action.save", comment: "Save")
            panel.nameFieldStringValue = sanitizedFileName("\(job.sourceFileName).md")
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try output.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            viewModel.report(error: error)
        }
    }

    private func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        return name.components(separatedBy: invalid).joined(separator: "-")
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            let running = viewModel.jobs.first { $0.status == TranscriptionJobStatus.running.rawValue }
            if let running {
                Label(
                    L10n.format(
                        "transcribe.status_bar.running",
                        comment: "Status bar running indicator",
                        running.segmentCompleted,
                        max(running.segmentCount, running.segmentCompleted)
                    ),
                    systemImage: "waveform"
                )
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.accentDark)
                ProgressView(value: running.progress)
                    .frame(maxWidth: 160)
            } else {
                Label(
                    L10n.localize("transcribe.status_bar.idle", comment: "Status bar idle"),
                    systemImage: "circle.dashed"
                )
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            Text(L10n.format(
                "transcribe.status_bar.jobs_count",
                comment: "Jobs count summary",
                viewModel.jobs.count
            ))
            .font(.system(size: 12))
            .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(AppTheme.ColorToken.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
    }

    private func resultSubtitle(for job: TranscriptionJobRecord) -> String {
        let metadata = FileTranscriptionPresentation.metadataLine(for: job)
        let status = viewModel.statusTitle(for: job)
        guard !metadata.isEmpty else { return status }
        return "\(status) · \(metadata)"
    }

    // MARK: - Actions

    private func deleteCurrentJob() {
        guard let deletingJobID else { return }
        if playback.isPlaying(jobID: deletingJobID) {
            playback.stop()
        }
        viewModel.delete(jobID: deletingJobID)
        if selectedJobID == deletingJobID {
            selectedJobID = viewModel.jobs.first?.id
        }
        self.deletingJobID = nil
    }

    private func start(_ job: TranscriptionJobRecord) {
        if job.status == TranscriptionJobStatus.queued.rawValue {
            viewModel.start(jobID: job.id)
        } else {
            Task {
                await viewModel.retry(jobID: job.id)
            }
        }
    }

    // MARK: - Status styling

    private func statusIcon(_ job: TranscriptionJobRecord) -> String {
        FileTranscriptionPresentation.statusIcon(for: job)
    }

    private func statusColor(_ job: TranscriptionJobRecord) -> Color {
        FileTranscriptionPresentation.statusColor(for: job)
    }
}

/// 可测试的文件转写 presentation 辅助。将 status→icon/color、provider mode label、metadata line 等
/// 纯展示逻辑从 View 中抽离，便于在测试中验证。
enum FileTranscriptionPresentation {
    static func statusIcon(for job: TranscriptionJobRecord) -> String {
        switch TranscriptionJobStatus(rawValue: job.status) {
        case .queued: return "clock"
        case .running: return "waveform"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        case .partiallyFailed: return "exclamationmark.circle.fill"
        case .interrupted: return "pause.circle"
        case nil: return "questionmark.circle"
        }
    }

    static func statusColor(for job: TranscriptionJobRecord) -> Color {
        switch TranscriptionJobStatus(rawValue: job.status) {
        case .completed:
            return AppTheme.ColorToken.accent
        case .failed, .partiallyFailed:
            return .red
        case .running:
            return AppTheme.ColorToken.accentDark
        case .interrupted:
            return .orange
        default:
            return AppTheme.ColorToken.secondaryText
        }
    }

    static func metadataLine(for job: TranscriptionJobRecord) -> String {
        var parts: [String] = []
        if job.durationMS > 0 {
            parts.append(durationLabel(job.durationMS))
        }
        let format = fileExtension(from: job.sourceFileName)
        if !format.isEmpty {
            parts.append(format.uppercased())
        }
        if job.segmentCount > 0 {
            parts.append("\(job.segmentCount) " + L10n.localize(
                "transcribe.metadata.segments_unit",
                comment: "Segments unit suffix"
            ))
        }
        return parts.joined(separator: " · ")
    }

    static func providerModeLabel(_ modeRaw: String) -> String {
        guard let mode = TranscriptionProviderMode(rawValue: modeRaw) else { return modeRaw }
        switch mode {
        case .nativeFile:
            return L10n.localize("transcribe.provider_mode.native_file", comment: "Native file mode")
        case .segmentedCompatible:
            return L10n.localize("transcribe.provider_mode.segmented", comment: "Segmented mode")
        case .notRecommendedForLongFiles:
            return L10n.localize("transcribe.provider_mode.not_recommended", comment: "Not recommended for long files")
        }
    }

    static func durationLabel(_ durationMS: Int) -> String {
        let totalSeconds = max(0, durationMS / 1_000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes):\(String(format: "%02d", seconds))"
        }
        return "\(seconds)s"
    }

    static func fileExtension(from fileName: String) -> String {
        guard let dot = fileName.lastIndex(of: ".") else { return "" }
        return String(fileName[fileName.index(after: dot)...]).lowercased()
    }
}

@MainActor
private final class FilePlaybackController: ObservableObject {
    @Published private(set) var playingJobID: String?
    private var player: AVPlayer?

    func toggle(job: TranscriptionJobRecord) {
        if playingJobID == job.id {
            player?.pause()
            playingJobID = nil
            return
        }

        stop()
        let player = AVPlayer(url: URL(fileURLWithPath: job.sourceFilePath))
        self.player = player
        playingJobID = job.id
        player.play()
    }

    func isPlaying(jobID: String) -> Bool {
        playingJobID == jobID
    }

    func stop() {
        player?.pause()
        player = nil
        playingJobID = nil
    }
}

/// 简易两列等宽布局，避免依赖 `HGrid` 的可用性差异。
struct HGrid<Content: View>: View {
    let spacing: CGFloat
    let content: () -> Content

    init(spacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        HStack(spacing: spacing) {
            content()
        }
    }
}
