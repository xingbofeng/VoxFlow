import AppKit
import SwiftUI

struct HomeDashboardView: View {
    @ObservedObject var viewModel: HomeDashboardViewModel

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                    HStack {
                        Label("首页", systemImage: "house.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(AppTheme.ColorToken.primaryText)
                        Spacer()
                    }

                    HomeStatsGrid(stats: viewModel.stats, focusedCharactersTitle: viewModel.focusedCharactersTitle)
                    HomeActivityCard(
                        activity: viewModel.activity,
                        selectedDate: viewModel.selectedActivityDate,
                        selectAction: viewModel.selectActivityDay,
                        clearAction: viewModel.restoreDefaultDashboardFocusFromActivityBlankTap
                    )
                    HomeHistorySection(viewModel: viewModel)
                }
                .padding(AppTheme.Spacing.page)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let detail = viewModel.selectedDetail {
                HomeHistoryDetailOverlay(viewModel: viewModel, detail: detail)
            }
        }
        .background(AppTheme.ColorToken.pageBackground)
        .tint(AppTheme.ColorToken.accent)
        .actionFeedbackOverlay(
            message: viewModel.lastActionMessage,
            error: viewModel.lastError,
            tone: viewModel.lastActionTone,
            onDismiss: viewModel.clearFeedback
        )
        .onAppear {
            viewModel.load()
        }
    }
}

private struct HomeActivityCard: View {
    let activity: HomeActivitySummary
    let selectedDate: Date?
    let selectAction: (Date) -> Void
    let clearAction: () -> Void

    private let maxSquareSize: CGFloat = 14
    private let minSquareSize: CGFloat = 8
    private let squareGap: CGFloat = 3
    private let weekdayLabelWidth: CGFloat = 18
    private let gridHeight: CGFloat = 116

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.grid) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("输入活跃度", systemImage: "square.grid.3x3.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("过去 52 周 · 每格代表一天")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(summaryText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    if selectedDate != nil {
                        Button("清除") {
                            clearAction()
                        }
                        .font(.system(size: 12, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.ColorToken.accent)
                    }
                }
            }

            GeometryReader { proxy in
                let columns = max(weeks.count, 1)
                let availableGridWidth = max(0, proxy.size.width - weekdayLabelWidth - 8)
                let squareSize = min(
                    maxSquareSize,
                    max(minSquareSize, (availableGridWidth - CGFloat(columns - 1) * squareGap) / CGFloat(columns))
                )

                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            clearAction()
                        }

                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: squareGap) {
                            ForEach(0..<7, id: \.self) { row in
                                Text(weekdayLabel(for: row))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(AppTheme.ColorToken.secondaryText.opacity(0.85))
                                    .frame(width: weekdayLabelWidth, height: squareSize, alignment: .trailing)
                            }
                        }

                        HStack(alignment: .top, spacing: squareGap) {
                            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                                VStack(spacing: squareGap) {
                                    ForEach(week) { day in
                                        Button {
                                            selectAction(day.date)
                                        } label: {
                                            RoundedRectangle(cornerRadius: min(4, squareSize * 0.28), style: .continuous)
                                                .fill(color(for: day.level))
                                                .frame(width: squareSize, height: squareSize)
                                                .overlay {
                                                    if isSelected(day) {
                                                        RoundedRectangle(cornerRadius: min(4, squareSize * 0.28), style: .continuous)
                                                            .stroke(AppTheme.ColorToken.accent, lineWidth: 2)
                                                    }
                                                }
                                        }
                                        .buttonStyle(.plain)
                                        .help("\(Self.dateFormatter.string(from: day.date)) · \(day.characters) 字")
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(height: gridHeight)

            HStack(spacing: 5) {
                Spacer()
                Text("少")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color(for: level))
                        .frame(width: 10, height: 10)
                }
                Text("多")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
        }
        .padding(AppTheme.Spacing.card)
        .appPanel()
    }

    private var summaryText: String {
        guard let selectedDate,
              let selectedDay = activity.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) else {
            return "本周 \(activity.thisWeekCharacters) 字"
        }
        return "\(Self.dateFormatter.string(from: selectedDate)) \(selectedDay.characters) 字"
    }

    private var weeks: [[HomeActivityDay]] {
        stride(from: 0, to: activity.days.count, by: 7).map { startIndex in
            Array(activity.days[startIndex..<min(startIndex + 7, activity.days.count)])
        }
    }

    private func isSelected(_ day: HomeActivityDay) -> Bool {
        guard let selectedDate else {
            return false
        }
        return Calendar.current.isDate(day.date, inSameDayAs: selectedDate)
    }

    private func weekdayLabel(for row: Int) -> String {
        switch row {
        case 0:
            return "一"
        case 1:
            return "二"
        case 2:
            return "三"
        case 3:
            return "四"
        case 4:
            return "五"
        case 5:
            return "六"
        case 6:
            return "日"
        default:
            return ""
        }
    }

    private func color(for level: Int) -> Color {
        switch level {
        case 1:
            return Color(red: 0.718, green: 0.847, blue: 0.812)
        case 2:
            return Color(red: 0.408, green: 0.718, blue: 0.639)
        case 3:
            return AppTheme.ColorToken.accentDark
        case 4:
            return AppTheme.ColorToken.accent
        default:
            return Color(red: 0.910, green: 0.938, blue: 0.925)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}

private struct HomeStatsGrid: View {
    let stats: HomeDashboardStats
    let focusedCharactersTitle: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: AppTheme.Spacing.grid)], spacing: AppTheme.Spacing.grid) {
            HomeStatCard(title: "累计字符", value: "\(stats.totalCharacters)", systemImage: "textformat.size")
            HomeStatCard(title: focusedCharactersTitle, value: "\(stats.todayCharacters)", systemImage: "calendar")
            HomeStatCard(title: "平均字/分钟", value: "\(stats.averageCPM)", systemImage: "speedometer")
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
    @State private var textVariant: HomeHistoryTextVariant = .final

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: selectAction) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.text(for: textVariant))
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                        .lineLimit(2)
                        .truncationMode(.head)
                    HStack(alignment: .center, spacing: 8) {
                        if let appName = item.appName {
                            SourceApplicationIcon(appName: appName, bundleID: item.appBundleID, size: 28)
                        }
                        if item.taskMode == .agentCompose {
                            Label("帮我说", systemImage: "sparkles")
                                .foregroundStyle(AppTheme.ColorToken.accent)
                        }
                        Text("\(item.charCount) 字")
                        Text("\(Int(item.cpm.rounded())) 字/分钟")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                textVariant = textVariant == .final ? .raw : .final
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!item.hasTextVariants)
            .help(textVariant == .final ? "显示转换前" : "显示转换后")
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

