import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct FileTranscriptionView: View {
    @ObservedObject var viewModel: FileTranscriptionViewModel
    @StateObject private var playback = FilePlaybackController()
    @State private var isImporterPresented = false
    @State private var deletingJobID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            header
            dropArea

            ScrollView {
                LazyVStack(spacing: AppTheme.Spacing.grid) {
                    ForEach(viewModel.jobs, id: \.id) { job in
                        jobRow(job)
                    }
                }
            }

            Spacer()
        }
        .padding(AppTheme.Spacing.page)
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
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Label(L10n.localize("transcribe.title", comment: "File transcription title"), systemImage: "waveform.path.badge.plus")
                    .font(.system(size: 24, weight: .semibold))
                Text(L10n.localize("transcribe.header.subtitle", comment: "File transcription subtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            Button {
                isImporterPresented = true
            } label: {
                Label(L10n.localize("transcribe.action.select_file", comment: "Select file action"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var dropArea: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
            .fill(AppTheme.ColorToken.panelBackground)
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .stroke(
                        AppTheme.ColorToken.accent.opacity(0.22),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                    )
            }
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(AppTheme.ColorToken.accent.opacity(0.72))
                    Text(L10n.localize("transcribe.drop_area.placeholder", comment: "Drag files placeholder"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
            }
            .frame(height: 130)
            .shadow(color: AppTheme.ColorToken.accent.opacity(0.035), radius: 8, y: 3)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url {
                            Task { @MainActor in
                                do {
                                    try viewModel.enqueueFiles([url])
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

    private func jobRow(_ job: TranscriptionJobRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.sourceFileName)
                        .font(.system(size: 15, weight: .semibold))
                    Label(viewModel.statusTitle(for: job), systemImage: statusIcon(job))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(statusColor(job))
                }
                Spacer()
                actionButtons(job)
            }

            ProgressView(value: job.progress)
                .opacity(job.status == TranscriptionJobStatus.running.rawValue ? 1 : 0.55)

            if let finalText = job.finalText {
                Text(finalText)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .truncationMode(.head)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appControlSurface()
            }

            if let error = job.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .padding(AppTheme.Spacing.card)
        .appPanel()
    }

    private func actionButtons(_ job: TranscriptionJobRecord) -> some View {
        HStack(spacing: 8) {
            Button {
                playback.toggle(job: job)
            } label: {
                Label(
                    playback.isPlaying(jobID: job.id)
                        ? L10n.localize("transcribe.action.pause", comment: "Pause")
                        : L10n.localize("transcribe.action.play", comment: "Play"),
                    systemImage: playback.isPlaying(jobID: job.id) ? "pause.fill" : "play.fill"
                )
            }
            .disabled(!FileManager.default.fileExists(atPath: job.sourceFilePath))

            if job.status == TranscriptionJobStatus.running.rawValue {
                Button(role: .destructive) {
                    viewModel.cancel(jobID: job.id)
                } label: {
                    Label(L10n.localize("transcribe.action.cancel_job", comment: "Cancel transcription job"), systemImage: "stop.fill")
                }
            } else {
                Button {
                    start(job)
                } label: {
                    Label(
                        viewModel.primaryActionTitle(for: job),
                        systemImage: job.status == TranscriptionJobStatus.queued.rawValue
                            ? "waveform"
                            : "arrow.clockwise"
                    )
                }
            }

            Button {
                do {
                    try viewModel.copyResult(jobID: job.id)
                } catch {
                    viewModel.report(error: error)
                }
            } label: {
                Label(L10n.localize("transcribe.action.copy", comment: "Copy transcription result"), systemImage: "doc.on.doc")
            }
            .disabled(job.finalText?.isEmpty != false)

            Button(role: .destructive) {
                deletingJobID = job.id
            } label: {
                Label(L10n.localize("transcribe.action.delete_job", comment: "Delete transcription job"), systemImage: "trash")
            }
        }
        .buttonStyle(.bordered)
    }

    private func deleteCurrentJob() {
        guard let deletingJobID else {
            return
        }
        if playback.isPlaying(jobID: deletingJobID) {
            playback.stop()
        }
        viewModel.delete(jobID: deletingJobID)
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

    private func statusIcon(_ job: TranscriptionJobRecord) -> String {
        switch TranscriptionJobStatus(rawValue: job.status) {
        case .queued: return "clock"
        case .running: return "waveform"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        case nil: return "questionmark.circle"
        }
    }

    private func statusColor(_ job: TranscriptionJobRecord) -> Color {
        switch TranscriptionJobStatus(rawValue: job.status) {
        case .completed:
            return AppTheme.ColorToken.accent
        case .failed:
            return .red
        case .running:
            return AppTheme.ColorToken.accentDark
        default:
            return AppTheme.ColorToken.secondaryText
        }
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
