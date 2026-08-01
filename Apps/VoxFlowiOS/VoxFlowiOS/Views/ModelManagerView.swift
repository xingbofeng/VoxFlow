// DictusApp/Views/ModelManagerView.swift
// Model management UI: download, select, and delete WhisperKit models.
// Redesigned with Downloaded/Available sections, gauge-based model cards, and engine descriptions.
// Swipe-to-delete on downloaded non-active model cards (like iOS Mail).
import SwiftUI
import Shared

/// Displays WhisperKit models organized in two sections:
/// - "Downloaded" — models on device, including deprecated ones
/// - "Available" — models available for download, excludes deprecated
///
/// WHY two sections instead of a flat list:
/// Users need to quickly see what's on their device vs. what they can download.
/// Separating sections provides clear visual hierarchy. Deprecated models (Tiny/Base)
/// only appear in Downloaded if the user already has them — they're hidden from
/// Available to guide users toward better models.
///
/// WHY List instead of ScrollView+VStack:
/// SwiftUI's .swipeActions modifier only works inside List context. We style the List
/// with transparent backgrounds and hidden separators to preserve the glass card aesthetic.
///
/// WHY engine description paragraphs:
/// Users may not know what "WhisperKit" means. A brief explanation helps them
/// understand the technology behind the models they're choosing.
struct ModelManagerView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var modelManager: ModelManager

    /// Controls the delete confirmation alert.
    @State private var modelToDelete: ModelInfo?
    @State private var showDeleteAlert = false

    /// Tracks any download error to show in an alert.
    @State private var downloadError: String?
    @State private var showErrorAlert = false

    /// Issue #144: the model identifier currently being prepared (downloading,
    /// compiling, or loading into RAM). When non-nil the full-screen overlay
    /// blocks the manager UI until prep completes. Driven by the @State below
    /// rather than the computed value because we want the overlay to keep its
    /// "ready" celebration moment after the model state flips back to .ready.
    @State private var preparingModelID: String?

    // MARK: - Computed model lists

    /// Downloaded models — includes deprecated (Tiny/Base) if user has them on device,
    /// plus any models currently downloading or prewarming (so they appear here immediately).
    private var downloadedModels: [ModelInfo] {
        ModelInfo.allIncludingDeprecated.filter { model in
            let state = modelManager.modelStates[model.identifier] ?? .notDownloaded
            switch state {
            case .downloading, .prewarming, .ready, .error:
                return true
            case .notDownloaded, .unavailable:
                return modelManager.downloadedModels.contains(model.identifier)
            }
        }
    }

    /// Available models — excludes downloaded, downloading, and prewarming models.
    /// Users won't see Tiny/Base here since they're deprecated.
    ///
    /// Phase 37 (issue #104): uses `ModelInfo.available(on:)` so per-device gated
    /// models (e.g. Whisper Turbo on low-RAM devices) are completely hidden rather
    /// than shown disabled. The "Downloaded" section above stays ungated so a user
    /// who obtained a gated model under a permissive build can still manage/delete it.
    private var availableModels: [ModelInfo] {
        ModelInfo.available(on: DeviceCapabilities.current()).filter { model in
            let state = modelManager.modelStates[model.identifier] ?? .notDownloaded
            switch state {
            case .downloading, .prewarming, .ready, .error:
                return false
            case .notDownloaded, .unavailable:
                return !modelManager.downloadedModels.contains(model.identifier)
            }
        }
    }

    /// First model identifier currently in a user-facing prep phase.
    /// Priority: active load > prewarming > downloading.
    private var liveActivePrepModel: String? {
        if modelManager.modelLoadState == .loading,
           let active = modelManager.activeModel {
            return active
        }
        for model in ModelInfo.allIncludingDeprecated {
            switch modelManager.modelStates[model.identifier] ?? .notDownloaded {
            case .prewarming:
                return model.identifier
            default:
                continue
            }
        }
        for model in ModelInfo.allIncludingDeprecated {
            switch modelManager.modelStates[model.identifier] ?? .notDownloaded {
            case .downloading:
                return model.identifier
            default:
                continue
            }
        }
        return nil
    }

    /// Whether a given model can be deleted (not active, not the last one).
    private func canDelete(_ model: ModelInfo) -> Bool {
        let state = modelManager.modelStates[model.identifier] ?? .notDownloaded
        guard case .ready = state else { return false }
        let isActive = modelManager.activeModel == model.identifier
        let isLastDownloaded = modelManager.downloadedModels.count <= 1
        return !isActive && !isLastDownloaded
    }

    var body: some View {
        List {
            // MARK: - Downloaded section
            // WHY no Section header: parameter:
            // List Section headers are sticky by default in iOS. Using an inline Text row
            // as the first item in a plain Section makes it scroll with the content.
            if !downloadedModels.isEmpty {
                Section {
                    // Inline section header — scrolls with content (not sticky)
                    Text(L10n.t("services.downloaded_section"))
                        .font(.dictusSubheading)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))

                    ForEach(downloadedModels) { model in
                        ModelCardView(
                            model: model,
                            modelManager: modelManager,
                            onDownloadError: { error in
                                downloadError = error
                                showErrorAlert = true
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if canDelete(model) {
                                Button(role: .destructive) {
                                    modelToDelete = model
                                    showDeleteAlert = true
                                } label: {
                                    Label(L10n.t("common.delete"), systemImage: "trash")
                                        .frame(maxHeight: .infinity)
                                }
                                .tint(.red)
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                }
            }

            // MARK: - Available section
            if !availableModels.isEmpty {
                Section {
                    // Inline section header — scrolls with content (not sticky)
                    Text(L10n.t("services.available_section"))
                        .font(.dictusSubheading)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))

                    ForEach(availableModels) { model in
                        ModelCardView(
                            model: model,
                            modelManager: modelManager,
                            onDownloadError: { error in
                                downloadError = error
                                showErrorAlert = true
                            }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                }
            }

            Section {
                ForEach(LocalCredentialStore.Provider.allCases) { provider in
                    NavigationLink {
                        CredentialEditorView(provider: provider) {
                            modelManager.loadState()
                            appState.reloadCredentials()
                        }
                    } label: {
                        HStack {
                            Text(provider.displayName)
                            Spacer()
                            if appState.credentialStore.isEffectivelyComplete(provider) {
                                Text(L10n.t("settings.credentials_configured"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(L10n.t("settings.credentials_not_set"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            } header: {
                Text(L10n.t("settings.credentials_section"))
                    .font(.dictusSubheading)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))
            } footer: {
                Text(L10n.t("settings.credentials_warning"))
                    .font(.dictusCaption)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 16, trailing: 16))
            }

            // MARK: - Engine descriptions footer
            // WHY a separate section at the bottom:
            // Engine descriptions are reference info, not per-section content.
            // Placing them as a fixed footer at the bottom keeps the model sections clean
            // and avoids duplicating descriptions across Downloaded/Available sections.
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    engineParagraph(
                        icon: "waveform",
                        text: L10n.t("services.engine.apple_speech")
                    )
                    engineParagraph(
                        icon: "bolt",
                        text: L10n.t("services.engine.cloud")
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle(L10n.t("services.title"))
        .background(Color.dictusBackground.ignoresSafeArea())
        // Sync state from onboarding's separate ModelManager instance (Bug #25 fix).
        // WHY onAppear loadState:
        // When the user downloads a model during onboarding, a separate ModelManager
        // writes state to App Group defaults. This view's ModelManager instance may
        // not reflect that. Calling loadState() on appear re-reads from the shared
        // UserDefaults so the model shows as downloaded and active.
        .onAppear {
            modelManager.loadState()
        }
        // Delete confirmation alert
        .alert(L10n.t("services.delete_alert_title"), isPresented: $showDeleteAlert, presenting: modelToDelete) { model in
            Button(L10n.t("common.cancel"), role: .cancel) { }
            Button(L10n.t("common.delete"), role: .destructive) {
                do {
                    try modelManager.deleteModel(model.identifier)
                } catch {
                    downloadError = error.localizedDescription
                    showErrorAlert = true
                }
            }
        } message: { model in
            Text(L10n.t("services.delete_alert_message", model.displayName))
        }
        // Error alert
        .alert(L10n.t("common.error"), isPresented: $showErrorAlert) {
            Button(L10n.t("common.ok"), role: .cancel) { }
        } message: {
            if let error = downloadError {
                Text(error)
            }
        }
        // Issue #144: full-screen overlay during model download / compile / RAM-load.
        // We watch the live computed property and lift it into a @State binding the
        // overlay can flip back to nil when it's ready to dismiss.
        .onChange(of: liveActivePrepModel) { _, newValue in
            if let id = newValue, preparingModelID == nil {
                preparingModelID = id
            }
        }
        .onAppear {
            if preparingModelID == nil, let id = liveActivePrepModel {
                preparingModelID = id
            }
        }
        .fullScreenCover(item: Binding<PreparingModelItem?>(
            get: { preparingModelID.map(PreparingModelItem.init) },
            set: { preparingModelID = $0?.id }
        )) { item in
            ModelLoadingOverlay(
                modelManager: modelManager,
                modelIdentifier: item.id,
                isPresented: Binding(
                    get: { preparingModelID != nil },
                    set: { if !$0 { preparingModelID = nil } }
                )
            )
        }
    }

    /// Wrapper so we can use `.fullScreenCover(item:)` with a plain String.
    private struct PreparingModelItem: Identifiable {
        let id: String
    }

    // MARK: - Engine descriptions

    /// A single engine description paragraph with icon.
    private func engineParagraph(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.dictusCaption)
                .foregroundStyle(.tertiary)

            Text(text)
                .font(.dictusCaption)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }
}

#Preview {
    NavigationStack {
        ModelManagerView(modelManager: ModelManager())
    }
}
