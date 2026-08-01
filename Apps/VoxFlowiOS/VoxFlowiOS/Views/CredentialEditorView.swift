import SwiftUI

struct CredentialEditorView: View {
    let provider: LocalCredentialStore.Provider
    var onSave: () -> Void = {}

    @EnvironmentObject private var appState: AppState
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
                                .textInputAutocapitalization(.never)
                        } else {
                            TextField("", text: binding(for: field.key))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
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
            onSave()
            saveError = nil
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
            onSave()
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
