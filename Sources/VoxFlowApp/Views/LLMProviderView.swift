import SwiftUI

enum LLMProviderActionIcon {
    static let edit = "square.and.pencil"
    static let testConnection = "antenna.radiowaves.left.and.right"
    static let delete = "trash"
}

enum LLMProviderViewSection: Equatable {
    case regularProviders
    case localAgentProviders
}

enum LLMProviderViewMode: Equatable {
    case llm
    case agent
    case combined

    var visibleSections: [LLMProviderViewSection] {
        switch self {
        case .llm:
            return [.regularProviders]
        case .agent:
            return [.localAgentProviders]
        case .combined:
            return [.regularProviders, .localAgentProviders]
        }
    }
}

struct LocalAgentProviderCardPresentation: Equatable {
    let subtitleKey: String
    let detectButtonKey: String
    let configurationTitleKey: String
    let showsBuiltinBadge: Bool
    let usesDefaultLLMProvider: Bool

    init(descriptor: LocalAgentProviderDescriptor) {
        let isBuiltin = descriptor.providerID == AgentProviderRegistry.voxflowAgent.providerID
        subtitleKey = isBuiltin
            ? "model.llm_provider.builtin_agent.subtitle"
            : "model.llm_provider.local_agent.subtitle"
        detectButtonKey = isBuiltin
            ? "model.llm_provider.builtin_agent.detect"
            : "model.llm_provider.codex.detect"
        configurationTitleKey = isBuiltin
            ? "model.llm_provider.builtin_agent.configuration_title"
            : "model.llm_provider.codex.model_section"
        showsBuiltinBadge = isBuiltin
        usesDefaultLLMProvider = isBuiltin
    }
}

struct LLMProviderView: View {
    @ObservedObject var viewModel: LLMProviderViewModel
    var mode: LLMProviderViewMode = .combined
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
                if mode.visibleSections.contains(.regularProviders) {
                    Button {
                        Task {
                            await viewModel.testAllConnections()
                        }
                    } label: {
                        Label {
                            Text(L10n.localize("model.llm_provider.test_all", comment: ""))
                        } icon: {
                            if viewModel.isTestingAllProviders {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: LLMProviderActionIcon.testConnection)
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .appControlSurface(cornerRadius: AppTheme.Radius.control)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isTestingAllProviders || viewModel.testingProviderID != nil || testableRegularProviders.isEmpty)
                    .help(L10n.localize("model.llm_provider.test_all_help", comment: ""))

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
                    .disabled(viewModel.isTestingAllProviders)
                    .help(L10n.localize("model.llm_provider.add_service_help", comment: ""))
                }
            }

