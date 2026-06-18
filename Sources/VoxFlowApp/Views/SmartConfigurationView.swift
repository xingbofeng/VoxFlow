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
                Text("智能应用配置")
                    .font(.system(size: 18, weight: .semibold))
                Text("自动为已安装应用推荐语音输入风格")
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
                .accessibilityLabel("关闭")
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
            progressView(title: "正在扫描已安装应用...", progress: progress)
        case .classifying(let progress):
            progressView(title: "正在智能分类应用...", progress: progress)
        case .reviewing:
            reviewingView
        case .applying:
            progressView(title: "正在应用配置...", progress: 0.5)
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
            Text("扫描已安装应用并智能推荐语音输入风格")
                .font(.system(size: 15, weight: .medium))
            Text("系统将分析你的应用，并为每个应用匹配最合适的语音输入风格。")
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
            Text("已发现 \(viewModel.totalAppCount) 个应用")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reviewingView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(viewModel.groups) { group in
                    groupCard(group)
                }
            }
            .padding(20)
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
                Text("\(group.recommendations.count) 个应用")
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
            Text("配置完成")
                .font(.system(size: 18, weight: .semibold))
            Text("应用风格规则已保存，语音输入时将自动切换风格。")
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
            Text("配置失败")
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
                Button("取消") {
                    viewModel.cancel()
                    onClose()
                }
                .buttonStyle(.bordered)
            }
            switch viewModel.phase {
            case .idle:
                Button("开始扫描") {
                    Task { await viewModel.startConfiguration() }
                }
                .buttonStyle(.borderedProminent)
            case .reviewing:
                Button("应用配置") {
                    do {
                        try viewModel.confirm()
                    } catch {
                        // Error will be reported through viewModel feedback
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canConfirm)
            case .completed, .failed:
                Button("完成", action: onClose)
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
        case .systemPreset: return "系统预设"
        case .aiRecommendation: return "AI 推荐"
        case .defaultStyle: return "默认风格"
        case .userRule: return "自定义规则"
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
