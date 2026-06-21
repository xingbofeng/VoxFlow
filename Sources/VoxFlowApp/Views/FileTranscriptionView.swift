import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct FileTranscriptionView: View {
    @ObservedObject var viewModel: FileTranscriptionViewModel
    @StateObject private var playback = FilePlaybackController()
    @State private var isImporterPresented = false

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
                Label("文件转写", systemImage: "waveform.path.badge.plus")
                    .font(.system(size: 24, weight: .semibold))
                Text("选择音频或视频，开始转写后可直接播放和复制结果。")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            Button {
                isImporterPresented = true
            } label: {
                Label("选择文件", systemImage: "plus")
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
                    Text("拖入音频或视频文件")
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
                    playback.isPlaying(jobID: job.id) ? "暂停" : "播放",
                    systemImage: playback.isPlaying(jobID: job.id) ? "pause.fill" : "play.fill"
                )
            }
            .disabled(!FileManager.default.fileExists(atPath: job.sourceFilePath))

            if job.status == TranscriptionJobStatus.running.rawValue {
                Button(role: .destructive) {
                    viewModel.cancel(jobID: job.id)
                } label: {
                    Label("取消", systemImage: "stop.fill")
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
                Label("复制", systemImage: "doc.on.doc")
            }
            .disabled(job.finalText?.isEmpty != false)
        }
        .buttonStyle(.bordered)
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
