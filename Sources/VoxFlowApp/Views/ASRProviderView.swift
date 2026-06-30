import SwiftUI

struct ASRProviderView: View {
    @ObservedObject var viewModel: ASRProviderViewModel
    var embedded = false
    @State private var showGroqAPIKey = false
    @State private var showAliyunDashScopeAPIKey = false
    @State private var showTencentCloudCredentials = false
    @State private var showVolcengineCredentials = false
    @State private var expandedProviderID: String?

    private var providerColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: AppTheme.Spacing.grid),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            if !embedded {
                Label(L10n.localize("asr.provider.title", comment: "ASR provider view title"), systemImage: "mic.badge.plus")
                    .font(.system(size: 24, weight: .semibold))
            }

            scopeAndTagFilterBar

            LazyVGrid(columns: providerColumns, spacing: AppTheme.Spacing.grid) {
                ForEach(viewModel.visibleProviders, id: \.id) { provider in
                    providerCard(provider)
                }
            }
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
    }

    private var scopeAndTagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ASRProviderScope.allCases) { scope in
                    scopeFilterButton(scope)
                }
                if !viewModel.availableTags.isEmpty {
                    Rectangle()
                        .fill(AppTheme.ColorToken.panelStroke)
                        .frame(width: 1, height: 24)
                        .padding(.horizontal, 4)
                    ForEach(viewModel.availableTags, id: \.self) { tag in
                        tagFilterButton(tag)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(AppTheme.ColorToken.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .stroke(AppTheme.ColorToken.panelStroke)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
    }

    private func scopeFilterButton(_ scope: ASRProviderScope) -> some View {
        let isSelected = viewModel.providerScope == scope
        return Button {
            viewModel.selectProviderScope(scope)
        } label: {
            Label(scope.title, systemImage: scope.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            isSelected
                ? AppTheme.ColorToken.accent
                : AppTheme.ColorToken.secondaryText
        )
        .background(
            isSelected
                ? AppTheme.ColorToken.selectionBackground
                : AppTheme.ColorToken.panelBackground
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                .stroke(
                    isSelected
                        ? AppTheme.ColorToken.accent.opacity(0.35)
                        : AppTheme.ColorToken.panelStroke
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
    }

    private func tagFilterButton(_ tag: String) -> some View {
        let isSelected = viewModel.selectedTags.contains(tag)
        return Button {
            viewModel.toggleTag(tag)
        } label: {
            Text(tag)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 11)
                .frame(height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            isSelected
                ? AppTheme.ColorToken.accent
                : AppTheme.ColorToken.secondaryText
        )
        .background(
            isSelected
                ? AppTheme.ColorToken.selectionBackground
                : AppTheme.ColorToken.panelBackground
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
                .stroke(
                    isSelected
                        ? AppTheme.ColorToken.accent.opacity(0.35)
                        : AppTheme.ColorToken.panelStroke
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous))
    }

    private func providerCard(_ provider: ASRProviderDescriptor) -> some View {
        let interaction = ASRProviderCardInteractionPresentation(provider: provider)
        let isExpanded = isProviderExpanded(provider)
        return VStack(alignment: .leading, spacing: isExpanded ? 12 : 0) {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    providerIcon(provider, compact: !isExpanded)
                    providerSummary(provider, isExpanded: isExpanded)
                    Spacer(minLength: 0)
                }

                if provider.isDefault {
                    Text(L10n.localize("asr.provider.current_badge", comment: "Current ASR provider badge"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.accent)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(AppTheme.ColorToken.selectionBackground)
                        .clipShape(Capsule())
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        toggleExpandedProvider(provider)
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(
                    isExpanded
                        ? L10n.localize("asr.provider.collapse_configuration", comment: "Collapse provider configuration")
                        : L10n.localize("asr.provider.expand_configuration", comment: "Expand provider configuration")
                )
            }

            if isExpanded {
                providerTagsRow(provider, interaction: interaction)
                providerExpandedControls(provider)
            }
        }
        .padding(.horizontal, isExpanded ? 18 : 14)
        .padding(.vertical, isExpanded ? 18 : 10)
        .background {
            cardSelectionSurface(provider, interaction: interaction)
        }
        .background(
            provider.isDefault
                ? AppTheme.ColorToken.selectionBackground.opacity(0.72)
                : AppTheme.ColorToken.panelBackground
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    provider.isDefault
                        ? AppTheme.ColorToken.accent.opacity(0.5)
                        : AppTheme.ColorToken.panelStroke,
                    lineWidth: provider.isDefault ? 1.5 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(provider.isAvailable ? 1 : 0.82)
    }

    private func isProviderExpanded(_ provider: ASRProviderDescriptor) -> Bool {
        expandedProviderID == provider.id
    }

    private func toggleExpandedProvider(_ provider: ASRProviderDescriptor) {
        if expandedProviderID == provider.id {
            expandedProviderID = nil
        } else {
            expandedProviderID = provider.id
        }
    }

    private func providerTagsRow(
        _ provider: ASRProviderDescriptor,
        interaction: ASRProviderCardInteractionPresentation
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ASRProviderTagPresentation.cardTags(for: provider), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(AppTheme.ColorToken.pageBackground)
                        .clipShape(Capsule())
                }
            }
        }
        .allowsHitTesting(!interaction.isSelectionPassthroughRegion(.tags))
    }

    @ViewBuilder
    private func providerExpandedControls(_ provider: ASRProviderDescriptor) -> some View {
        if provider.supportsLocalModelControls {
            localModelControls(provider)
        }
        if provider.id == ASRProviderID.groqWhisper {
            groqConfigurationControls
        }
        if provider.id == ASRProviderID.tencentCloudASR {
            tencentCloudConfigurationControls
        }
        if provider.id == ASRProviderID.qwenCloudASR {
            aliyunDashScopeConfigurationControls
        }
        if provider.id == ASRProviderID.volcengineDoubao {
            volcengineConfigurationControls
        }
    }

    private var groqConfigurationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack(spacing: 8) {
                Text(L10n.localize("asr.provider.groq.configuration_title", comment: "Groq configuration title"))
                    .font(.system(size: 13, weight: .semibold))
                if viewModel.hasStoredGroqAPIKey {
                    Text(L10n.localize("asr.provider.api_key_saved", comment: "API key saved status"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.green)
                }
            }
            HStack(spacing: 8) {
                Group {
                    if showGroqAPIKey {
                        TextField(L10n.localize("asr.provider.groq.api_key_placeholder", comment: "Groq API key placeholder"), text: $viewModel.groqAPIKeyInput)
                    } else {
                        SecureField(L10n.localize("asr.provider.groq.api_key_placeholder", comment: "Groq API key placeholder"), text: $viewModel.groqAPIKeyInput)
                    }
                }
                .textFieldStyle(.roundedBorder)
                Button {
                    if showGroqAPIKey {
                        viewModel.groqAPIKeyInput = viewModel.groqAPIKeyForEditing()
                        showGroqAPIKey = false
                    } else {
                        if viewModel.isMaskedGroqAPIKey(text: viewModel.groqAPIKeyInput) {
                            viewModel.groqAPIKeyInput = viewModel.storedGroqAPIKeyForEditing()
                        }
                        showGroqAPIKey = true
                    }
                } label: {
                    Image(systemName: showGroqAPIKey ? "eye.slash" : "eye")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(showGroqAPIKey ? L10n.localize("asr.provider.hide_api_key", comment: "Hide API key help") : L10n.localize("asr.provider.show_api_key", comment: "Show API key help"))
            }
            Picker(L10n.localize("asr.provider.model", comment: "Model picker label"), selection: $viewModel.groqModelInput) {
                ForEach(viewModel.supportedGroqModels) { model in
                    Text(model.title).tag(model.id)
                }
            }
            .pickerStyle(.menu)
            HStack(spacing: 8) {
                Button(L10n.localize("asr.provider.save_configuration", comment: "Save ASR provider configuration")) {
                    viewModel.saveGroqConfiguration()
                }
                Button(viewModel.isTestingGroq ? L10n.localize("asr.provider.testing_connection", comment: "Testing connection") : L10n.localize("asr.provider.test_connection", comment: "Test connection")) {
                    Task { await viewModel.testGroqConnection() }
                }
                .disabled(viewModel.isTestingGroq)
                if viewModel.hasStoredGroqAPIKey {
                    Button(L10n.localize("asr.provider.delete_api_key", comment: "Delete API key"), role: .destructive) {
                        viewModel.deleteGroqAPIKey()
                    }
                }
            }
            .buttonStyle(.bordered)
            Text(L10n.localize("asr.provider.groq.privacy_note", comment: "Groq privacy note"))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
        .settingsRow()
    }

    private var tencentCloudConfigurationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack(spacing: 8) {
                Text(L10n.localize("asr.provider.tencent.configuration_title", comment: "Tencent Cloud configuration title"))
                    .font(.system(size: 13, weight: .semibold))
                if viewModel.hasStoredTencentCloudCredentials {
                    Text(L10n.localize("asr.provider.credentials_saved", comment: "Credentials saved status"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.green)
                }
            }
            Text(L10n.localize("asr.provider.tencent.description", comment: "Tencent Cloud ASR description"))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            VStack(alignment: .leading, spacing: 8) {
                tencentCredentialField(L10n.localize("asr.provider.tencent.app_id", comment: "Tencent Cloud app ID"), text: $viewModel.tencentAppIDInput, isSecret: false)
                tencentCredentialField(L10n.localize("asr.provider.tencent.secret_id", comment: "Tencent Cloud secret ID"), text: $viewModel.tencentSecretIDInput, isSecret: false)
                HStack(spacing: 8) {
                    tencentCredentialField(L10n.localize("asr.provider.tencent.secret_key", comment: "Tencent Cloud secret key"), text: $viewModel.tencentSecretKeyInput, isSecret: true)
                    Button {
                        if showTencentCloudCredentials {
                            let stored = viewModel.storedTencentCloudCredentialsForEditing()
                            viewModel.tencentAppIDInput = stored.appID
                            viewModel.tencentSecretIDInput = stored.secretID
                            viewModel.tencentSecretKeyInput = stored.secretKey.isEmpty
                                ? ""
                                : ASRProviderViewModel.storedTencentSecretMask
                            showTencentCloudCredentials = false
                        } else {
                            let stored = viewModel.storedTencentCloudCredentialsForEditing()
                            if viewModel.isMaskedTencentSecret(text: viewModel.tencentSecretKeyInput) {
                                viewModel.tencentSecretKeyInput = stored.secretKey
                            }
                            showTencentCloudCredentials = true
                        }
                    } label: {
                        Image(systemName: showTencentCloudCredentials ? "eye.slash" : "eye")
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(showTencentCloudCredentials ? L10n.localize("asr.provider.tencent.hide_credentials", comment: "Hide Tencent Cloud credentials") : L10n.localize("asr.provider.tencent.show_credentials", comment: "Show Tencent Cloud credentials"))
                }
            }
            HStack(spacing: 8) {
                Button(L10n.localize("asr.provider.save_configuration", comment: "Save ASR provider configuration")) {
                    viewModel.saveTencentCloudConfiguration()
                }
                Button(viewModel.isTestingTencentCloud ? L10n.localize("asr.provider.testing_connection", comment: "Testing connection") : L10n.localize("asr.provider.test_connection", comment: "Test connection")) {
                    Task { await viewModel.testTencentCloudConnection() }
                }
                .disabled(viewModel.isTestingTencentCloud)
                if viewModel.hasStoredTencentCloudCredentials {
                    Button(L10n.localize("asr.provider.delete_credentials", comment: "Delete credentials"), role: .destructive) {
                        viewModel.deleteTencentCloudCredentials()
                    }
                }
            }
            .buttonStyle(.bordered)
            Text(L10n.localize("asr.provider.tencent.privacy_note", comment: "Tencent Cloud privacy note"))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
        .settingsRow()
    }

    @ViewBuilder
    private func tencentCredentialField(_ placeholder: String, text: Binding<String>, isSecret: Bool) -> some View {
        if isSecret && !showTencentCloudCredentials {
            SecureField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        } else {
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var aliyunDashScopeConfigurationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack(spacing: 8) {
                Text(L10n.localize("asr.provider.aliyun.configuration_title", comment: "Aliyun Bailian configuration title"))
                    .font(.system(size: 13, weight: .semibold))
                if viewModel.hasStoredAliyunDashScopeAPIKey {
                    Text(L10n.localize("asr.provider.api_key_saved", comment: "API key saved status"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.green)
                }
            }
            Text(L10n.localize("asr.provider.aliyun.description", comment: "Aliyun DashScope description"))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            HStack(spacing: 8) {
                Group {
                    if showAliyunDashScopeAPIKey {
                        TextField(L10n.localize("asr.provider.aliyun.api_key_placeholder", comment: "Aliyun API key placeholder"), text: $viewModel.aliyunDashScopeAPIKeyInput)
                    } else {
                        SecureField(L10n.localize("asr.provider.aliyun.api_key_placeholder", comment: "Aliyun API key placeholder"), text: $viewModel.aliyunDashScopeAPIKeyInput)
                    }
                }
                .textFieldStyle(.roundedBorder)
                Button {
                    if showAliyunDashScopeAPIKey {
                        viewModel.aliyunDashScopeAPIKeyInput = viewModel.aliyunDashScopeAPIKeyForEditing()
                        showAliyunDashScopeAPIKey = false
                    } else {
                        if viewModel.isMaskedAliyunDashScopeAPIKey(text: viewModel.aliyunDashScopeAPIKeyInput) {
                            viewModel.aliyunDashScopeAPIKeyInput = viewModel.storedAliyunDashScopeAPIKeyForEditing()
                        }
                        showAliyunDashScopeAPIKey = true
                    }
                } label: {
                    Image(systemName: showAliyunDashScopeAPIKey ? "eye.slash" : "eye")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(showAliyunDashScopeAPIKey ? L10n.localize("asr.provider.hide_api_key", comment: "Hide API key help") : L10n.localize("asr.provider.show_api_key", comment: "Show API key help"))
            }
            HStack(spacing: 8) {
                Button(L10n.localize("asr.provider.save_configuration", comment: "Save ASR provider configuration")) {
                    viewModel.saveAliyunDashScopeConfiguration()
                }
                Button(viewModel.isTestingAliyunDashScope ? L10n.localize("asr.provider.testing_connection", comment: "Testing connection") : L10n.localize("asr.provider.test_connection", comment: "Test connection")) {
                    Task { await viewModel.testAliyunDashScopeConnection() }
                }
                .disabled(viewModel.isTestingAliyunDashScope)
                if viewModel.hasStoredAliyunDashScopeAPIKey {
                    Button(L10n.localize("asr.provider.delete_api_key", comment: "Delete API key"), role: .destructive) {
                        viewModel.deleteAliyunDashScopeAPIKey()
                    }
                }
            }
            .buttonStyle(.bordered)
            Text(L10n.localize("asr.provider.aliyun.privacy_note", comment: "Aliyun DashScope privacy note"))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
        .settingsRow()
    }

    private var volcengineConfigurationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack(spacing: 8) {
                Text(L10n.localize("asr.provider.volcengine.configuration_title", comment: "Volcengine configuration title"))
                    .font(.system(size: 13, weight: .semibold))
                if viewModel.hasStoredVolcengineCredentials {
                    Text(L10n.localize("asr.provider.credentials_saved", comment: "Credentials saved status"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.green)
                }
            }
            Text(L10n.localize("asr.provider.volcengine.description", comment: "Volcengine ASR description"))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            VStack(alignment: .leading, spacing: 8) {
                volcengineCredentialField(L10n.localize("asr.provider.volcengine.app_id", comment: "Volcengine app ID"), text: $viewModel.volcengineAppIDInput, isSecret: false)
                HStack(spacing: 8) {
                    volcengineCredentialField(L10n.localize("asr.provider.volcengine.access_token", comment: "Volcengine access token"), text: $viewModel.volcengineAccessTokenInput, isSecret: true)
                    Button {
                        if showVolcengineCredentials {
                            let stored = viewModel.storedVolcengineCredentialsForEditing()
                            viewModel.volcengineAppIDInput = stored.appID
                            viewModel.volcengineAccessTokenInput = stored.accessToken.isEmpty
                                ? ""
                                : ASRProviderViewModel.storedVolcengineSecretMask
                            viewModel.volcengineSecretKeyInput = stored.secretKey.isEmpty
                                ? ""
                                : ASRProviderViewModel.storedVolcengineSecretMask
                            showVolcengineCredentials = false
                        } else {
                            let stored = viewModel.storedVolcengineCredentialsForEditing()
                            if viewModel.isMaskedVolcengineSecret(text: viewModel.volcengineAccessTokenInput) {
                                viewModel.volcengineAccessTokenInput = stored.accessToken
                            }
                            if viewModel.isMaskedVolcengineSecret(text: viewModel.volcengineSecretKeyInput) {
                                viewModel.volcengineSecretKeyInput = stored.secretKey
                            }
                            showVolcengineCredentials = true
                        }
                    } label: {
                        Image(systemName: showVolcengineCredentials ? "eye.slash" : "eye")
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(showVolcengineCredentials ? L10n.localize("asr.provider.volcengine.hide_credentials", comment: "Hide Volcengine credentials") : L10n.localize("asr.provider.volcengine.show_credentials", comment: "Show Volcengine credentials"))
                }
                volcengineCredentialField(L10n.localize("asr.provider.volcengine.secret_key", comment: "Volcengine secret key"), text: $viewModel.volcengineSecretKeyInput, isSecret: true)
            }
            HStack(spacing: 8) {
                Button(L10n.localize("asr.provider.save_configuration", comment: "Save ASR provider configuration")) {
                    viewModel.saveVolcengineConfiguration()
                }
                Button(viewModel.isTestingVolcengine ? L10n.localize("asr.provider.testing_connection", comment: "Testing connection") : L10n.localize("asr.provider.test_connection", comment: "Test connection")) {
                    Task { await viewModel.testVolcengineConnection() }
                }
                .disabled(viewModel.isTestingVolcengine)
                if viewModel.hasStoredVolcengineCredentials {
                    Button(L10n.localize("asr.provider.delete_credentials", comment: "Delete credentials"), role: .destructive) {
                        viewModel.deleteVolcengineCredentials()
                    }
                }
            }
            .buttonStyle(.bordered)
            Text(L10n.localize("asr.provider.volcengine.privacy_note", comment: "Volcengine privacy note"))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
        .settingsRow()
    }

    @ViewBuilder
    private func volcengineCredentialField(_ placeholder: String, text: Binding<String>, isSecret: Bool) -> some View {
        if isSecret && !showVolcengineCredentials {
            SecureField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        } else {
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func cardSelectionSurface(
        _ provider: ASRProviderDescriptor,
        interaction: ASRProviderCardInteractionPresentation
    ) -> some View {
        Button {
            switch interaction.cardTapBehavior {
            case .selectProvider, .showUnavailableFeedback:
                viewModel.selectDefaultProvider(id: provider.id)
            case .ignore:
                return
            }
        } label: {
            Color.clear
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!interaction.handlesCardTap)
        .accessibilityLabel(
            L10n.format("asr.provider.select_accessibility_format", comment: "Select ASR provider accessibility label",
                provider.displayName
            )
        )
    }

    private func providerSummary(_ provider: ASRProviderDescriptor, isExpanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: isExpanded ? 6 : 3) {
            Text(provider.displayName)
                .font(.system(size: isExpanded ? 17 : 15, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
            if let status = provider.statusMessage {
                Text(status)
                    .font(.system(size: isExpanded ? 13 : 12, weight: .medium))
                    .foregroundStyle(provider.isAvailable ? AppTheme.ColorToken.accent : .orange)
                    .lineLimit(isExpanded ? nil : 1)
            }
            if isExpanded {
                Text(provider.privacySummary)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            if isExpanded, let links = provider.externalLinks {
                externalLinksRow(links)
            }
        }
    }

    private func externalLinksRow(_ links: ASRProviderExternalLinks) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                externalLink(title: links.apiKeyTitle, destination: links.apiKeyURL)
                if let title = links.modelsTitle, let url = links.modelsURL {
                    Text("·")
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    externalLink(title: title, destination: url)
                }
                if let title = links.guideTitle, let url = links.guideURL {
                    Text("·")
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    externalLink(title: title, destination: url)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                externalLink(title: links.apiKeyTitle, destination: links.apiKeyURL)
                if let title = links.modelsTitle, let url = links.modelsURL {
                    externalLink(title: title, destination: url)
                }
                if let title = links.guideTitle, let url = links.guideURL {
                    externalLink(title: title, destination: url)
                }
            }
        }
    }

    private func externalLink(title: String, destination: URL) -> some View {
        Link(destination: destination) {
            Label(title, systemImage: "arrow.up.right")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.accent)
        }
    }

    @ViewBuilder
    private func providerIcon(_ provider: ASRProviderDescriptor, compact: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(provider.isDefault ? AppTheme.ColorToken.selectionBackground : AppTheme.ColorToken.panelBackground)
            .frame(width: compact ? 34 : 46, height: compact ? 34 : 46)
            .overlay {
                if let symbolName = ASRProviderIcon.systemSymbolName(providerID: provider.id) {
                    Image(systemName: symbolName)
                        .font(.system(size: compact ? 16 : 20, weight: .medium))
                } else if let image = ASRProviderIcon.load(providerID: provider.id) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: compact ? 21 : 27, height: compact ? 21 : 27)
                        .opacity(provider.isAvailable ? 1 : 0.55)
                } else if let badge = ASRProviderIcon.textBadge(providerID: provider.id) {
                    Text(badge)
                        .font(.system(size: compact ? 11 : 14, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(
                provider.isAvailable
                    ? AppTheme.ColorToken.accent
                    : AppTheme.ColorToken.secondaryText
            )
    }

    private func localModelControls(_ provider: ASRProviderDescriptor) -> some View {
        let isDownloading = viewModel.isDownloading && viewModel.downloadingProviderID == provider.id
        return VStack(alignment: .leading, spacing: 12) {
            Divider()
            providerConfigurationControls(provider)
            HStack(alignment: .center, spacing: 14) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.localize("asr.provider.local_model.status_label", comment: "Local model status label"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        Text(localModelStatusText(provider, isDownloading: isDownloading))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.localize("asr.provider.local_model.size_label", comment: "Local model size label"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        Text(viewModel.localModelSizeSummary(providerID: provider.id))
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                Spacer()
                switch provider.localModelAction {
                case .download, .resume, .repair:
                    HStack(spacing: 8) {
                        Button {
                            Task { await viewModel.downloadModel(id: provider.id) }
                        } label: {
                            Label(
                                localModelActionTitle(provider, isDownloading: isDownloading),
                                systemImage: localModelActionIcon(provider)
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isDownloading)

                        Button(role: .destructive) {
                            viewModel.deleteLocalModel(id: provider.id)
                        } label: {
                            Label(L10n.localize("asr.provider.local_model.clean", comment: "Clean local model"), systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isDownloading && viewModel.downloadingProviderID != provider.id)
                    }
                case .delete:
                    Button(role: .destructive) {
                        viewModel.deleteLocalModel(id: provider.id)
                    } label: {
                        Label(L10n.localize("asr.provider.local_model.delete", comment: "Delete local model"), systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                case .none:
                    EmptyView()
                }
            }
            if isDownloading, let progress = viewModel.downloadProgress {
                VStack(alignment: .leading, spacing: 6) {
                    if let progressValue = progress.progressValue {
                        ProgressView(value: progressValue) {
                            Text(progress.statusText)
                                .font(.system(size: 12))
                        }
                    } else {
                        ProgressView {
                            Text(progress.statusText)
                                .font(.system(size: 12))
                        }
                    }
                    HStack(spacing: 8) {
                        Text(progress.componentName)
                        Text(progress.detailText)
                        Text(progress.modelSizeText)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
            }
        }
    }

    private func localModelStatusText(
        _ provider: ASRProviderDescriptor,
        isDownloading: Bool
    ) -> String {
        if isDownloading {
            return L10n.localize("asr.provider.local_model.status_downloading", comment: "Local model downloading status")
        }
        switch provider.localModelAction {
        case .delete:
            return L10n.localize("asr.provider.local_model.status_ready", comment: "Local model ready status")
        case .repair:
            return L10n.localize("asr.provider.local_model.status_repair_needed", comment: "Local model repair needed status")
        case .resume:
            return L10n.localize("asr.provider.local_model.status_resume", comment: "Local model resumable status")
        case .download:
            return L10n.localize("asr.provider.local_model.status_not_downloaded", comment: "Local model not downloaded status")
        case .none:
            return provider.isAvailable ? L10n.localize("asr.provider.local_model.status_ready", comment: "Local model ready status") : L10n.localize("asr.provider.local_model.status_unavailable", comment: "Local model unavailable status")
        }
    }

    private func localModelActionTitle(
        _ provider: ASRProviderDescriptor,
        isDownloading: Bool
    ) -> String {
        if isDownloading {
            return provider.localModelAction == .repair ? L10n.localize("asr.provider.local_model.action_repairing", comment: "Repairing local model") : L10n.localize("asr.provider.local_model.action_downloading", comment: "Downloading local model")
        }
        switch provider.localModelAction {
        case .repair:
            return L10n.localize("asr.provider.local_model.action_repair", comment: "Repair local model")
        case .resume:
            return L10n.localize("asr.provider.local_model.action_resume", comment: "Resume local model download")
        case .none, .download, .delete:
            return L10n.localize("asr.provider.local_model.action_download", comment: "Download local model")
        }
    }

    private func localModelActionIcon(_ provider: ASRProviderDescriptor) -> String {
        provider.localModelAction == .repair ? "arrow.clockwise.circle" : "arrow.down.circle"
    }

    @ViewBuilder
    private func providerConfigurationControls(_ provider: ASRProviderDescriptor) -> some View {
        switch provider.id {
        case ASRProviderID.funASR:
            Picker(
                L10n.localize("asr.provider.precision", comment: "Precision picker label"),
                selection: Binding(
                    get: { viewModel.selectedFunASRPrecision },
                    set: { value in viewModel.selectFunASRPrecision(value, selectingProvider: true) }
                )
            ) {
                ForEach(ASRManager.FunASRPrecision.allCases, id: \.self) { precision in
                    Text(precision.rawValue).tag(precision)
                }
            }
            .pickerStyle(.segmented)
        case ASRProviderID.whisper:
            Picker(
                L10n.localize("asr.provider.model", comment: "Model picker label"),
                selection: Binding(
                    get: { viewModel.selectedWhisperVariant },
                    set: { value in viewModel.selectWhisperVariant(value, selectingProvider: true) }
                )
            ) {
                ForEach(ASRManager.WhisperVariant.allCases, id: \.self) { variant in
                    Text(variant.rawValue).tag(variant)
                        .disabled(!ASRManager.isWhisperRuntimeSupported(variant: variant))
                }
            }
            .pickerStyle(.segmented)
        case ASRProviderID.qwen3:
            Picker(
                L10n.localize("asr.provider.model", comment: "Model picker label"),
                selection: Binding(
                    get: { viewModel.selectedQwenModelSize },
                    set: { value in viewModel.selectQwenModelSize(value, selectingProvider: true) }
                )
            ) {
                ForEach(ASRManager.ModelSize.allCases, id: \.self) { size in
                    Text(size.rawValue).tag(size)
                }
            }
            .pickerStyle(.segmented)
        default:
            EmptyView()
        }
    }

}
