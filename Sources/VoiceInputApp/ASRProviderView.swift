import SwiftUI

struct ASRProviderView: View {
    @ObservedObject var viewModel: ASRProviderViewModel
    var embedded = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            if !embedded {
                Label("听写模型", systemImage: "mic.badge.plus")
                    .font(.system(size: 24, weight: .semibold))
            }

            tagBar

            VStack(spacing: AppTheme.Spacing.grid) {
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
        .onAppear { viewModel.load() }
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
        VStack(alignment: .leading, spacing: 16) {
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

            if provider.id == ASRProviderID.qwen3
                || provider.id == ASRProviderID.funASR
                || provider.id == ASRProviderID.whisper
                || provider.id == ASRProviderID.paraformer
                || provider.id == ASRProviderID.senseVoice {
                localModelControls(provider)
            }
        }
        .padding(18)
        .background {
            cardSelectionSurface(provider)
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

    private func cardSelectionSurface(_ provider: ASRProviderDescriptor) -> some View {
        Button {
            guard provider.isAvailable, !provider.isDefault else { return }
            viewModel.selectDefaultProvider(id: provider.id)
        } label: {
            Color.clear
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!provider.isAvailable)
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
                } else if let badge = ASRProviderIcon.textBadge(providerID: provider.id) {
                    Text(badge)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                } else if let image = ASRProviderIcon.load(providerID: provider.id) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 27, height: 27)
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
                    Text(provider.isAvailable ? "就绪，可直接使用" : isDownloading ? "正在下载所需文件" : "尚未下载")
                        .font(.system(size: 14, weight: .semibold))
                }
                Spacer()
                if !provider.isAvailable {
                    Button {
                        Task { await viewModel.downloadModel(id: provider.id) }
                    } label: {
                        Label(isDownloading ? "下载中" : "下载模型", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isDownloading)
                } else {
                    Button(role: .destructive) {
                        viewModel.deleteLocalModel(id: provider.id)
                    } label: {
                        Label("删除模型", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
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

    @ViewBuilder
    private func providerConfigurationControls(_ provider: ASRProviderDescriptor) -> some View {
        switch provider.id {
        case ASRProviderID.funASR:
            Picker(
                "精度",
                selection: Binding(
                    get: { viewModel.selectedFunASRPrecision },
                    set: { value in viewModel.selectFunASRPrecision(value) }
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
                    set: { value in viewModel.selectWhisperVariant(value) }
                )
            ) {
                ForEach(ASRManager.WhisperVariant.allCases, id: \.self) { variant in
                    Text(variant.rawValue).tag(variant)
                }
            }
            .pickerStyle(.segmented)
        case ASRProviderID.paraformer:
            Picker(
                "语言",
                selection: Binding(
                    get: { viewModel.selectedParaformerLanguage },
                    set: { value in viewModel.selectParaformerLanguage(value) }
                )
            ) {
                ForEach(ASRManager.ParaformerLanguage.allCases, id: \.self) { language in
                    Text(language.rawValue).tag(language)
                }
            }
            .pickerStyle(.segmented)
        case ASRProviderID.qwen3:
            Picker(
                "模型",
                selection: Binding(
                    get: { viewModel.selectedQwenModelSize },
                    set: { value in viewModel.selectQwenModelSize(value) }
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
