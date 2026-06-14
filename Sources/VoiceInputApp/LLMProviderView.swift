import SwiftUI

enum LLMProviderActionIcon {
    static let edit = "square.and.pencil"
    static let testConnection = "checkmark.circle"
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
                    Label("OpenAI 兼容模型", systemImage: "network")
                        .font(.system(size: 24, weight: .semibold))
                }
                Spacer()
                Button {
                    editorRequest = LLMProviderEditorRequest(provider: nil)
                } label: {
                    Label("添加", systemImage: "plus")
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
                .help("添加 Provider")
            }

            if viewModel.providers.isEmpty {
                Text("暂无 Provider")
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(AppTheme.ColorToken.panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
            } else {
                VStack(spacing: AppTheme.Spacing.grid) {
                    ForEach(viewModel.providers, id: \.id) { provider in
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
            onDismiss: viewModel.clearFeedback
        )
        .onAppear {
            viewModel.load()
        }
        .sheet(item: $editorRequest) { request in
            LLMProviderEditorSheet(
                provider: request.provider,
                viewModel: viewModel
            )
            .frame(width: 560, height: 540)
        }
    }

    private func providerRow(_ provider: LLMProviderRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            LLMProviderIcon(systemImage: "sparkles", tint: AppTheme.ColorToken.accent)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(provider.displayName)
                        .font(.system(size: 15, weight: .semibold))
                    if provider.isDefault {
                        providerBadge("默认", color: AppTheme.ColorToken.accent)
                    }
                    providerBadge(provider.enabled ? "已启用" : "已停用", color: provider.enabled ? AppTheme.ColorToken.accent : AppTheme.ColorToken.secondaryText)
                }
                HStack(spacing: 6) {
                    providerInfoChip(title: "模型", value: provider.defaultModel)
                    providerInfoChip(title: "地址", value: provider.baseURL)
                }
                if let message = provider.lastHealthMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                if let latency = provider.lastLatencyMS {
                    Text("\(latency) ms")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.ColorToken.accent)
                }
            }
            Spacer()
            Button {
                editorRequest = LLMProviderEditorRequest(provider: provider)
            } label: {
                Image(systemName: LLMProviderActionIcon.edit)
                    .frame(width: 32, height: 32)
                    .appControlSurface(cornerRadius: 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("编辑")
            Button {
                Task {
                    await viewModel.testConnection(id: provider.id)
                }
            } label: {
                Image(systemName: LLMProviderActionIcon.testConnection)
                    .frame(width: 32, height: 32)
                    .appControlSurface(cornerRadius: 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("测试连接")
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
            .help("删除")
        }
        .padding(AppTheme.Spacing.card)
        .background(AppTheme.ColorToken.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(AppTheme.ColorToken.panelStroke, lineWidth: AppTheme.Border.panelLineWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
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
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(tint.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.icon, style: .continuous))
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
                Text(provider == nil ? "添加 Provider" : "编辑 Provider")
                    .font(.system(size: 24, weight: .semibold))

                providerField(
                    title: "名称",
                    placeholder: "例如：主要模型",
                    text: $displayName,
                    error: validationErrors["displayName"]
                )
                providerField(
                    title: "Base URL",
                    placeholder: "https://api.example.com/v1",
                    text: $baseURL,
                    error: validationErrors["baseURL"]
                )
                providerField(
                    title: "Model",
                    placeholder: "模型名称",
                    text: $model,
                    error: validationErrors["model"]
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key *")
                        .font(.system(size: 13, weight: .medium))
                    HStack(spacing: 8) {
                        Group {
                            if showAPIKey {
                                TextField("API Key", text: $apiKey)
                            } else {
                                SecureField("API Key", text: $apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
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
                        .help(showAPIKey ? "隐藏 API Key" : "显示 API Key")
                    }
                    if let error = validationErrors["apiKey"] {
                        fieldError(error)
                    } else if provider != nil {
                        Text("已从 Keychain 载入；不修改即可保留原值")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    }
                }

                Toggle("启用此模型配置", isOn: $isEnabled)
                    .toggleStyle(.switch)

                Spacer()
                HStack(spacing: 10) {
                    Spacer()
                    Button("测试") {
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
                    }
                    .buttonStyle(.bordered)
                    Button("保存") {
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
            .help("关闭")
        }
        .onChange(of: displayName) { validationErrors["displayName"] = nil }
        .onChange(of: baseURL) { validationErrors["baseURL"] = nil }
        .onChange(of: model) { validationErrors["model"] = nil }
        .onChange(of: apiKey) { validationErrors["apiKey"] = nil }
    }

    private func providerField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        error: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) *")
                .font(.system(size: 13, weight: .medium))
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
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
                timeoutSeconds: provider?.timeoutSeconds ?? 8,
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
