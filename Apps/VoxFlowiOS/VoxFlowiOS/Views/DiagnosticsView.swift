import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                providerAvailabilitySection
                runtimeEnvironmentSection
                recorderSection
                timelineSection
            }
            .navigationTitle(L10n.t("diagnostics.title"))
            .onAppear {
                appState.refreshRecorderDiagnostic()
            }
        }
    }

    private var providerAvailabilitySection: some View {
        Section(L10n.t("diagnostics.providers_section")) {
            ForEach(SelectedProvider.allCases) { provider in
                providerRow(provider)
            }
        }
    }

    private func providerRow(_ provider: SelectedProvider) -> some View {
        let availability = appState.providerAvailability(for: provider)
        return HStack(alignment: .top) {
            Image(systemName: availabilityIcon(availability))
                .foregroundStyle(availabilityColor(availability))
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.subheadline.bold())
                Text(L10n.t(availability.displayKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var runtimeEnvironmentSection: some View {
        Section(L10n.t("diagnostics.env_section")) {
            LabeledContent(L10n.t("diagnostics.env_platform"), value: runtimePlatform)
            LabeledContent(L10n.t("diagnostics.env_container"), value: containerHint)
            LabeledContent(L10n.t("diagnostics.env_locale"), value: Locale.current.identifier)
        }
    }

    private var recorderSection: some View {
        Section(L10n.t("diagnostics.recorder_section")) {
            if let error = appState.recorderDiagnostic.lastDeactivationError {
                LabeledContent(L10n.t("diagnostics.recorder_deactivation_error"), value: error)
                    .foregroundStyle(.orange)
            } else {
                Text(L10n.t("diagnostics.recorder_no_error"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timelineSection: some View {
        Section(L10n.t("diagnostics.timeline_section")) {
            if appState.timelineEvents.isEmpty {
                Text(L10n.t("diagnostics.timeline_empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.timelineEvents.reversed()) { event in
                    HStack(alignment: .top) {
                        Image(systemName: timelineIcon(event.category))
                            .foregroundStyle(.tint)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.message)
                                .font(.footnote)
                            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var runtimePlatform: String {
        #if targetEnvironment(simulator)
        return L10n.t("diagnostics.env_platform_simulator")
        #else
        return L10n.t("diagnostics.env_platform_device")
        #endif
    }

    private var containerHint: String {
        // LiveContainer 检测：bundle path 包含 "PrivateFrameworks" 或 sandbox 路径异常时提示。
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.contains("Application/LiveContainer") || bundlePath.contains("Containers/com.rileytestut.AltStore") {
            return L10n.t("diagnostics.env_container_livecontainer")
        }
        return L10n.t("diagnostics.env_container_native")
    }

    private func availabilityIcon(_ availability: ProviderAvailability) -> String {
        switch availability {
        case .ready: return "checkmark.circle.fill"
        case .missingCredentials: return "key.slash.fill"
        case .permissionDenied: return "lock.fill"
        case .permissionNotDetermined: return "questionmark.circle.fill"
        case .envLimited: return "exclamationmark.triangle.fill"
        }
    }

    private func availabilityColor(_ availability: ProviderAvailability) -> Color {
        switch availability {
        case .ready: return .green
        case .missingCredentials: return .secondary
        case .permissionDenied: return .red
        case .permissionNotDetermined: return .orange
        case .envLimited: return .orange
        }
    }

    private func timelineIcon(_ category: TimelineEvent.Category) -> String {
        switch category {
        case .audio: return "waveform"
        case .network: return "network"
        case .asr: return "text.bubble"
        case .permission: return "lock.shield"
        case .env: return "gearshape"
        }
    }
}

#Preview {
    DiagnosticsView()
        .environmentObject(AppState())
}
