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

            if let error = viewModel.lastError {
                ActionFeedbackView(message: nil, error: error, onDismiss: viewModel.clearFeedback)
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(provider.isDefault ? AppTheme.ColorToken.selectionBackground : AppTheme.ColorToken.panelBackground)
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: provider.id == ASRProviderID.appleSpeech ? "waveform" : "cpu")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(
                                provider.isAvailable
                                    ? AppTheme.ColorToken.accent
                                    : AppTheme.ColorToken.secondaryText
                            )
                    }

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
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    if provider.id == ASRProviderID.qwen3 {
                        qwenSizeOptions
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

            if provider.id == ASRProviderID.qwen3 {
                qwenControls(provider)
            }
        }
        .padding(18)
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
        .contentShape(Rectangle())
        .onTapGesture {
            guard provider.isAvailable, !provider.isDefault else { return }
            viewModel.selectDefaultProvider(id: provider.id)
        }
        .opacity(provider.isAvailable ? 1 : 0.82)
    }

    private func qwenControls(_ provider: ASRProviderDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("模型状态")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    Text(provider.isAvailable ? "就绪，可直接使用" : viewModel.isDownloading ? "正在下载所需文件" : "尚未下载")
                        .font(.system(size: 14, weight: .semibold))
                }
                Spacer()
                if !provider.isAvailable {
                    Button {
                        Task { await viewModel.downloadQwenModel() }
                    } label: {
                        Label(viewModel.isDownloading ? "下载中" : "下载模型", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isDownloading)
                } else {
                    Button(role: .destructive) {
                        viewModel.deleteLocalQwenModel()
                    } label: {
                        Label("删除模型", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
            if viewModel.isDownloading, let progress = viewModel.downloadProgress {
                ProgressView(value: progress.overallProgress) {
                    Text(progress.fileName)
                        .font(.system(size: 12))
                }
            }
        }
    }

    private var qwenSizeOptions: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text("选择模型")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            HStack(spacing: 6) {
                ForEach(ASRManager.ModelSize.allCases, id: \.rawValue) { size in
                    Button {
                        viewModel.selectQwenModelSize(size)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(size.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                            Text(size == .size0_6B ? "1.31 GB" : "2.95 GB")
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 42)
                        .background(
                            viewModel.selectedQwenModelSize == size
                                ? AppTheme.ColorToken.selectionBackground
                                : AppTheme.ColorToken.pageBackground
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    viewModel.selectedQwenModelSize == size
                                        ? AppTheme.ColorToken.accent.opacity(0.5)
                                        : AppTheme.ColorToken.panelStroke
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
