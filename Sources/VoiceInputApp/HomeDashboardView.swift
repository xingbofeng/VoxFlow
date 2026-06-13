import SwiftUI

struct HomeDashboardView: View {
    @ObservedObject var viewModel: HomeDashboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                HStack {
                    Label("首页", systemImage: "house.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                    Spacer()
                }

                HomeStatsGrid(stats: viewModel.stats)
                GoalProgressCard(stats: viewModel.stats)
                HomeHistorySection(viewModel: viewModel)
                if let selectedDetail = viewModel.selectedDetail {
                    HomeHistoryDetailPanel(viewModel: viewModel, detail: selectedDetail)
                }
            }
            .padding(AppTheme.Spacing.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.ColorToken.pageBackground)
        .tint(AppTheme.ColorToken.accent)
        .overlay(alignment: .topTrailing) {
            ActionFeedbackView(
                message: viewModel.lastActionMessage,
                error: viewModel.lastError,
                tone: viewModel.lastActionTone,
                onDismiss: viewModel.clearFeedback
            )
            .padding(AppTheme.Spacing.page)
        }
        .onAppear {
            viewModel.load()
        }
    }
}

private struct HomeStatsGrid: View {
    let stats: HomeDashboardStats

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: AppTheme.Spacing.grid)], spacing: AppTheme.Spacing.grid) {
            HomeStatCard(title: "累计字符", value: "\(stats.totalCharacters)", systemImage: "textformat.size")
            HomeStatCard(title: "今日字符", value: "\(stats.todayCharacters)", systemImage: "calendar")
            HomeStatCard(title: "平均 CPM", value: "\(stats.averageCPM)", systemImage: "speedometer")
            HomeStatCard(title: "连续使用", value: "\(stats.streakDays) 天", systemImage: "flame")
        }
    }
}

private struct HomeStatCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(AppTheme.ColorToken.accent)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                Spacer()
            }
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(AppTheme.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel()
    }
}

private struct GoalProgressCard: View {
    let stats: HomeDashboardStats

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("今日目标", systemImage: "target")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(stats.todayCharacters) / \(stats.dailyGoal)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.ColorToken.progressTrack)
                    Capsule()
                        .fill(AppTheme.ColorToken.accent)
                        .frame(width: max(6, proxy.size.width * stats.dailyGoalProgress))
                }
            }
            .frame(height: 8)
        }
        .padding(AppTheme.Spacing.card)
        .appPanel()
    }
}

private struct HomeHistorySection: View {
    @ObservedObject var viewModel: HomeDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("历史", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                TextField(
                    "搜索历史",
                    text: Binding(
                        get: { viewModel.searchText },
                        set: { viewModel.updateSearch($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            }

            if viewModel.historyGroups.isEmpty {
                Text("暂无记录")
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .appPanel()
            } else {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.grid) {
                    ForEach(viewModel.historyGroups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                            ForEach(group.items) { item in
                                HomeHistoryRow(
                                    item: item,
                                    isSelected: viewModel.selectedDetail?.id == item.id,
                                    selectAction: { viewModel.selectHistoryItem(id: item.id) },
                                    copyAction: { viewModel.copyHistoryItem(id: item.id) },
                                    deleteAction: { viewModel.deleteHistoryItem(id: item.id) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct HomeHistoryRow: View {
    let item: HomeHistoryItem
    let isSelected: Bool
    let selectAction: () -> Void
    let copyAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: selectAction) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.finalText)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if let appName = item.appName {
                            Text(appName)
                        }
                        Text("\(item.charCount) 字")
                        Text("\(Int(item.cpm.rounded())) CPM")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: copyAction) {
                Image(systemName: "doc.on.doc")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("复制")
            Button(action: deleteAction) {
                Image(systemName: "trash")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("删除")
        }
        .padding(12)
        .background(isSelected ? AppTheme.ColorToken.selectionBackground : AppTheme.ColorToken.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(
                    isSelected ? AppTheme.ColorToken.selectionBorder : AppTheme.ColorToken.panelStroke,
                    lineWidth: AppTheme.Border.panelLineWidth
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .shadow(
            color: AppTheme.ColorToken.accent.opacity(isSelected ? 0.05 : 0.025),
            radius: isSelected ? 8 : 4,
            y: 2
        )
    }
}

private struct HomeHistoryDetailPanel: View {
    @ObservedObject var viewModel: HomeDashboardViewModel
    let detail: HomeHistoryDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("详情", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button {
                    Task {
                        await viewModel.reprocessSelectedHistoryItem()
                    }
                } label: {
                    Image(systemName: viewModel.isReprocessing ? "hourglass" : "arrow.triangle.2.circlepath")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isReprocessing)
                .help("重新处理")
                Button {
                    viewModel.clearSelectedDetail()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("关闭")
            }

            HStack(alignment: .top, spacing: AppTheme.Spacing.grid) {
                DetailTextBlock(title: "处理后", text: detail.finalText)
                DetailTextBlock(title: "原文", text: detail.rawText)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: AppTheme.Spacing.grid)], spacing: 8) {
                DetailMetaItem(title: "语言", value: detail.language)
                DetailMetaItem(title: "应用", value: detail.appName ?? "-")
                DetailMetaItem(title: "ASR", value: detail.asrProviderID ?? "-")
                DetailMetaItem(title: "LLM", value: detail.llmProviderID ?? "-")
                DetailMetaItem(title: "风格", value: detail.styleID ?? "-")
                DetailMetaItem(title: "字符", value: "\(detail.charCount)")
                DetailMetaItem(title: "CPM", value: "\(Int(detail.cpm.rounded()))")
                DetailMetaItem(title: "创建", value: Self.format(detail.createdAt))
                DetailMetaItem(title: "更新", value: Self.format(detail.updatedAt))
            }

            if !detail.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("警告")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    ForEach(detail.warnings, id: \.self) { warning in
                        Text(warning)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.card)
        .appPanel()
    }

    private static func format(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }
}

private struct DetailTextBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appControlSurface()
    }
}

private struct DetailMetaItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
