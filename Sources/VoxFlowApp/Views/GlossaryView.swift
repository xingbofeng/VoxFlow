import SwiftUI

struct GlossaryView: View {
    @ObservedObject var viewModel: GlossaryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                header
                placeholderPanel
            }
            .padding(AppTheme.Spacing.page)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.ColorToken.pageBackground)
        .tint(AppTheme.ColorToken.accent)
        .actionFeedbackOverlay(
            message: viewModel.lastActionMessage,
            error: viewModel.lastError,
            onDismiss: viewModel.clearFeedback
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("词汇表", systemImage: "text.book.closed")
                .font(.system(size: 28, weight: .semibold))
            Text("普通术语词表入口已为新版本地纠错系统让位。")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
    }

    private var placeholderPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("暂无可管理内容", systemImage: "archivebox")
                .font(.system(size: 15, weight: .semibold))
            Text("后续若恢复普通术语词表，会使用新的数据结构与新版纠错规则分离。")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
        .padding(AppTheme.Spacing.card)
        .appPanel()
    }
}
