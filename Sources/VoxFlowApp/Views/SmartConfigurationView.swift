import SwiftUI

enum SmartConfigurationPresentationPolicy {
    static let showsCloseButton = true
    static let dismissesOnBackdropTap = true
}

struct SmartConfigurationView: View {
    @ObservedObject var viewModel: SmartConfigurationViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 480)
        .background(AppTheme.ColorToken.pageBackground)
        .tint(AppTheme.ColorToken.accent)
        .actionFeedbackOverlay(
            message: viewModel.lastActionMessage,
            error: viewModel.lastError,
            onDismiss: viewModel.clearFeedback
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.localize("smart.config.title", comment: ""))
                    .font(.system(size: 18, weight: .semibold))
                Text(L10n.localize("smart.config.subtitle", comment: ""))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            if SmartConfigurationPresentationPolicy.showsCloseButton {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(AppTheme.ColorToken.controlBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.localize("smart.config.close", comment: ""))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            idleView
        case .scanning(let progress):
            progressView(title: L10n.localize("smart.config.progress_scanning", comment: ""), progress: progress)
        case .classifying(let progress):
            progressView(title: L10n.localize("smart.config.progress_classifying", comment: ""), progress: progress)
        case .reviewing:
            reviewingView
        case .applying:
            progressView(title: L10n.localize("smart.config.progress_applying", comment: ""), progress: 0.5)
        case .completed:
            completedView
        case .failed(let message):
            failedView(message: message)
        }
    }

    private var idleView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "sparkles.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.ColorToken.accent.opacity(0.6))
            Text(L10n.localize("smart.config.idle_title", comment: ""))
                .font(.system(size: 15, weight: .medium))
            Text(L10n.localize("smart.config.idle_subtitle", comment: ""))
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func progressView(title: String, progress: Double) -> some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)
            Text(title)
                .font(.system(size: 15, weight: .medium))
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 260)
            Text(String(format: L10n.localize("smart.config.discovered_format", comment: ""), viewModel.totalAppCount))
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reviewingView: some View {
        Group {
            if viewModel.groups.isEmpty {
                emptyReviewingView
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.groups) { group in
                            groupCard(group)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyReviewingView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "sparkles.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.ColorToken.accent.opacity(0.6))
            Text(L10n.localize("smart.config.empty_title", comment: ""))
                .font(.system(size: 15, weight: .medium))
            Text(L10n.localize("smart.config.empty_subtitle", comment: ""))
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if viewModel.totalAppCount > 0 {
                Text(String(format: L10n.localize("smart.config.discovered_format", comment: ""), viewModel.totalAppCount))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func groupCard(_ group: StyleRecommendationGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: group.styleIconName)
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 24, height: 24)
                Text(group.styleName)
                    .font(.system(size: 15, weight: .semibold))
                Text(sourceLabel(group.source))
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(sourceColor(group.source).opacity(0.12))
                    .foregroundStyle(sourceColor(group.source))
                    .clipShape(Capsule())
                Spacer()
                Text(String(format: L10n.localize("smart.config.app_count_format", comment: ""), group.recommendations.count))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }

            ForEach(group.recommendations, id: \.bundleID) { rec in
                HStack(spacing: 10) {
                    Image(systemName: "app")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rec.appName)
                            .font(.system(size: 13, weight: .medium))
                        Text(rec.bundleID)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button {
                        viewModel.removeRecommendation(bundleID: rec.bundleID)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .appPanel(cornerRadius: AppTheme.Radius.card)
    }

    private var completedView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text(L10n.localize("smart.config.completed_title", comment: ""))
                .font(.system(size: 18, weight: .semibold))
            Text(L10n.localize("smart.config.completed_message", comment: ""))
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(L10n.localize("smart.config.failed_title", comment: ""))
                .font(.system(size: 18, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            if viewModel.canCancel {
                Button(L10n.localize("smart.config.button_cancel", comment: "")) {
                    viewModel.cancel()
                    onClose()
                }
                .buttonStyle(.bordered)
            }
            switch viewModel.phase {
            case .idle:
                Button(L10n.localize("smart.config.button_start_scan", comment: "")) {
                    Task { await viewModel.startConfiguration() }
                }
                .buttonStyle(.borderedProminent)
            case .reviewing:
                Button(L10n.localize("smart.config.button_apply", comment: "")) {
                    do {
                        try viewModel.confirm()
                    } catch {
                        // Error will be reported through viewModel feedback
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canConfirm)
            case .completed, .failed:
                Button(L10n.localize("smart.config.button_done", comment: ""), action: onClose)
                    .buttonStyle(.borderedProminent)
                default:
                    EmptyView()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    private func sourceLabel(_ source: StyleRecommendationSource) -> String {
        switch source {
        case .systemPreset: return L10n.localize("smart.config.source_system_preset", comment: "")
        case .aiRecommendation: return L10n.localize("smart.config.source_ai_recommendation", comment: "")
        case .defaultStyle: return L10n.localize("smart.config.source_default_style", comment: "")
        case .userRule: return L10n.localize("smart.config.source_user_rule", comment: "")
        }
    }

    private func sourceColor(_ source: StyleRecommendationSource) -> Color {
        switch source {
        case .systemPreset: return .blue
        case .aiRecommendation: return AppTheme.ColorToken.accent
        case .defaultStyle: return .gray
        case .userRule: return .purple
        }
    }
}
