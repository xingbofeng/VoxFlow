import SwiftUI
import VoxFlowMobileCore

struct DictationView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showCopiedToast = false
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    providerSummaryCard
                    languageSummaryCard
                    liveTextCard
                    actionButtons
                    if !appState.finalText.isEmpty {
                        finalTextCard
                    }
                }
                .padding()
            }
            .navigationTitle(L10n.t("dictation.title"))
            .overlay(alignment: .top) {
                if showCopiedToast {
                    Text(L10n.t("dictation.copied"))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let text = shareText {
                    ShareSheet(text: text)
                }
            }
        }
    }

    // MARK: - Subviews

    private var providerSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("dictation.current_service"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: providerIcon)
                    .foregroundStyle(.tint)
                Text(appState.selectedProvider.displayName)
                    .font(.headline)
                Spacer()
                NavigationLink {
                    SettingsView()
                } label: {
                    Text(L10n.t("dictation.change"))
                        .font(.footnote)
                }
            }
            Text(L10n.t(appState.selectedProvider.summaryKey))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !availabilityHint.isEmpty {
                Text(availabilityHint)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var languageSummaryCard: some View {
        HStack {
            Image(systemName: "globe")
                .foregroundStyle(.tint)
            Text(L10n.t("dictation.language_label"))
                .font(.subheadline)
            Spacer()
            Text(appState.selectedLanguage.displayName)
                .font(.subheadline.bold())
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var liveTextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("dictation.live_text"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(appState.visibleLiveText.isEmpty ? L10n.t("dictation.live_placeholder") : appState.visibleLiveText)
                .font(.body)
                .foregroundStyle(appState.visibleLiveText.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .minHeight(80)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            primaryActionButton
            HStack(spacing: 12) {
                Button {
                    if appState.copyFinalText() {
                        withAnimation { showCopiedToast = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            withAnimation { showCopiedToast = false }
                        }
                    }
                } label: {
                    Label(L10n.t("dictation.copy"), systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(appState.visibleLiveText.isEmpty && appState.finalText.isEmpty)

                Button {
                    showShareSheet = true
                } label: {
                    Label(L10n.t("dictation.share"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(appState.visibleLiveText.isEmpty && appState.finalText.isEmpty)

                Button(role: .destructive) {
                    appState.clearResult()
                } label: {
                    Label(L10n.t("dictation.clear"), systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isSessionActive)
            }
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch appState.sessionState {
        case .idle, .failed:
            Button {
                Task { await appState.startDictation() }
            } label: {
                Label(L10n.t("dictation.start"), systemImage: "mic.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        case .requestingPermission:
            ProgressView(L10n.t("dictation.requesting_permission"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        case .recording:
            Button(role: .destructive) {
                appState.stopDictation()
            } label: {
                Label(L10n.t("dictation.stop"), systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        case .transcribing:
            ProgressView(L10n.t("dictation.transcribing"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        case .finished:
            Button {
                Task { await appState.startDictation() }
            } label: {
                Label(L10n.t("dictation.start_again"), systemImage: "arrow.clockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var finalTextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("dictation.final_text"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(appState.finalText)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private var providerIcon: String {
        switch appState.selectedProvider {
        case .appleSpeech: return "apple.logo"
        case .tencent: return "cloud.fill"
        case .aliyun: return "cloud.fill"
        case .volcengine: return "cloud.fill"
        }
    }

    private var availabilityHint: String {
        switch appState.providerAvailability(for: appState.selectedProvider) {
        case .ready: return ""
        case .missingCredentials: return L10n.t("diagnostics.availability.missing_credentials")
        case .permissionDenied: return L10n.t("diagnostics.availability.permission_denied")
        case .permissionNotDetermined: return L10n.t("diagnostics.availability.permission_not_determined")
        case let .envLimited(msg): return msg
        }
    }

    private var shareText: String? {
        let text = appState.finalText.isEmpty ? appState.visibleLiveText : appState.finalText
        return text.isEmpty ? nil : text
    }

    private var isSessionActive: Bool {
        switch appState.sessionState {
        case .recording, .transcribing:
            return true
        default:
            return false
        }
    }
}

extension View {
    func minHeight(_ height: CGFloat) -> some View {
        frame(minHeight: height, alignment: .topLeading)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    DictationView()
        .environmentObject(AppState())
}
