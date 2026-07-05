import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            Form {
                providerSection
                languageSection
                credentialsSection
                warningSection
                aboutSection
            }
            .navigationTitle(L10n.t("settings.title"))
        }
    }

    private var providerSection: some View {
        Section(L10n.t("settings.provider_section")) {
            Picker(L10n.t("settings.provider"), selection: $appState.selectedProvider) {
                ForEach(SelectedProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.menu)

            if !appState.selectedProvider.requiresCredentials {
                Text(L10n.t("settings.provider.apple_speech_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var languageSection: some View {
        Section(L10n.t("settings.language_section")) {
            Picker(L10n.t("settings.language"), selection: $appState.selectedLanguage) {
                ForEach(SelectedLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var credentialsSection: some View {
        Section(L10n.t("settings.credentials_section")) {
            ForEach(LocalCredentialStore.Provider.allCases) { provider in
                NavigationLink {
                    CredentialEditorView(provider: provider)
                } label: {
                    HStack {
                        Text(provider.displayName)
                        Spacer()
                        if appState.credentialStore.isComplete(provider) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text(L10n.t("settings.credentials_not_set"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var warningSection: some View {
        Section {
            Label {
                Text(L10n.t("settings.credentials_warning"))
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var aboutSection: some View {
        Section(L10n.t("settings.about_section")) {
            LabeledContent(L10n.t("settings.about_version"), value: Self.appVersion)
            LabeledContent(L10n.t("settings.about_env"), value: Self.runtimeEnvironment)
            Text(L10n.t("settings.about_env_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private static var runtimeEnvironment: String {
        #if targetEnvironment(simulator)
        return L10n.t("settings.about_env_simulator")
        #else
        return L10n.t("settings.about_env_device")
        #endif
    }
}

struct CredentialEditorView: View {
    let provider: LocalCredentialStore.Provider

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var saveError: String?
    @State private var showSaved = false

    var body: some View {
        Form {
            Section(provider.displayName) {
                ForEach(provider.fieldDefinitions) { field in
                    HStack {
                        Text(field.label)
                            .frame(width: 100, alignment: .leading)
                        if field.isSecret {
                            SecureField("", text: binding(for: field.key))
                                .textContentType(.password)
                                .autocorrectionDisabled()
                        } else {
                            TextField("", text: binding(for: field.key))
                                .autocorrectionDisabled()
                        }
                    }
                }
            }

            Section {
                Button {
                    save()
                } label: {
                    Label(L10n.t("settings.credentials_save"), systemImage: "tray.and.arrow.down")
                }
                .disabled(!isComplete)

                Button(role: .destructive) {
                    clear()
                } label: {
                    Label(L10n.t("settings.credentials_clear"), systemImage: "trash")
                }
            }

            if let saveError {
                Section {
                    Text(saveError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section {
                Text(L10n.t("settings.credentials_warning"))
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .navigationTitle(provider.displayName)
        .onAppear {
            values = appState.credentialStore.values(for: provider)
        }
        .overlay(alignment: .top) {
            if showSaved {
                Text(L10n.t("settings.credentials_saved_toast"))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { values[key] ?? "" },
            set: { values[key] = $0 }
        )
    }

    private var isComplete: Bool {
        provider.fieldDefinitions.allSatisfy { field in
            !(values[field.key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    private func save() {
        do {
            try appState.saveCredentials(for: provider, values: values)
            withAnimation { showSaved = true }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation { showSaved = false }
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func clear() {
        do {
            try appState.clearCredentials(for: provider)
            values = [:]
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
