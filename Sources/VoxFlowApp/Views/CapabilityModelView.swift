import SwiftUI

struct CapabilityModelView: View {
    @ObservedObject var viewModel: CapabilityModelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.grid) {
            ForEach(viewModel.models) { model in
                modelCard(model)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .actionFeedbackOverlay(
            message: viewModel.lastActionMessage,
            error: viewModel.lastError,
            enabled: false,
            onDismiss: viewModel.clearFeedback
        )
    }

    private func modelCard(_ model: CapabilityModelDescriptor) -> some View {
        let isSelected = viewModel.selectedModelID == model.id
        let isSelectable = CapabilityModelViewModel.isSelectable(model)
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                guard !isSelected, isSelectable else { return }
                viewModel.selectModel(id: model.id)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? AppTheme.ColorToken.selectionBackground : AppTheme.ColorToken.panelBackground)
                        .frame(width: 42, height: 42)
                        .overlay {
                            Image(systemName: model.kind == .tts ? "speaker.wave.2" : "globe.asia.australia")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(AppTheme.ColorToken.accent)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(model.displayName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppTheme.ColorToken.primaryText)
                        if model.isRecommended {
                                Text(L10n.localize("model.capability.recommended", comment: ""))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(AppTheme.ColorToken.accent)
                                    .padding(.horizontal, 7)
                                    .frame(height: 22)
                                    .background(AppTheme.ColorToken.selectionBackground)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(model.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        Text("\(model.sizeDescription) · \(model.memoryDescription)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Text(L10n.localize("model.capability.current_using", comment: ""))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.ColorToken.accent)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(AppTheme.ColorToken.selectionBackground)
                            .clipShape(Capsule())
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isSelectable)

            HStack(spacing: 8) {
                Text(statusText(for: model))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(model.isInstalled ? AppTheme.ColorToken.accent : .orange)
                Text(model.fallbackDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            if viewModel.isDownloading && viewModel.downloadingModelID == model.id {
                ProgressView(value: viewModel.downloadProgress) {
                    Text(L10n.localize("model.capability.downloading", comment: ""))
                        .font(.system(size: 12))
                }
            }
            if !model.isInstalled, CapabilityModelID.requiresDownload(model.id) {
                Button {
                    Task { await viewModel.downloadModel(id: model.id) }
                } label: {
                    Label(L10n.localize("model.capability.download_button", comment: ""), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isDownloading)
            }
        }
        .opacity(isSelectable ? 1 : 0.58)
        .padding(14)
        .background(isSelected ? AppTheme.ColorToken.selectionBackground.opacity(0.72) : AppTheme.ColorToken.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSelected ? AppTheme.ColorToken.accent.opacity(0.5) : AppTheme.ColorToken.panelStroke,
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statusText(for model: CapabilityModelDescriptor) -> String {
        if model.isInstalled {
            return L10n.localize("model.capability.status_ready", comment: "")
        }
        if model.id == CapabilityModelID.llmTranslation {
            return L10n.localize("model.capability.status_unconfigured", comment: "")
        }
        return L10n.localize("model.capability.status_not_downloaded", comment: "")
    }
}
