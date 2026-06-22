import SwiftUI

struct ASRProviderView: View {
    @ObservedObject var viewModel: ASRProviderViewModel
    var embedded = false
    @State private var showGroqAPIKey = false
    @State private var showAliyunDashScopeAPIKey = false
    @State private var showTencentCloudCredentials = false
    @State private var expandedProviderID: String?

    private var providerColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: AppTheme.Spacing.grid),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            if !embedded {
                Label("听写模型", systemImage: "mic.badge.plus")
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
                    Text("当前使用")
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
                .help(isExpanded ? "收起配置" : "展开配置")
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
    }

    private var groqConfigurationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack(spacing: 8) {
                Text("Groq 配置")
                    .font(.system(size: 13, weight: .semibold))
                if viewModel.hasStoredGroqAPIKey {
                    Text("访问密钥已保存")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.green)
                }
            }
            HStack(spacing: 8) {
                Group {
                    if showGroqAPIKey {
                        TextField("Groq 访问密钥", text: $viewModel.groqAPIKeyInput)
                    } else {
                        SecureField("Groq 访问密钥", text: $viewModel.groqAPIKeyInput)
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
                .help(showGroqAPIKey ? "隐藏访问密钥" : "显示访问密钥")
            }
            Picker("模型", selection: $viewModel.groqModelInput) {
                ForEach(viewModel.supportedGroqModels) { model in
                    Text(model.title).tag(model.id)
                }
            }
            .pickerStyle(.menu)
            HStack(spacing: 8) {
                Button("保存配置") {
                    viewModel.saveGroqConfiguration()
                }
                Button(viewModel.isTestingGroq ? "测试中…" : "测试连接") {
                    Task { await viewModel.testGroqConnection() }
                }
                .disabled(viewModel.isTestingGroq)
                if viewModel.hasStoredGroqAPIKey {
                    Button("删除访问密钥", role: .destructive) {
                        viewModel.deleteGroqAPIKey()
                    }
                }
            }
            .buttonStyle(.bordered)
            Text("录音会发送到 Groq。访问密钥保存在系统钥匙串，可用眼睛按钮查看或隐藏。")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
        .settingsRow()
    }

    private var tencentCloudConfigurationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack(spacing: 8) {
                Text("腾讯云配置")
                    .font(.system(size: 13, weight: .semibold))
                if viewModel.hasStoredTencentCloudCredentials {
                    Text("凭据已保存")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.green)
                }
            }
            Text("使用腾讯云实时流式语音识别 WebSocket。请在腾讯云控制台获取应用 ID、密钥 ID 和密钥。")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            VStack(alignment: .leading, spacing: 8) {
                tencentCredentialField("应用 ID", text: $viewModel.tencentAppIDInput, isSecret: false)
                tencentCredentialField("密钥 ID", text: $viewModel.tencentSecretIDInput, isSecret: false)
                HStack(spacing: 8) {
                    tencentCredentialField("密钥", text: $viewModel.tencentSecretKeyInput, isSecret: true)
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
                    .help(showTencentCloudCredentials ? "隐藏腾讯云凭据" : "显示腾讯云凭据")
                }
            }
            HStack(spacing: 8) {
                Button("保存配置") {
                    viewModel.saveTencentCloudConfiguration()
                }
                Button(viewModel.isTestingTencentCloud ? "测试中…" : "测试连接") {
                    Task { await viewModel.testTencentCloudConnection() }
                }
                .disabled(viewModel.isTestingTencentCloud)
                if viewModel.hasStoredTencentCloudCredentials {
                    Button("删除凭据", role: .destructive) {
                        viewModel.deleteTencentCloudCredentials()
                    }
                }
            }
            .buttonStyle(.bordered)
            Text("录音会发送到腾讯云。应用 ID、密钥 ID 和 密钥 保存在系统钥匙串，可用眼睛按钮查看或隐藏。")
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
                Text("阿里云百炼配置")
                    .font(.system(size: 13, weight: .semibold))
                if viewModel.hasStoredAliyunDashScopeAPIKey {
                    Text("访问密钥已保存")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.green)
                }
            }
            Text("使用 DashScope 实时语音识别 WebSocket。接入地址固定为 wss://dashscope.aliyuncs.com/api-ws/v1/inference，鉴权使用 Authorization: Bearer 访问密钥。")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            HStack(spacing: 8) {
                Group {
                    if showAliyunDashScopeAPIKey {
                        TextField("百炼访问密钥", text: $viewModel.aliyunDashScopeAPIKeyInput)
                    } else {
                        SecureField("百炼访问密钥", text: $viewModel.aliyunDashScopeAPIKeyInput)
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
                .help(showAliyunDashScopeAPIKey ? "隐藏访问密钥" : "显示访问密钥")
            }
            HStack(spacing: 8) {
                Button("保存配置") {
                    viewModel.saveAliyunDashScopeConfiguration()
                }
                Button(viewModel.isTestingAliyunDashScope ? "测试中…" : "测试连接") {
                    Task { await viewModel.testAliyunDashScopeConnection() }
                }
                .disabled(viewModel.isTestingAliyunDashScope)
                if viewModel.hasStoredAliyunDashScopeAPIKey {
                    Button("删除访问密钥", role: .destructive) {
                        viewModel.deleteAliyunDashScopeAPIKey()
                    }
                }
            }
            .buttonStyle(.bordered)
            Text("录音会发送到阿里云百炼。访问密钥保存在系统钥匙串，可用眼睛按钮查看或隐藏。默认使用官方推荐语音识别模型。")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
        .settingsRow()
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
        .accessibilityLabel("选择 \(provider.displayName)")
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
                VStack(alignment: .leading, spacing: 4) {
                    Text("模型状态")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    Text(localModelStatusText(provider, isDownloading: isDownloading))
                        .font(.system(size: 14, weight: .semibold))
                }
                Spacer()
                switch provider.localModelAction {
                case .download, .repair:
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
                case .delete:
                    Button(role: .destructive) {
                        viewModel.deleteLocalModel(id: provider.id)
                    } label: {
                        Label("删除模型", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                case .none:
                    EmptyView()
                }
            }
            if isDownloading, let progress = viewModel.downloadProgress {
                ProgressView(value: progress.overallProgress) {
                    Text(progress.fileName)
                        .font(.system(size: 12))
                }
            }
        }
    }

    private func localModelStatusText(
        _ provider: ASRProviderDescriptor,
        isDownloading: Bool
    ) -> String {
        if isDownloading {
            return "正在下载所需文件"
        }
        switch provider.localModelAction {
        case .delete:
            return "就绪，可直接使用"
        case .repair:
            return "需要修复"
        case .download:
            return "尚未下载"
        case .none:
            return provider.isAvailable ? "就绪，可直接使用" : "不可用"
        }
    }

    private func localModelActionTitle(
        _ provider: ASRProviderDescriptor,
        isDownloading: Bool
    ) -> String {
        if isDownloading {
            return provider.localModelAction == .repair ? "修复中" : "下载中"
        }
        return provider.localModelAction == .repair ? "修复模型" : "下载模型"
    }

    private func localModelActionIcon(_ provider: ASRProviderDescriptor) -> String {
        provider.localModelAction == .repair ? "arrow.clockwise.circle" : "arrow.down.circle"
    }

    @ViewBuilder
    private func providerConfigurationControls(_ provider: ASRProviderDescriptor) -> some View {
        switch provider.id {
        case ASRProviderID.funASR:
            Picker(
                "精度",
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
                "模型",
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
                "模型",
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