private struct HomeHistoryDetailOverlay: View {
    @ObservedObject var viewModel: HomeDashboardViewModel
    let detail: HomeHistoryDetail

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.dismissSelectedDetailFromBackdrop()
                }

            HomeHistoryDetailModal(viewModel: viewModel, detail: detail)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 28, y: 12)
                .contentShape(Rectangle())
                .onTapGesture {}
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum HomeHistoryDetailLayout {
    static let usesScrollableContent = true
    static let modalWidth: CGFloat = 980
    static let modalMinHeight: CGFloat = 480
    static let modalIdealHeight: CGFloat = 680
    static let modalMaxHeight: CGFloat = 760
    static let textComparisonMaxHeight: CGFloat = 220
    static let requestJSONMaxHeight: CGFloat = 220
}

private struct HomeHistoryDetailModal: View {
    @ObservedObject var viewModel: HomeDashboardViewModel
    let detail: HomeHistoryDetail
    @State private var isRequestJSONExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    textComparison
                    traceSection
                    metadataSection
                    warningsSection
                }
                .padding(.trailing, 2)
            }
            .scrollIndicators(.visible)
        }
        .padding(24)
        .frame(width: HomeHistoryDetailLayout.modalWidth)
        .frame(
            minHeight: HomeHistoryDetailLayout.modalMinHeight,
            idealHeight: HomeHistoryDetailLayout.modalIdealHeight,
            maxHeight: HomeHistoryDetailLayout.modalMaxHeight
        )
        .background(
            Color(nsColor: .textBackgroundColor)
        )
        .tint(AppTheme.ColorToken.accent)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(width: 46, height: 46)
                .background(AppTheme.ColorToken.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.icon, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(detail.taskMode == .agentCompose ? "帮我说详情" : "转写详情")
                    .font(.system(size: 24, weight: .semibold))
                Text(traceSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            if detail.taskMode != nil {
                Button {
                    viewModel.copySelectedTaskDiagnostic()
                } label: {
                    Label("复制诊断", systemImage: "stethoscope")
                        .frame(height: 32)
                }
                .buttonStyle(.bordered)
            }
            if detail.taskMode == .agentCompose {
                if !detail.finalText.isEmpty {
                    Button {
                        viewModel.copyDetailText()
                    } label: {
                        Label("复制结果", systemImage: "doc.on.doc")
                            .frame(height: 32)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button {
                    Task {
                        await viewModel.reprocessSelectedHistoryItem()
                    }
                } label: {
                    Label(viewModel.isReprocessing ? "处理中" : "重新处理", systemImage: viewModel.isReprocessing ? "hourglass" : "arrow.triangle.2.circlepath")
                        .frame(height: 32)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isReprocessing)
            }
            Button {
                viewModel.clearSelectedDetail()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .appControlSurface(cornerRadius: 8)
        }
    }

    private var textComparison: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 12) {
                DetailTextBlock(
                    title: "处理后",
                    subtitle: detail.taskMode == .agentCompose
                        ? "生成并写入当前输入框的文本"
                        : "最终注入到当前应用的文本",
                    text: detail.finalText,
                    highlighted: true
                )
                DetailTextBlock(
                    title: detail.taskMode == .agentCompose ? "语音意图" : "原文",
                    subtitle: detail.taskMode == .agentCompose
                        ? "语音识别出的用户指令"
                        : "语音识别返回的原始文本",
                    text: detail.rawText,
                    highlighted: false
                )
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: HomeHistoryDetailLayout.textComparisonMaxHeight)
    }

    @ViewBuilder
    private var traceSection: some View {
        if let llmTrace = detail.trace?.llm {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(detail.taskMode == .agentCompose ? "生成过程" : "文本纠错过程", systemImage: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text(llmTrace.succeeded ? "已调用" : "调用失败")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(llmTrace.succeeded ? AppTheme.ColorToken.accent : Color.orange)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background((llmTrace.succeeded ? AppTheme.ColorToken.accent : Color.orange).opacity(0.10))
                        .clipShape(Capsule())
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                    DetailMetaItem(
                        title: detail.taskMode == .agentCompose ? "生成服务" : "纠错服务",
                        value: llmTrace.providerName
                    )
                    DetailMetaItem(title: "使用模型", value: llmTrace.model)
                    DetailMetaItem(
                        title: "处理用时",
                        value: HomeHistoryDetailPresentation.durationText(milliseconds: llmTrace.durationMS)
                    )
                    DetailMetaItem(
                        title: "调用结果",
                        value: llmTrace.succeeded
                            ? "成功\(llmTrace.statusCode.map { "（\($0)）" } ?? "")"
                            : "失败\(llmTrace.statusCode.map { "（\($0)）" } ?? "")"
                    )
                    DetailMetaItem(title: "请求地址", value: llmTrace.endpoint)
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(detail.taskMode == .agentCompose ? "用户说的话" : "发送给模型的内容")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        Text(HomeHistoryDetailPresentation.requestBodyPreview(
                            from: llmTrace.requestBodyJSON,
                            taskMode: detail.taskMode
                        ))
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.ColorToken.primaryText)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                            .padding(10)
                            .background(Color(nsColor: .textBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        RequestJSONDisclosure(
                            requestBodyJSON: llmTrace.requestBodyJSON,
                            isExpanded: $isRequestJSONExpanded
                        )
                    }
                    .frame(maxWidth: .infinity)
                    DetailTextBlock(
                        title: llmTrace.errorMessage == nil ? "模型返回的内容" : "失败原因",
                        subtitle: llmTrace.errorMessage != nil ? "接口返回的错误信息" : "模型输出的原始文本",
                        text: llmTrace.errorMessage ?? llmTrace.responseText ?? "未返回内容",
                        highlighted: false
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .historyDetailPanel()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label(detail.taskMode == .agentCompose ? "生成过程" : "文本纠错过程", systemImage: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                Text(HomeHistoryDetailPresentation.missingTraceMessage(for: detail.taskMode))
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .historyDetailPanel()
        }
    }

    private var metadataSection: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: 170),
                    spacing: AppTheme.Spacing.grid,
                    alignment: .top
                )
            ],
            alignment: .leading,
            spacing: 10
        ) {
            DetailMetaItem(
                title: "识别语言",
                value: HomeHistoryDetailPresentation.languageName(for: detail.language)
            )
            DetailApplicationMetaItem(title: "使用应用", appName: detail.appName, appBundleID: detail.appBundleID)
            DetailMetaItem(
                title: "语音识别",
                value: HomeHistoryDetailPresentation.recognitionProviderName(for: detail.asrProviderID)
            )
            DetailMetaItem(
                title: detail.taskMode == .agentCompose ? "生成模型" : "文本纠错",
                value: HomeHistoryDetailPresentation.textCorrectionName(
                    providerID: detail.llmProviderID,
                    traceProviderName: detail.trace?.llm?.providerName
                )
            )
            DetailMetaItem(
                title: "表达风格",
                value: HomeHistoryDetailPresentation.styleName(for: detail.styleID)
            )
            DetailMetaItem(title: "文本长度", value: "\(detail.charCount) 个字符")
            DetailMetaItem(title: "处理速度", value: "\(Int(detail.cpm.rounded())) 字/分钟")
            DetailMetaItem(title: "首次创建", value: Self.format(detail.createdAt))
            DetailMetaItem(title: "最近更新", value: Self.format(detail.updatedAt))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .historyDetailPanel()
    }

    @ViewBuilder
    private var warningsSection: some View {
        if !detail.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("处理提示", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 16, weight: .semibold))
                ForEach(detail.warnings, id: \.self) { warning in
                    Text(HomeHistoryDetailPresentation.warningMessage(
                        for: warning,
                        taskMode: detail.taskMode
                    ))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .historyDetailPanel()
        }
    }

    private var traceSubtitle: String {
        if detail.taskMode == .agentCompose {
            return "查看语音意图、生成结果和本次处理信息"
        }
        if detail.trace?.llm != nil {
            return "对比识别原文与最终文本，并查看本次文本纠错过程"
        }
        return "对比识别原文与最终文本；旧记录可重新处理查看纠错过程"
    }

    private static func format(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }

}

