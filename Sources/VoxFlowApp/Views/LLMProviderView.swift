import SwiftUI

enum LLMProviderActionIcon {
    static let edit = "square.and.pencil"
    static let testConnection = "antenna.radiowaves.left.and.right"
    static let delete = "trash"
}

struct LLMProviderView: View {
    @ObservedObject var viewModel: LLMProviderViewModel
    var embedded = false
    @State private var editorRequest: LLMProviderEditorRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            HStack {
                if !embedded {
                    Label(L10n.localize("model.llm_provider.title", comment: ""), systemImage: "network")
                        .font(.system(size: 24, weight: .semibold))
                }
                Spacer()
                Button {
                    editorRequest = LLMProviderEditorRequest(provider: nil)
                } label: {
                    Label(L10n.localize("model.llm_provider.add_button", comment: ""), systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.accent)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(AppTheme.ColorToken.accentSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                                .stroke(AppTheme.ColorToken.accent.opacity(0.28))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L10n.localize("model.llm_provider.add_service_help", comment: ""))
            }

            codexSettingsCard

            if regularProviders.isEmpty {
                Text(L10n.localize("model.llm_provider.empty_state", comment: ""))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(AppTheme.ColorToken.panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
            } else {
                LazyVStack(spacing: AppTheme.Spacing.grid) {
                    ForEach(regularProviders, id: \.id) { provider in
                        providerRow(provider)
                    }
                }
            }

            Spacer()
        }
        .padding(embedded ? 0 : AppTheme.Spacing.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(embedded ? Color.clear : AppTheme.ColorToken.pageBackground)
        .actionFeedbackOverlay(
            message: viewModel.lastActionMessage,
            error: viewModel.lastError,
            enabled: !embedded,
            onDismiss: viewModel.clearFeedback
        )
        .onAppear {
            viewModel.loadIfNeeded()
            Task {
                await viewModel.detectCodexRuntime(forceRefresh: false)
            }
        }
        .sheet(item: $editorRequest) { request in
            LLMProviderEditorSheet(
                provider: request.provider,
                viewModel: viewModel
            )
            .frame(width: 560, height: 540)
        }
    }

    private var regularProviders: [LLMProviderRecord] {
        viewModel.providers.filter {
            $0.id.caseInsensitiveCompare(AgentProviderRegistry.codex.providerID) != .orderedSame &&
                $0.providerType.caseInsensitiveCompare(AgentProviderRegistry.codex.providerID) != .orderedSame
        }
    }

    private var codexSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.ColorToken.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.icon, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.localize("model.llm_provider.codex.title", comment: "Codex provider title"))
                        .font(.system(size: 18, weight: .semibold))
                    Text(L10n.localize("model.llm_provider.codex.subtitle", comment: "Codex provider subtitle"))
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                Spacer()
                Toggle(
                    viewModel.codexEnabled
                        ? L10n.localize("model.llm_provider.codex.enabled_short", comment: "Codex enabled short")
                        : L10n.localize("model.llm_provider.codex.disabled_short", comment: "Codex disabled short"),
                    isOn: Binding(
                        get: { viewModel.codexEnabled },
                        set: { viewModel.setCodexEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.large)
            }

            HStack(spacing: 10) {
                codexAvailabilityPill
                Spacer()
                Button {
                    Task { await viewModel.detectCodexRuntime(forceRefresh: true) }
                } label: {
                    Label(
                        L10n.localize("model.llm_provider.codex.detect", comment: "Detect Codex"),
                        systemImage: "checkmark.seal"
                    )
                    .frame(height: 32)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isCheckingCodexRuntime)
            }

            VStack(alignment: .leading, spacing: 9) {
                Text(L10n.localize("model.llm_provider.codex.model_section", comment: "Codex model section"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(viewModel.codexModelIDs, id: \.self) { model in
                        codexModelButton(model)
                    }
                }
            }
        }
        .padding(18)
        .background(viewModel.codexEnabled ? AppTheme.ColorToken.selectionBackground.opacity(0.72) : AppTheme.ColorToken.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    viewModel.codexEnabled ? AppTheme.ColorToken.accent.opacity(0.5) : AppTheme.ColorToken.panelStroke,
                    lineWidth: viewModel.codexEnabled ? 1.5 : AppTheme.Border.panelLineWidth
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var codexAvailabilityPill: some View {
        let availability = viewModel.codexRuntimeAvailability
        let available = availability?.isAvailable == true
        let text: String
        if viewModel.isCheckingCodexRuntime {
            text = L10n.localize("model.llm_provider.codex.detecting", comment: "Detecting Codex")
        } else if available {
            text = L10n.format(
                "model.llm_provider.codex.available_format",
                comment: "Codex available",
                availability?.cliVersion ?? L10n.localize("home.detail.meta.not_recorded", comment: "Not recorded")
            )
        } else {
            text = availability?.status.reason ?? L10n.localize("model.llm_provider.codex.not_checked", comment: "Codex not checked")
        }
        return HStack(spacing: 7) {
            Image(systemName: available ? "checkmark.circle" : "exclamationmark.circle")
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(available ? AppTheme.ColorToken.accent : AppTheme.ColorToken.secondaryText)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background((available ? AppTheme.ColorToken.accent : AppTheme.ColorToken.secondaryText).opacity(0.10))
        .clipShape(Capsule())
    }

    private func codexModelButton(_ model: String) -> some View {
        let selected = viewModel.codexSelectedModel == model
        return Button {
            viewModel.selectCodexModel(model)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark" : "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text(model)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? AppTheme.ColorToken.accent : AppTheme.ColorToken.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(selected ? AppTheme.ColorToken.accentSoft : AppTheme.ColorToken.controlBackground.opacity(0.78))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? AppTheme.ColorToken.accent.opacity(0.45) : AppTheme.ColorToken.subtleStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func providerRow(_ provider: LLMProviderRecord) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                guard !provider.isDefault, provider.enabled else { return }
                do {
                    try viewModel.setDefaultProvider(id: provider.id)
                } catch {
                    viewModel.report(error: error)
                }
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    LLMProviderIcon(
                        displayName: provider.displayName,
                        tint: AppTheme.ColorToken.accent,
                        isDefault: provider.isDefault
                    )
                    providerSummary(provider)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!provider.enabled)

            VStack(alignment: .trailing, spacing: 8) {
                if provider.isDefault {
                    Text(L10n.localize("model.llm_provider.current_use", comment: ""))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.accent)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(AppTheme.ColorToken.selectionBackground)
                        .clipShape(Capsule())
                }
                HStack(spacing: 8) {
                    Button {
                        editorRequest = LLMProviderEditorRequest(provider: provider)
                    } label: {
                        Image(systemName: LLMProviderActionIcon.edit)
                            .frame(width: 32, height: 32)
                            .appControlSurface(cornerRadius: 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.localize("model.llm_provider.edit", comment: ""))
                    Button {
                        Task {
                            await viewModel.testConnection(id: provider.id)
                        }
                    } label: {
                        Group {
                            if viewModel.testingProviderID == provider.id {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: LLMProviderActionIcon.testConnection)
                            }
                        }
                        .frame(width: 32, height: 32)
                        .appControlSurface(cornerRadius: 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.testingProviderID != nil)
                    .help(L10n.localize("model.llm_provider.test_connection", comment: ""))
                    Button {
                        viewModel.deleteProvider(id: provider.id)
                    } label: {
                        Image(systemName: LLMProviderActionIcon.delete)
                            .frame(width: 32, height: 32)
                            .appControlSurface(cornerRadius: 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .help(L10n.localize("model.llm_provider.delete", comment: ""))
                }
            }
        }
        .padding(18)
        .background(provider.isDefault ? AppTheme.ColorToken.selectionBackground.opacity(0.72) : AppTheme.ColorToken.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    provider.isDefault ? AppTheme.ColorToken.accent.opacity(0.5) : AppTheme.ColorToken.panelStroke,
                    lineWidth: provider.isDefault ? 1.5 : AppTheme.Border.panelLineWidth
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(provider.enabled ? 1 : 0.82)
    }

    private func providerSummary(_ provider: LLMProviderRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(provider.displayName)
                    .font(.system(size: 17, weight: .semibold))
                providerBadge(
                    provider.enabled ? L10n.localize("model.llm_provider.status_enabled", comment: "") : L10n.localize("model.llm_provider.status_disabled", comment: ""),
                    color: provider.enabled ? AppTheme.ColorToken.accent : AppTheme.ColorToken.secondaryText
                )
            }
            HStack(spacing: 6) {
                providerInfoChip(title: L10n.localize("model.llm_provider.label_model", comment: ""), value: provider.defaultModel)
                providerInfoChip(title: L10n.localize("model.llm_provider.label_address", comment: ""), value: provider.baseURL)
            }
            if let message = provider.lastHealthMessage {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(provider.enabled ? AppTheme.ColorToken.accent : .orange)
            }
            if let latency = provider.lastLatencyMS {
                Text("\(latency) ms")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.accent)
            }
        }
    }

    private func providerBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
    }

    private func providerInfoChip(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(AppTheme.ColorToken.controlBackground.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct LLMProviderIcon: View {
    let displayName: String
    let tint: Color
    let isDefault: Bool

    var body: some View {
        ProviderInitialBadge(
            text: displayName,
            tint: tint,
            background: isDefault ? AppTheme.ColorToken.selectionBackground : AppTheme.ColorToken.panelBackground,
            size: 46
        )
    }
}

private struct LLMProviderEditorRequest: Identifiable {
    let id = UUID()
    let provider: LLMProviderRecord?
}

private struct LLMProviderEditorSheet: View {
    let provider: LLMProviderRecord?
    @ObservedObject var viewModel: LLMProviderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var baseURL: String
    @State private var model: String
    @State private var apiKey = ""
    @State private var isEnabled: Bool
    @State private var showAPIKey = false
    @State private var validationErrors: [String: String] = [:]

    init(provider: LLMProviderRecord?, viewModel: LLMProviderViewModel) {
        self.provider = provider
        self.viewModel = viewModel
        _displayName = State(initialValue: provider?.displayName ?? "")
        _baseURL = State(initialValue: provider?.baseURL ?? "")
        _model = State(initialValue: provider?.defaultModel ?? "")
        _apiKey = State(initialValue: viewModel.APIKeyForEditing(providerID: provider?.id))
        _isEnabled = State(initialValue: provider?.enabled ?? true)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 16) {
                Text(provider == nil ? L10n.localize("model.llm_provider.sheet_title_add", comment: "") : L10n.localize("model.llm_provider.sheet_title_edit", comment: ""))
                    .font(.system(size: 24, weight: .semibold))

                providerField(
                    title: L10n.localize("model.llm_provider.field_name", comment: ""),
                    placeholder: L10n.localize("model.llm_provider.field_name_placeholder", comment: ""),
                    text: $displayName,
                    error: validationErrors["displayName"]
                )
                providerField(
                    title: L10n.localize("model.llm_provider.field_service_url", comment: ""),
                    placeholder: "https://api.example.com/v1",
                    text: $baseURL,
                    error: validationErrors["baseURL"]
                )
                providerField(
                    title: L10n.localize("model.llm_provider.field_model", comment: ""),
                    placeholder: L10n.localize("model.llm_provider.field_model_placeholder", comment: ""),
                    text: $model,
                    error: validationErrors["model"]
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.format("model.llm_provider.field_api_key_with_required_mark_format", comment: "", L10n.localize("model.llm_provider.field_api_key", comment: "")))
                        .font(.system(size: 13, weight: .medium))
                    HStack(spacing: 8) {
                        Group {
                            if showAPIKey {
                                TextField(L10n.localize("model.llm_provider.field_api_key", comment: ""), text: $apiKey.singleLineInput())
                            } else {
                                SecureField(L10n.localize("model.llm_provider.field_api_key", comment: ""), text: $apiKey.singleLineInput())
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1)
                        Button {
                            if showAPIKey {
                                apiKey = viewModel.APIKeyForEditing(providerID: provider?.id)
                                showAPIKey = false
                            } else {
                                if viewModel.isMaskedAPIKey(providerID: provider?.id, text: apiKey) {
                                    apiKey = viewModel.storedAPIKeyForEditing(providerID: provider?.id)
                                }
                                showAPIKey = true
                            }
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(showAPIKey ? L10n.localize("model.llm_provider.api_key_hide", comment: "") : L10n.localize("model.llm_provider.api_key_show", comment: ""))
                    }
                    if let error = validationErrors["apiKey"] {
                        fieldError(error)
                    } else if provider != nil {
                        Text(L10n.localize("model.llm_provider.keychain_hint", comment: ""))
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    }
                }

                Toggle(L10n.localize("model.llm_provider.toggle_enable", comment: ""), isOn: $isEnabled)
                    .toggleStyle(.switch)

                Spacer()
                HStack(spacing: 10) {
                    Spacer()
                    Button {
                        validate()
                        guard validationErrors.isEmpty else { return }
                        Task {
                            await viewModel.testDraftConnection(
                                providerID: provider?.id,
                                displayName: displayName,
                                baseURL: baseURL,
                                model: model,
                                apiKey: apiKey
                            )
                        }
                    } label: {
                        if viewModel.isTestingDraftConnection {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(L10n.localize("model.llm_provider.test", comment: ""))
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isTestingDraftConnection)
                    Button(L10n.localize("model.llm_provider.save", comment: "")) {
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(16)
            .help(L10n.localize("model.llm_provider.close", comment: ""))
        }
        .onChange(of: displayName) { validationErrors["displayName"] = nil }
        .onChange(of: baseURL) { validationErrors["baseURL"] = nil }
        .onChange(of: model) { validationErrors["model"] = nil }
        .onChange(of: apiKey) { validationErrors["apiKey"] = nil }
        .actionFeedbackOverlay(
            message: viewModel.lastActionMessage,
            error: viewModel.lastError,
            onDismiss: viewModel.clearFeedback
        )
    }

    private func providerField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        error: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title + " *")
                .font(.system(size: 13, weight: .medium))
            TextField(placeholder, text: text.singleLineInput())
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            if let error {
                fieldError(error)
            }
        }
    }

    private func fieldError(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.red)
    }

    private func validate() {
        validationErrors = viewModel.validationErrors(
            providerID: provider?.id,
            displayName: displayName,
            baseURL: baseURL,
            model: model,
            apiKey: apiKey
        )
    }

    private func save() {
        validate()
        guard validationErrors.isEmpty else {
            viewModel.report(
                error: LLMProviderViewModelError.requiredFields(
                    validationErrors.keys.sorted()
                )
            )
            return
        }
        do {
            try viewModel.saveProvider(
                id: provider?.id,
                displayName: displayName,
                baseURL: baseURL,
                model: model,
                apiKey: apiKey,
                temperature: provider?.temperature ?? 0.2,
                timeoutSeconds: provider?.timeoutSeconds ?? 30,
                enabled: isEnabled,
                isDefault: provider?.isDefault ?? viewModel.providers.isEmpty
            )
            dismiss()
        } catch {
            viewModel.report(error: error)
            AppLogger.general.error("Failed to save LLM Provider: \(error.localizedDescription)")
        }
    }
}

private extension Binding where Value == String {
    func singleLineInput() -> Binding<String> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = SingleLineTextInput.removingLineBreaks($0) }
        )
    }
}
