// DictusApp/Views/SettingsView.swift
// iOS-style grouped settings list with preferences persisted via App Group.
import SwiftUI
import UIKit
import Shared

/// Settings screen with 3 sections: Transcription, Keyboard, About.
///
/// WHY @AppStorage with App Group store:
/// Preferences need to be readable by both the main app AND the keyboard extension.
/// @AppStorage with the App Group suite writes to the shared UserDefaults container,
/// making preferences available across processes without any additional sync logic.
///
/// WHY grouped List style:
/// iOS standard settings pattern — users immediately recognize the familiar
/// grouped rows with section headers and footers.
struct SettingsView: View {

    // MARK: - Preferences (App Group persisted)

    @AppStorage(SharedKeys.keyboardLayout, store: UserDefaults(suiteName: AppGroup.identifier))
    private var keyboardLayout = "qwerty"

    @AppStorage(SharedKeys.hapticsEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
    private var hapticsEnabled = true

    /// WHY default true: Most users expect autocorrect to be active by default.
    /// Power users who find it annoying can toggle it off here.
    @AppStorage(SharedKeys.autocorrectEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
    private var autocorrectEnabled = true

    @AppStorage(SharedKeys.liveActivityEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
    private var liveActivityEnabled = true

    #if DEBUG
    /// Debug-only: logs autocorrect decisions with user text to the debug log.
    /// This toggle only exists in DEBUG builds — the Release binary doesn't contain
    /// either this @AppStorage or the AutocorrectDebugLog code that reads it.
    @AppStorage(SharedKeys.autocorrectDebugLogging, store: UserDefaults(suiteName: AppGroup.identifier))
    private var autocorrectDebugLogging = false
    #endif

    /// Tracks log export async operation for spinner display.
    @State private var isExporting = false
    @State private var exportURL: URL?

    // MARK: - Body

    var body: some View {
        List {
            // Section 1: Keyboard
            // All toggles are always visible — there's only one keyboard type now.
            Section {
                DefaultLayerPicker()

                Toggle(L10n.t("settings.haptic_feedback"), isOn: $hapticsEnabled)

                NavigationLink(L10n.t("settings.sounds")) {
                    SoundSettingsView()
                }

                Toggle(L10n.t("settings.autocorrect"), isOn: $autocorrectEnabled)

                Toggle(L10n.t("settings.live_activity"), isOn: $liveActivityEnabled)
                    .onChange(of: liveActivityEnabled) { _, enabled in
                        if !enabled {
                            LiveActivityManager.shared.stopStandbyActivity()
                        }
                    }
            } header: {
                Text(L10n.t("settings.keyboard_section"))
            } footer: {
                if !liveActivityEnabled {
                    Text(L10n.t("settings.live_activity_disabled_hint"))
                }
            }
            .onAppear {
                keyboardLayout = "qwerty"
            }

            #if DEBUG
            // Section: Developer (visible ONLY in Debug builds — not in Release/TestFlight/App Store).
            // WHY #if DEBUG: Code inside is compile-time excluded from production builds.
            // Impossible to accidentally ship a toggle that logs user text.
            Section {
                Toggle(L10n.t("settings.autocorrect_debug_logs"), isOn: $autocorrectDebugLogging)
            } header: {
                Text(L10n.t("settings.developer_section"))
            } footer: {
                if autocorrectDebugLogging {
                    Text(L10n.t("settings.autocorrect_debug_warning"))
                        .foregroundColor(.orange)
                } else {
                    Text(L10n.t("settings.autocorrect_debug_hint"))
                }
            }
            #endif

            // Section 3: A propos
            Section(L10n.t("settings.about_section")) {
                LabeledContent(L10n.t("settings.about_version"), value: appVersion)

                externalLinkRow(
                    title: L10n.t("settings.github_star"),
                    url: ExternalLinks.githubRepository
                )

                externalLinkRow(
                    title: L10n.t("settings.privacy_policy"),
                    url: ExternalLinks.privacyPolicy
                )

                externalLinkRow(
                    title: L10n.t("settings.licenses"),
                    url: ExternalLinks.thirdPartyLicenses
                )

                NavigationLink(L10n.t("settings.diagnostic")) {
                    diagnosticView
                }

                NavigationLink(L10n.t("settings.debug_logs")) {
                    DebugLogView()
                }

                Button {
                    exportLogs()
                } label: {
                    HStack {
                        Text(L10n.t("settings.export_logs"))
                        Spacer()
                        if isExporting {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .disabled(isExporting)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.dictusBackground.ignoresSafeArea())
        .navigationTitle(L10n.t("settings.title"))
        .sheet(isPresented: Binding(
            get: { exportURL != nil },
            set: { isPresented in
                if !isPresented {
                    exportURL = nil
                }
            }
        )) {
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
        }
    }

    // MARK: - Private

    /// Export logs via iOS share sheet.
    ///
    /// WHY write to a temp file instead of sharing raw text:
    /// UIActivityViewController with a file URL shows the file name ("dictus-logs.txt")
    /// in the share sheet and lets the user save, AirDrop, or attach it to email/GitHub.
    /// Raw text sharing doesn't give a meaningful filename.
    /// WHY async with isExporting flag:
    /// Log gathering reads from disk and can take a moment on large log files.
    /// The spinner gives visual feedback that something is happening. The share
    /// sheet presentation must happen on the main thread (UIKit requirement).
    private func exportLogs() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            let start = CFAbsoluteTimeGetCurrent()
            let content = PersistentLog.exportContent()
            let duration = CFAbsoluteTimeGetCurrent() - start
            PersistentLog.log(.logExportCompleted(durationMs: Int(duration * 1000), sizeBytes: content.utf8.count))
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("mashangxie-logs.txt")
            try? content.write(to: tempURL, atomically: true, encoding: .utf8)

            await MainActor.run {
                isExporting = false
                exportURL = tempURL
            }
        }
    }

    // WHY Button instead of Link:
    // Link does not get the same row press highlight inside this grouped List.
    private func externalLinkRow(title: String, url: URL) -> some View {
        Button {
            UIApplication.shared.open(url)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// App version string from Info.plist — marketing version + build number.
    ///
    /// Format: "1.6.0 (10)" — lets testers report bugs against a specific build,
    /// since TestFlight ships multiple builds under the same marketing version.
    private var appVersion: String {
        let marketing = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(marketing) (\(build))"
    }

    /// Full diagnostics view. This includes App Group health plus the dictation
    /// bridge selector used to force ClipboardBridge during free-signing checks.
    private var diagnosticView: some View {
        DiagnosticsView()
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