private struct DetailTextBlock: View {
    let title: String
    let subtitle: String
    let text: String
    let highlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(highlighted ? AppTheme.ColorToken.accent : AppTheme.ColorToken.secondaryText)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlighted ? AppTheme.ColorToken.accentSoft.opacity(0.5) : AppTheme.ColorToken.controlBackground.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(highlighted ? AppTheme.ColorToken.selectionBorder : AppTheme.ColorToken.subtleStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
    }
}

private struct RequestJSONDisclosure: View {
    let requestBodyJSON: String
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 12)
                    Image(systemName: "curlybraces")
                    Text("查看完整请求 JSON")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollView {
                    Text(requestBodyJSON)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                }
                .frame(maxHeight: HomeHistoryDetailLayout.requestJSONMaxHeight)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .background(AppTheme.ColorToken.controlBackground.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private extension View {
    func historyDetailPanel() -> some View {
        background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

private struct DetailApplicationMetaItem: View {
    let title: String
    let appName: String?
    let appBundleID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            if let appName {
                HStack(alignment: .center, spacing: 6) {
                    SourceApplicationIcon(appName: appName, bundleID: appBundleID, size: 32)
                    Text(appName)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                        .lineLimit(1)
                }
            } else {
                Text("未记录")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SourceApplicationIcon: View {
    let appName: String
    var bundleID: String?
    var size: CGFloat

    var body: some View {
        Group {
            if let image = SourceApplicationIconResolver.image(for: appName, bundleID: bundleID) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.16)
            } else {
                Image(systemName: "app")
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.accent)
            }
        }
        .frame(width: size, height: size)
        .background(AppTheme.ColorToken.controlBackground)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .help(appName)
        .accessibilityLabel("使用应用：\(appName)")
    }
}

private enum SourceApplicationIconResolver {
    static func image(for appName: String, bundleID: String? = nil) -> NSImage? {
        let trimmedName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return nil
        }

        // Prefer bundleID-based lookup (most reliable)
        if let bundleID, !bundleID.isEmpty {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return NSWorkspace.shared.icon(forFile: appURL.path)
            }
        }

        // Fall back to appName-based lookup
        guard let resolvedBundleID = bundleIDFromAppName(for: trimmedName),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: resolvedBundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    private static func bundleIDFromAppName(for appName: String) -> String? {
        let normalizedName = appName.lowercased()
        if let bundleID = appNameAliases[normalizedName] {
            return bundleID
        }

        return KnownApplicationRegistry.builtIn().entries.first { entry in
            entry.displayName.localizedCaseInsensitiveCompare(appName) == .orderedSame
        }?.bundleID
    }

    private static let appNameAliases: [String: String] = [
        "微信": "com.tencent.xinWeChat",
        "wechat": "com.tencent.xinWeChat",
        "飞书": "com.tencent.Lark",
        "邮件": "com.apple.mail",
        "终端": "com.apple.Terminal",
    ]
}
