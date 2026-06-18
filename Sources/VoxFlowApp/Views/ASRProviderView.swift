import SwiftUI

struct ASRProviderView: View {
    @ObservedObject var viewModel: ASRProviderViewModel
    var embedded = false

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

            scopeFilterBar
            tagBar

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

    private var scopeFilterBar: some View {
        HStack(spacing: 8) {
            ForEach(ASRProviderScope.allCases) { scope in
                let isSelected = viewModel.providerScope == scope
                Button {
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
            Spacer(minLength: 0)
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

    private var tagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.availableTags, id: \.self) { tag in
                    Button(tag) {
                        viewModel.toggleTag(tag)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        viewModel.selectedTags.contains(tag)
                            ? AppTheme.ColorToken.accent
                            : AppTheme.ColorToken.secondaryText
                    )
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(
                        viewModel.selectedTags.contains(tag)
                            ? AppTheme.ColorToken.selectionBackground
                            : AppTheme.ColorToken.panelBackground
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                viewModel.selectedTags.contains(tag)
                                    ? AppTheme.ColorToken.accent.opacity(0.35)
                                    : AppTheme.ColorToken.panelStroke
                            )
                    )
                    .clipShape(Capsule())
                }
            }
        }
    }

    private func providerCard(_ provider: ASRProviderDescriptor) -> some View {
        let interaction = ASRProviderCardInteractionPresentation(provider: provider)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    providerIcon(provider)
                    providerSummary(provider)
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
            }
            .allowsHitTesting(!interaction.isSelectionPassthroughRegion(.blank))

            HStack(spacing: 6) {
                ForEach(provider.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(AppTheme.ColorToken.pageBackground)
                        .clipShape(Capsule())
                }
            }
            .allowsHitTesting(!interaction.isSelectionPassthroughRegion(.tags))

            if provider.supportsLocalModelControls {
                localModelControls(provider)
            }
        }
        .padding(18)
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
        .opacity(provider.isAvailable || provider.externalLinks != nil ? 1 : 0.82)
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

    private func providerSummary(_ provider: ASRProviderDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(provider.displayName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
            if let status = provider.statusMessage {
                Text(status)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(provider.isAvailable ? AppTheme.ColorToken.accent : .orange)
            }
            Text(provider.privacySummary)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            if let links = provider.externalLinks {
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
    private func providerIcon(_ provider: ASRProviderDescriptor) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(provider.isDefault ? AppTheme.ColorToken.selectionBackground : AppTheme.ColorToken.panelBackground)
            .frame(width: 46, height: 46)
            .overlay {
                if let symbolName = ASRProviderIcon.systemSymbolName(providerID: provider.id) {
                    Image(systemName: symbolName)
                        .font(.system(size: 20, weight: .medium))
                } else if let image = ASRProviderIcon.load(providerID: provider.id) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 27, height: 27)
                } else if let badge = ASRProviderIcon.textBadge(providerID: provider.id) {
                    Text(badge)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
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
                        viewModel.selectProviderForConfiguration(id: provider.id)
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
                        viewModel.selectProviderForConfiguration(id: provider.id)
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
