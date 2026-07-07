import Shared
import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var appGroupResult = AppGroupDiagnostic.runSafe()
    @State private var sharedSnapshot = SharedSnapshot.capture()
    @State private var bridgeSnapshot = BridgeDiagnosticsSnapshot.capture()
    @State private var bridgeMode: DictationBridgeMode = BridgeModeStore.read()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                bridgeSection
                appGroupSection
                keyboardStateSection
                providerAvailabilitySection
                runtimeEnvironmentSection
                recorderSection
                persistentLogSection
                timelineSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(Color.dictusBackground.ignoresSafeArea())
        .navigationTitle(L10n.t("diagnostics.title"))
        .onAppear {
            refresh()
        }
        .refreshable {
            refresh()
        }
    }

    private var bridgeSection: some View {
        diagnosticsCard(title: L10n.t("diagnostics.bridge_section"), systemImage: "arrow.triangle.swap") {
            VStack(spacing: 10) {
                Picker(
                    selection: Binding(
                        get: { bridgeMode },
                        set: { newMode in
                            bridgeMode = newMode
                            BridgeModeStore.write(newMode)
                            refresh()
                        }
                    ),
                    label: Text(L10n.t("diagnostics.bridge_mode"))
                ) {
                    ForEach(DictationBridgeMode.allCases, id: \.self) { mode in
                        Text(L10n.t(mode.displayNameKey)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                diagnosticValueRow(
                    title: L10n.t("diagnostics.bridge_effective"),
                    value: L10n.t(bridgeSnapshot.effectiveBridge.displayNameKey)
                )
                diagnosticValueRow(
                    title: L10n.t("diagnostics.bridge_app_group"),
                    value: appGroupAvailabilityText(bridgeSnapshot.appGroupAvailability)
                )
                if let reason = bridgeSnapshot.fallbackReason {
                    diagnosticValueRow(
                        title: L10n.t("diagnostics.bridge_fallback_reason"),
                        value: L10n.t(reason.reasonKey)
                    )
                }
                if let lastEvent = bridgeSnapshot.lastClipboardEvent {
                    diagnosticValueRow(
                        title: L10n.t("diagnostics.bridge_last_clipboard_event"),
                        value: clipboardEventText(lastEvent)
                    )
                } else {
                    diagnosticValueRow(
                        title: L10n.t("diagnostics.bridge_last_clipboard_event"),
                        value: L10n.t("diagnostics.value_none")
                    )
                }
            }
        }
    }

    private func appGroupAvailabilityText(_ availability: AppGroupAvailability) -> String {
        switch availability {
        case .available:
            return L10n.t("diagnostics.bridge_app_group_available")
        case .unavailable(let reason):
            return L10n.t("diagnostics.bridge_app_group_unavailable") + " (" + L10n.t(reason.reasonKey) + ")"
        }
    }

    private func clipboardEventText(_ event: ClipboardBridgeEvent) -> String {
        let key: String
        switch event.kind {
        case .deepLinkOpened: key = "diagnostics.bridge_event.deep_link_opened"
        case .pasteboardWriteSuccess: key = "diagnostics.bridge_event.pasteboard_write_success"
        case .pasteboardWriteFailed: key = "diagnostics.bridge_event.pasteboard_write_failed"
        case .pasteboardReadSuccess: key = "diagnostics.bridge_event.pasteboard_read_success"
        case .pasteboardReadEmpty: key = "diagnostics.bridge_event.pasteboard_read_empty"
        case .pasteboardReadFailed: key = "diagnostics.bridge_event.pasteboard_read_failed"
        case .inserted: key = "diagnostics.bridge_event.inserted"
        case .dismissed: key = "diagnostics.bridge_event.dismissed"
        }
        let time = event.timestamp.formatted(date: .omitted, time: .standard)
        return "\(L10n.t(key)) · \(time)"
    }

    private var appGroupSection: some View {
        diagnosticsCard(title: L10n.t("diagnostics.app_group_section"), systemImage: "externaldrive.connected.to.line.below") {
            VStack(spacing: 10) {
                diagnosticStatusRow(
                    title: L10n.t("diagnostics.app_group_container"),
                    value: appGroupResult.appGroupID,
                    isHealthy: appGroupResult.containerExists
                )
                diagnosticStatusRow(
                    title: L10n.t("diagnostics.app_group_read"),
                    value: appGroupResult.canRead ? L10n.t("diagnostics.ok") : L10n.t("diagnostics.failed"),
                    isHealthy: appGroupResult.canRead
                )
                diagnosticStatusRow(
                    title: L10n.t("diagnostics.app_group_write"),
                    value: appGroupResult.canWrite ? L10n.t("diagnostics.ok") : L10n.t("diagnostics.failed"),
                    isHealthy: appGroupResult.canWrite
                )
                diagnosticStatusRow(
                    title: L10n.t("diagnostics.app_group_file_read"),
                    value: appGroupResult.canReadFile ? L10n.t("diagnostics.ok") : L10n.t("diagnostics.failed"),
                    isHealthy: appGroupResult.canReadFile
                )
                diagnosticStatusRow(
                    title: L10n.t("diagnostics.app_group_file_write"),
                    value: appGroupResult.canWriteFile ? L10n.t("diagnostics.ok") : L10n.t("diagnostics.failed"),
                    isHealthy: appGroupResult.canWriteFile
                )
                diagnosticValueRow(
                    title: L10n.t("diagnostics.app_group_file"),
                    value: appGroupResult.fileName
                )
                diagnosticValueRow(
                    title: L10n.t("diagnostics.app_group_timestamp"),
                    value: appGroupResult.timestamp.formatted(date: .omitted, time: .standard)
                )
            }
        }
    }

    private var keyboardStateSection: some View {
        diagnosticsCard(title: L10n.t("diagnostics.keyboard_section"), systemImage: "keyboard") {
            VStack(spacing: 10) {
                diagnosticValueRow(
                    title: L10n.t("diagnostics.keyboard_status"),
                    value: sharedSnapshot.statusRaw ?? L10n.t("diagnostics.value_none")
                )
                diagnosticValueRow(
                    title: L10n.t("diagnostics.keyboard_heartbeat"),
                    value: sharedSnapshot.heartbeatDescription
                )
                diagnosticValueRow(
                    title: L10n.t("diagnostics.keyboard_cold_start"),
                    value: sharedSnapshot.coldStartActive ? L10n.t("diagnostics.value_yes") : L10n.t("diagnostics.value_no")
                )
                diagnosticValueRow(
                    title: L10n.t("diagnostics.keyboard_pending_transcription"),
                    value: sharedSnapshot.pendingTranscriptionDescription
                )
                diagnosticValueRow(
                    title: L10n.t("diagnostics.keyboard_last_error"),
                    value: sharedSnapshot.lastError ?? L10n.t("diagnostics.value_none")
                )
            }
        }
    }

    private var providerAvailabilitySection: some View {
        diagnosticsCard(title: L10n.t("diagnostics.providers_section"), systemImage: "antenna.radiowaves.left.and.right") {
            VStack(spacing: 10) {
                ForEach(SelectedProvider.allCases) { provider in
                    providerRow(provider)
                }
            }
        }
    }

    private func providerRow(_ provider: SelectedProvider) -> some View {
        let availability = appState.providerAvailability(for: provider)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: availabilityIcon(availability))
                .foregroundStyle(availabilityColor(availability))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(provider.displayName)
                    .font(.subheadline.bold())
                Text(L10n.t(availability.displayKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var runtimeEnvironmentSection: some View {
        diagnosticsCard(title: L10n.t("diagnostics.env_section"), systemImage: "iphone") {
            VStack(spacing: 10) {
                diagnosticValueRow(title: L10n.t("diagnostics.env_platform"), value: runtimePlatform)
                diagnosticValueRow(title: L10n.t("diagnostics.env_container"), value: containerHint)
                diagnosticValueRow(title: L10n.t("diagnostics.env_locale"), value: Locale.current.identifier)
                diagnosticValueRow(title: L10n.t("diagnostics.env_bundle"), value: Bundle.main.bundleIdentifier ?? L10n.t("diagnostics.value_unknown"))
                diagnosticValueRow(title: L10n.t("diagnostics.env_url_scheme"), value: "mashangxie://")
            }
        }
    }

    private var recorderSection: some View {
        diagnosticsCard(title: L10n.t("diagnostics.recorder_section"), systemImage: "mic") {
            if let error = appState.recorderDiagnostic.lastDeactivationError {
                diagnosticValueRow(title: L10n.t("diagnostics.recorder_deactivation_error"), value: error, valueColor: .orange)
            } else {
                Text(L10n.t("diagnostics.recorder_no_error"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var persistentLogSection: some View {
        diagnosticsCard(title: L10n.t("diagnostics.logs_section"), systemImage: "doc.text.magnifyingglass") {
            NavigationLink {
                DebugLogView()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("diagnostics.open_debug_logs"))
                            .font(.subheadline.bold())
                        Text(L10n.t("diagnostics.open_debug_logs_hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    private var timelineSection: some View {
        diagnosticsCard(title: L10n.t("diagnostics.timeline_section"), systemImage: "clock.arrow.circlepath") {
            if appState.timelineEvents.isEmpty {
                Text(L10n.t("diagnostics.timeline_empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 12) {
                    ForEach(appState.timelineEvents.reversed()) { event in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: timelineIcon(event.category))
                                .foregroundStyle(Color.dictusAccent)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.message)
                                    .font(.footnote)
                                Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func diagnosticsCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .dictusGlass(in: RoundedRectangle(cornerRadius: 18))
    }

    private func diagnosticStatusRow(title: String, value: String, isHealthy: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isHealthy ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isHealthy ? Color.dictusSuccess : .red)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
    }

    private func diagnosticValueRow(title: String, value: String, valueColor: Color = .secondary) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 16)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func refresh() {
        appState.refreshRecorderDiagnostic()
        appGroupResult = AppGroupDiagnostic.runSafe()
        sharedSnapshot = SharedSnapshot.capture()
        bridgeSnapshot = BridgeDiagnosticsSnapshot.capture()
        bridgeMode = BridgeModeStore.read()
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
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.contains("Application/LiveContainer") {
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
        case .ready: return Color.dictusSuccess
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

private struct SharedSnapshot {
    let statusRaw: String?
    let heartbeat: Date?
    let coldStartActive: Bool
    let pendingTranscription: String?
    let lastError: String?

    var heartbeatDescription: String {
        guard let heartbeat else { return L10n.t("diagnostics.value_none") }
        let age = max(0, Date().timeIntervalSince(heartbeat))
        return L10n.t("diagnostics.heartbeat_age", Int(age))
    }

    var pendingTranscriptionDescription: String {
        guard let pendingTranscription, !pendingTranscription.isEmpty else {
            return L10n.t("diagnostics.value_none")
        }
        return L10n.t("diagnostics.pending_transcription_length", pendingTranscription.count)
    }

    static func capture() -> SharedSnapshot {
        let store = SharedStatusStore()
        let defaults = AppGroup.defaultsIfAvailable
        return SharedSnapshot(
            statusRaw: store.readStatus()?.rawValue,
            heartbeat: store.readHeartbeat(),
            coldStartActive: defaults?.bool(forKey: SharedKeys.coldStartActive) ?? false,
            pendingTranscription: store.readTranscription(),
            lastError: store.readError()
        )
    }
}

#Preview {
    DiagnosticsView()
        .environmentObject(AppState())
}
