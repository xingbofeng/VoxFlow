// DictusApp/Views/HomeView.swift adapted for Mashangxie branding/provider adapter.
// Home dashboard showing model status, last transcription, and test dictation link.
import Shared
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var coordinator: DictationCoordinator
    @ObservedObject var modelManager: ModelManager
    @State private var showCopiedFeedback = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            logoSection
            modelStatusCard

            if let result = coordinator.lastResult {
                transcriptionCard(result: result)
            }

            if modelManager.activeModelStatus?.isReady == true {
                testDictationLink
            }

            Spacer()
        }
        .padding()
        .background(Color.dictusBackground.ignoresSafeArea())
        .onAppear {
            modelManager.loadState()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DictusOnboardingCompleted"))) { _ in
            modelManager.loadState()
        }
    }

    // MARK: - Logo Section

    private var logoSection: some View {
        VStack(spacing: 8) {
            BrandWaveform(maxHeight: 84, isProcessing: true)
                .opacity(0.7)
                .padding(.top, 8)
            Text(L10n.t("app.home.brand"))
                .font(.dictusHeading)
                .foregroundColor(.dictusAccent)
            Text(L10n.t("app.home.tagline"))
                .font(.dictusCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Model Status Card

    private var modelStatusCard: some View {
        Group {
            if let status = modelManager.activeModelStatus {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("app.home.active_model"))
                            .font(.dictusCaption)
                            .foregroundColor(.secondary)
                        Text(status.info.displayName)
                            .font(.dictusSubheading)
                        statusText(status)
                            .font(.dictusCaption)
                            .foregroundColor(statusTextColor(status))
                    }
                    Spacer()
                    statusIcon(status)
                        .font(.title2)
                        .foregroundColor(statusIconColor(status))
                }
                .padding()
                .dictusGlass()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.dictusAccent)
                    Text(L10n.t("app.home.download_model"))
                        .font(.dictusSubheading)
                        .multilineTextAlignment(.center)
                    Text(L10n.t("app.home.download_model_hint"))
                        .font(.dictusCaption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .dictusGlass()
            }
        }
    }

    @ViewBuilder
    private func statusText(_ status: ActiveModelStatus) -> some View {
        switch status.state {
        case .ready:
            Text(status.info.sizeLabel)
        case .unavailable(let message):
            Text(message)
        case .error(let message):
            Text(message)
        case .downloading:
            Text(L10n.t("model_loading.phase.downloading"))
        case .prewarming:
            Text(L10n.t("services.optimizing"))
        case .notDownloaded:
            Text(status.info.localizedDescription)
        }
    }

    private func statusTextColor(_ status: ActiveModelStatus) -> Color {
        switch status.state {
        case .error:
            return .orange
        case .unavailable:
            return .secondary
        default:
            return .secondary
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: ActiveModelStatus) -> some View {
        switch status.state {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
        case .unavailable:
            Image(systemName: "lock.circle.fill")
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
        case .downloading, .prewarming:
            ProgressView()
        case .notDownloaded:
            Image(systemName: "arrow.down.circle.fill")
        }
    }

    private func statusIconColor(_ status: ActiveModelStatus) -> Color {
        switch status.state {
        case .ready:
            return .dictusSuccess
        case .error:
            return .orange
        case .unavailable:
            return .secondary
        case .downloading, .prewarming, .notDownloaded:
            return .dictusAccent
        }
    }

    // MARK: - Last Transcription Card

    private func transcriptionCard(result: String) -> some View {
        Button {
            UIPasteboard.general.string = result
            HapticFeedback.recordingStopped()
            showCopiedFeedback = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopiedFeedback = false
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(showCopiedFeedback ? L10n.t("app.home.copied") : L10n.t("app.home.last_transcription"))
                        .font(.dictusCaption)
                        .foregroundColor(showCopiedFeedback ? .dictusSuccess : .secondary)
                        .animation(.easeOut(duration: 0.2), value: showCopiedFeedback)
                    Spacer()
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                Text(result)
                    .font(.dictusBody)
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .dictusGlass()
        }
        .buttonStyle(GlassPressStyle(pressedScale: 0.97))
        .accessibilityHint(L10n.t("app.home.tap_to_copy"))
    }

    // MARK: - Test Dictation Link

    private var testDictationLink: some View {
        Button {
            coordinator.startDictation()
        } label: {
            HStack {
                Image(systemName: "waveform")
                Text(L10n.t("app.home.new_dictation"))
                    .font(.dictusBody)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.dictusAccent)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(GlassPressStyle())
    }
}

#Preview {
    NavigationStack {
        HomeView(modelManager: ModelManager())
            .environmentObject(DictationCoordinator.shared)
    }
}