            if mode.visibleSections.contains(.regularProviders) {
                customProviderSection
            }
            if mode.visibleSections.contains(.localAgentProviders) {
                localAgentProviderSection
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
        }
        .sheet(item: $editorRequest) { request in
            LLMProviderEditorSheet(
                provider: request.provider,
                viewModel: viewModel
            )
            .frame(width: 680, height: 640)
        }
    }

    private var regularProviders: [LLMProviderRecord] {
        viewModel.providers.filter { !$0.isLocalAgentProvider }
    }

    private var testableRegularProviders: [LLMProviderRecord] {
        regularProviders.filter(LLMProviderAvailability.isUsableProvider)
    }

    private var customProviderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            providerSectionHeader(
                title: L10n.localize("model.llm_provider.custom_section.title", comment: "Custom LLM provider section title"),
                subtitle: L10n.localize("model.llm_provider.custom_section.subtitle", comment: "Custom LLM provider section subtitle")
            )

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
        }
    }

    private var localAgentProviderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            providerSectionHeader(
                title: L10n.localize("model.llm_provider.agent_section.title", comment: "Agent LLM provider section title"),
                subtitle: L10n.localize("model.llm_provider.agent_section.subtitle", comment: "Agent LLM provider section subtitle")
            )
            localAgentProviderCards
        }
    }

    private var localAgentProviderCards: some View {
        LazyVStack(spacing: AppTheme.Spacing.grid) {
            ForEach(AgentProviderRegistry.enabledRuntimeProviders, id: \.providerID) { descriptor in
                localAgentSettingsCard(descriptor)
            }
        }
    }

    private func providerSectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func localAgentSettingsCard(_ descriptor: LocalAgentProviderDescriptor) -> some View {
        let selected = viewModel.isLocalAgentProviderSelected(providerID: descriptor.providerID)
        let presentation = LocalAgentProviderCardPresentation(descriptor: descriptor)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                LLMProviderIcon(
                    resourceName: AgentProviderIconResource.resourceName(providerID: descriptor.providerID),
                    displayName: descriptor.displayName,
                    tint: AppTheme.ColorToken.accent,
                    isDefault: selected,
                    size: 44
                )
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(descriptor.displayName)
                            .font(.system(size: 18, weight: .semibold))
                        if presentation.showsBuiltinBadge {
                            providerBadge(
                                L10n.localize("model.llm_provider.builtin_agent.badge", comment: "Builtin agent badge"),
                                color: AppTheme.ColorToken.accent
                            )
                        }
                    }
                    Text(L10n.localize(presentation.subtitleKey, comment: "Local agent subtitle"))
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle(
                    selected
                        ? L10n.localize("model.llm_provider.local_agent.selected_short", comment: "Local agent selected short")
                        : L10n.localize("model.llm_provider.local_agent.unselected_short", comment: "Local agent unselected short"),
                    isOn: Binding(
                        get: { selected },
                        set: { newValue in
                            Task {
                                await viewModel.setLocalAgentProviderEnabledAfterDetection(
                                    providerID: descriptor.providerID,
                                    newValue
                                )
                            }
                        }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.large)
            }

            HStack(spacing: 10) {
                localAgentAvailabilityPill(descriptor)
                if selected {
                    providerBadge(L10n.localize("model.llm_provider.current_use", comment: ""), color: AppTheme.ColorToken.accent)
                }
                Spacer()
                Button {
                    Task { await viewModel.detectLocalAgentProvider(providerID: descriptor.providerID, forceRefresh: true) }
                } label: {
                    Label(
                        L10n.localize(presentation.detectButtonKey, comment: "Detect local agent"),
                        systemImage: "checkmark.seal"
                    )
                    .frame(height: 32)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.checkingLocalAgentProviderIDs.contains(descriptor.providerID))
            }

            if selected {
                VStack(alignment: .leading, spacing: 9) {
                    Text(L10n.localize(presentation.configurationTitleKey, comment: "Local agent configuration section"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    if presentation.usesDefaultLLMProvider {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.ColorToken.accent)
                            Text(L10n.localize("model.llm_provider.builtin_agent.default_llm_note", comment: "Builtin agent default LLM note"))
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.ColorToken.panelBackground.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        LocalAgentModelPicker(
                            selectedModel: viewModel.localAgentSelectedModel(providerID: descriptor.providerID),
                            models: viewModel.localAgentModelIDs(providerID: descriptor.providerID),
                            onSelect: { model in
                                viewModel.selectLocalAgentModel(providerID: descriptor.providerID, model: model)
                            }
                        )
                    }
                }
            }
        }
        .padding(18)
        .background(selected ? AppTheme.ColorToken.selectionBackground.opacity(0.72) : AppTheme.ColorToken.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    selected ? AppTheme.ColorToken.accent.opacity(0.5) : AppTheme.ColorToken.panelStroke,
                    lineWidth: selected ? 1.5 : AppTheme.Border.panelLineWidth
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func localAgentAvailabilityPill(_ descriptor: LocalAgentProviderDescriptor) -> some View {
        let availability = viewModel.localAgentAvailability(providerID: descriptor.providerID)
        let available = availability?.isAvailable == true
        let text: String
        if viewModel.checkingLocalAgentProviderIDs.contains(descriptor.providerID) {
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
                        provider: provider,
                        displayName: provider.displayName,
                        tint: AppTheme.ColorToken.accent,
                        isDefault: provider.isDefault,
                        usesDisplayNameFallback: false
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
                    .disabled(viewModel.testingProviderID != nil || viewModel.isTestingAllProviders)
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
    var provider: LLMProviderRecord? = nil
    var templateID: String? = nil
    var resourceName: String? = nil
    let displayName: String
    let tint: Color
    let isDefault: Bool
    var size: CGFloat = 46
    var usesDisplayNameFallback = true

    private var image: NSImage? {
        if let resourceName {
            return LLMProviderIconResource.load(resourceName: resourceName)
        }
        if let templateID {
            return LLMProviderIconResource.load(templateID: templateID)
        }
        if let provider {
            return LLMProviderIconResource.load(provider: provider)
        }
        guard usesDisplayNameFallback else { return nil }
        if let resourceName = LLMProviderIconResource.resourceName(displayName: displayName) {
            return LLMProviderIconResource.load(resourceName: resourceName)
        }
        return nil
    }

    var body: some View {
        if let image {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(isDefault ? AppTheme.ColorToken.selectionBackground : AppTheme.ColorToken.panelBackground)
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
                )
                .overlay {
                    Image(nsImage: image)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .foregroundStyle(tint)
                        .padding(size * 0.23)
                }
                .accessibilityHidden(true)
        } else {
            ProviderInitialBadge(
                text: displayName,
                tint: tint,
                background: isDefault ? AppTheme.ColorToken.selectionBackground : AppTheme.ColorToken.panelBackground,
                size: size
            )
        }
    }
}

private struct LocalAgentModelPicker: View {
    let selectedModel: String
    let models: [String]
    let onSelect: (String) -> Void
    @State private var isPresented = false
    @State private var searchText = ""

    private var normalizedSearchText: String {
        SingleLineTextInput.normalized(searchText)
    }

    private var filteredModels: [String] {
        guard !normalizedSearchText.isEmpty else { return models }
        return models.filter { $0.localizedCaseInsensitiveContains(normalizedSearchText) }
    }

    private var canUseSearchText: Bool {
        !normalizedSearchText.isEmpty &&
            !models.contains { $0.caseInsensitiveCompare(normalizedSearchText) == .orderedSame }
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                Text(selectedModel.isEmpty ? L10n.localize("model.llm_provider.local_agent.manual_model_placeholder", comment: "") : selectedModel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selectedModel.isEmpty ? AppTheme.ColorToken.secondaryText : AppTheme.ColorToken.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
            .background(AppTheme.ColorToken.controlBackground.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            pickerPopover
        }
    }

    private var pickerPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                TextField(
                    L10n.localize("model.llm_provider.local_agent.search_model_placeholder", comment: ""),
                    text: $searchText.singleLineInput()
                )
                .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(AppTheme.ColorToken.controlBackground.opacity(0.78))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredModels, id: \.self) { model in
                        modelRow(model)
                    }
                    if canUseSearchText {
                        modelRow(normalizedSearchText, isCustom: true)
                    } else if filteredModels.isEmpty {
                        Text(L10n.localize("model.llm_provider.local_agent.no_matching_models", comment: ""))
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
            .frame(width: 320, height: 240)
        }
        .padding(12)
        .background(AppTheme.ColorToken.panelBackground)
    }

    private func modelRow(_ model: String, isCustom: Bool = false) -> some View {
        let selected = selectedModel.caseInsensitiveCompare(model) == .orderedSame
        return Button {
            onSelect(model)
            isPresented = false
            searchText = ""
        } label: {
            HStack(spacing: 9) {
                Image(systemName: selected ? "checkmark" : (isCustom ? "plus.circle" : "sparkles"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? AppTheme.ColorToken.accent : AppTheme.ColorToken.secondaryText)
                Text(isCustom ? L10n.format("model.llm_provider.local_agent.use_search_model_format", comment: "", model) : model)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(selected ? AppTheme.ColorToken.accentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    @Environment(\.openURL) private var openURL
    @State private var displayName: String
    @State private var baseURL: String
    @State private var model: String
    @State private var apiKey = ""
    @State private var isEnabled: Bool
    @State private var showAPIKey = false
    @State private var suppressAPIKeyModelInvalidation = false
    @State private var validationErrors: [String: String] = [:]
    @State private var selectedTemplateID = LLMProviderTemplateCatalog.customTemplateID
    @State private var selectedTemplate: LLMProviderTemplate?
    @State private var draftModelIDs: [String]
    @State private var allowsManualModelEntry = false

    init(provider: LLMProviderRecord?, viewModel: LLMProviderViewModel) {
        self.provider = provider
        self.viewModel = viewModel
        let inferredTemplateID = provider
            .flatMap { LLMProviderTemplateCatalog.templateID(baseURL: $0.baseURL) } ?? LLMProviderTemplateCatalog.customTemplateID
        let inferredTemplate = LLMProviderTemplateCatalog.template(id: inferredTemplateID)
        _displayName = State(initialValue: provider?.displayName ?? "")
        _baseURL = State(initialValue: provider?.baseURL ?? "")
        _model = State(initialValue: provider?.defaultModel ?? "")
        _apiKey = State(initialValue: viewModel.APIKeyForEditing(providerID: provider?.id))
        _isEnabled = State(initialValue: provider?.enabled ?? true)
        _selectedTemplateID = State(initialValue: inferredTemplateID)
        _selectedTemplate = State(initialValue: inferredTemplate)
        _draftModelIDs = State(initialValue: provider.map { viewModel.modelIDsByProviderID[$0.id] ?? [] } ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    providerOverview
                    templatePicker
                    formDivider
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
                    formDivider
                    apiKeyField
                    modelPicker
                    formDivider
                    enableRow
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
            }
            .frame(maxHeight: 462)
            Divider()
            actionBar
        }
        .frame(width: 680, height: 640)
        .background(AppTheme.ColorToken.panelBackground)
        .onChange(of: displayName) { _, _ in validationErrors["displayName"] = nil }
        .onChange(of: baseURL) { _, _ in
            validationErrors["baseURL"] = nil
            draftModelIDs = []
        }
        .onChange(of: model) { _, _ in validationErrors["model"] = nil }
        .onChange(of: apiKey) { _, _ in
            validationErrors["apiKey"] = nil
            if suppressAPIKeyModelInvalidation {
                suppressAPIKeyModelInvalidation = false
                return
            }
            draftModelIDs = []
        }
        .onChange(of: selectedTemplateID) { _, newValue in applyTemplate(id: newValue) }
        .actionFeedbackOverlay(
            message: viewModel.lastActionMessage,
            error: viewModel.lastError,
            onDismiss: viewModel.clearFeedback
        )
        .tint(AppTheme.ColorToken.accent)
    }

    private var requiresAPIKey: Bool {
        if let selectedTemplate {
            return selectedTemplate.requiresAPIKey
        }
        if LLMProviderTemplateCatalog.isLoopbackBaseURL(baseURL) {
            return false
        }
        return provider?.requiresAPIKey ?? true
    }

    private var sheetHeader: some View {
        HStack(spacing: 12) {
            Text(provider == nil ? L10n.localize("model.llm_provider.sheet_title_add", comment: "") : L10n.localize("model.llm_provider.sheet_title_edit", comment: ""))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.localize("model.llm_provider.close", comment: ""))
        }
        .padding(.leading, 28)
        .padding(.trailing, 20)
        .frame(height: 66)
    }

    private var activeTemplate: LLMProviderTemplate? {
        selectedTemplate
    }

    private var activeTemplateID: String? {
        if selectedTemplateID != LLMProviderTemplateCatalog.customTemplateID {
            return selectedTemplateID
        }
        return nil
    }

    private var activeIconResourceName: String? {
        if let activeTemplateID,
           let resourceName = LLMProviderIconResource.resourceName(templateID: activeTemplateID) {
            return resourceName
        }
        return nil
    }

    private var overviewTitle: String {
        if let selectedTemplate {
            return selectedTemplate.displayName
        }
        return L10n.localize("model.llm_provider.template_custom", comment: "")
    }

    private var overviewSubtitle: String {
        if !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return baseURL
        }
        return L10n.localize("model.llm_provider.template_hint", comment: "")
    }

    private var providerOverview: some View {
        HStack(spacing: 14) {
            LLMProviderIcon(
                resourceName: activeIconResourceName,
                displayName: overviewTitle,
                tint: AppTheme.ColorToken.accent,
                isDefault: true,
                size: 52,
                usesDisplayNameFallback: false
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(overviewTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(overviewSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if let url = activeTemplate?.apiKeyURL {
                Button {
                    openURL(url)
                } label: {
                    Label(
                        activeTemplate?.requiresAPIKey == false
                            ? L10n.localize("model.llm_provider.open_docs", comment: "")
                            : L10n.localize("model.llm_provider.get_api_key", comment: ""),
                        systemImage: "arrow.up.right.square"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .frame(height: 32)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(AppTheme.ColorToken.controlBackground.opacity(0.56))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var templatePicker: some View {
        formRow(
            title: L10n.localize("model.llm_provider.template_label", comment: ""),
            hint: L10n.localize("model.llm_provider.template_hint", comment: "")
        ) {
            Picker("", selection: $selectedTemplateID) {
                Text(L10n.localize("model.llm_provider.template_custom", comment: ""))
                    .tag(LLMProviderTemplateCatalog.customTemplateID)
                ForEach(LLMProviderTemplateCatalog.templates) { template in
                    Text(template.displayName).tag(template.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var modelPicker: some View {
        formRow(
            title: L10n.localize("model.llm_provider.field_model", comment: ""),
            isRequired: true,
            error: validationErrors["model"],
            hint: draftModelIDs.isEmpty
                ? L10n.localize("model.llm_provider.model_list_hint", comment: "")
                : L10n.format("model.llm_provider.model_list_loaded_format", comment: "", draftModelIDs.count)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    modelControl
                        .frame(maxWidth: .infinity)

                    if !draftModelIDs.isEmpty {
                        Button(
                            allowsManualModelEntry
                                ? L10n.localize("model.llm_provider.model_choose_from_list", comment: "")
                                : L10n.localize("model.llm_provider.model_manual_entry", comment: "")
                        ) {
                            allowsManualModelEntry.toggle()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Button {
                    Task { await fetchModels() }
                } label: {
                    if viewModel.isFetchingDraftModels {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(L10n.localize("model.llm_provider.fetch_models", comment: ""), systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isFetchingDraftModels)
            }
        }
    }

    @ViewBuilder
    private var modelControl: some View {
        if !draftModelIDs.isEmpty && !allowsManualModelEntry {
            Picker("", selection: $model) {
                if model.isEmpty {
                    Text(L10n.localize("model.llm_provider.model_picker_placeholder", comment: ""))
                        .tag("")
                }
                ForEach(draftModelIDs, id: \.self) { modelID in
                    Text(modelID).tag(modelID)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        } else {
            TextField(L10n.localize("model.llm_provider.field_model_placeholder", comment: ""), text: $model.singleLineInput())
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
        }
    }

    private var apiKeyField: some View {
        formRow(
            title: L10n.localize("model.llm_provider.field_api_key", comment: ""),
            isRequired: requiresAPIKey,
            error: validationErrors["apiKey"],
            hint: requiresAPIKey ? L10n.localize("model.llm_provider.keychain_hint", comment: "") : L10n.localize("model.llm_provider.no_api_key_hint", comment: "")
        ) {
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
                        let maskedKey = viewModel.APIKeyForEditing(providerID: provider?.id)
                        if !maskedKey.isEmpty {
                            suppressAPIKeyModelInvalidation = true
                            apiKey = maskedKey
                        }
                        showAPIKey = false
                    } else {
                        if viewModel.isMaskedAPIKey(providerID: provider?.id, text: apiKey) {
                            suppressAPIKeyModelInvalidation = true
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
                if selectedTemplate?.requiresAPIKey == false {
                    Text(L10n.localize("model.llm_provider.no_api_key_required", comment: ""))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.accent)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(AppTheme.ColorToken.selectionBackground)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var enableRow: some View {
        formRow(
            title: L10n.localize("model.llm_provider.toggle_enable", comment: ""),
            hint: L10n.localize("model.llm_provider.toggle_enable_hint", comment: "")
        ) {
            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var actionBar: some View {
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
                        apiKey: apiKey,
                        requiresAPIKey: requiresAPIKey
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
        .padding(.horizontal, 28)
        .frame(height: 72)
    }

    private func providerField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        error: String?
    ) -> some View {
        formRow(title: title, isRequired: true, error: error) {
            TextField(placeholder, text: text.singleLineInput())
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
        }
    }

    private var formDivider: some View {
        Rectangle()
            .fill(AppTheme.ColorToken.subtleStroke.opacity(0.55))
            .frame(height: 1)
            .padding(.leading, 124)
    }

    private func formRow<Content: View>(
        title: String,
        isRequired: Bool = false,
        error: String? = nil,
        hint: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(isRequired ? "\(title) *" : title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .frame(width: 110, alignment: .trailing)
                    .lineLimit(1)

                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error {
                fieldAuxiliary { fieldError(error) }
            } else if let hint, !hint.isEmpty {
                fieldAuxiliary {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
            }
        }
    }

    private func fieldAuxiliary<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 14) {
            Spacer()
                .frame(width: 110)
            content()
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
            apiKey: apiKey,
            requiresAPIKey: requiresAPIKey
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
                timeoutSeconds: provider?.timeoutSeconds ?? selectedTemplate?.timeoutSeconds ?? 30,
                enabled: isEnabled,
                isDefault: provider?.isDefault ?? viewModel.providers.isEmpty,
                requiresAPIKey: requiresAPIKey
            )
            dismiss()
        } catch {
            viewModel.report(error: error)
            AppLogger.general.error("Failed to save LLM Provider: \(error.localizedDescription)")
        }
    }

    private func applyTemplate(id: String) {
        guard id != LLMProviderTemplateCatalog.customTemplateID,
              let template = LLMProviderTemplateCatalog.template(id: id) else {
            selectedTemplate = nil
            validationErrors = [:]
            return
        }
        selectedTemplate = template
        displayName = template.displayName
        baseURL = template.baseURL
        model = template.defaultModel
        if !template.requiresAPIKey {
            apiKey = ""
            showAPIKey = false
        }
        draftModelIDs = []
        allowsManualModelEntry = false
        validationErrors = [:]
    }

    private func fetchModels() async {
        let models = await viewModel.fetchDraftModels(
            providerID: provider?.id,
            baseURL: baseURL,
            apiKey: apiKey,
            requiresAPIKey: requiresAPIKey,
            timeoutSeconds: provider?.timeoutSeconds ?? selectedTemplate?.timeoutSeconds ?? 30
        )
        draftModelIDs = models
        allowsManualModelEntry = models.isEmpty
        if !models.isEmpty && !models.contains(model) {
            model = ""
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
