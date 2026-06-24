import AppKit
import SwiftUI
import VoxFlowVoiceCorrection

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

                HomeStatsGrid(stats: viewModel.stats, focusedAssetsTitle: viewModel.focusedAssetsTitle)
                HomeActivityCard(
                    activity: viewModel.activity,
                    selectedDate: viewModel.selectedActivityDate,
                    selectAction: viewModel.selectActivityDay,
                    clearAction: viewModel.restoreDefaultDashboardFocusFromActivityBlankTap
                )
                HomeAssetSection(viewModel: viewModel)
            }
            .padding(AppTheme.Spacing.page)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            viewModel.loadIfNeeded()
        }
    }
}

private struct HomeAssetSection: View {
    @ObservedObject var viewModel: HomeDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Label("资产", systemImage: "tray.full")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                    Text("共 \(viewModel.totalAssetCount) 条")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    Spacer(minLength: 16)
                    TextField(
                        "搜索资产",
                        text: Binding(
                            get: { viewModel.searchText },
                            set: { viewModel.updateSearch($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                }

                HStack(alignment: .center, spacing: 10) {
                    assetToolbarButton("清空数据", systemImage: "trash", role: .destructive) {
                        viewModel.clearAllAssets()
                    }
                    .disabled(viewModel.totalAssetCount == 0)

                    assetToolbarButton("删除选中", systemImage: "checklist", role: .destructive) {
                        viewModel.deleteSelectedAssets()
                    }
                    .disabled(viewModel.selectedAssetIDs.isEmpty)

                    assetToolbarButton(viewModel.areVisibleAssetsSelected ? "取消全选" : "全选", systemImage: "checklist") {
                        viewModel.toggleVisibleAssetSelection()
                    }
                    .disabled(viewModel.visibleAssetIDs.isEmpty)

                    Spacer(minLength: 16)

                    assetPagination

                    Picker("每页", selection: Binding(
                        get: { viewModel.pageSize },
                        set: { viewModel.updateAssetPageSize($0) }
                    )) {
                        ForEach([20, 50, 100], id: \.self) { size in
                            Text("\(size) 条/页").tag(size)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
            }

            if viewModel.assetGroups.isEmpty {
                Text("暂无资产")
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .appPanel()
            } else {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.grid) {
                    ForEach(viewModel.assetGroups, id: \.id) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                            ForEach(group.items, id: \.id) { item in
                                HomeAssetRow(
                                    item: item,
                                    isSelected: viewModel.selectedAssetIDs.contains(item.id),
                                    selectAction: { viewModel.selectAssetItem(id: item.id) },
                                    toggleSelectionAction: { viewModel.toggleAssetSelection(id: item.id) },
                                    copyAction: { viewModel.copyAssetItem(id: item.id) },
                                    deleteAction: { viewModel.deleteAssetItem(id: item.id) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func assetToolbarButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(height: 28)
        }
        .buttonStyle(.bordered)
    }

    private var assetPagination: some View {
        HStack(spacing: 6) {
            Button("上一页", action: viewModel.previousAssetPage)
                .disabled(!viewModel.canGoToPreviousAssetPage)
            ForEach(visibleAssetPageSlots, id: \.self) { slot in
                if let page = slot {
                    Button("\(page)") { viewModel.goToAssetPage(page) }
                        .buttonStyle(.bordered)
                        .background(
                            page == viewModel.assetCurrentPage
                                ? AppTheme.ColorToken.accentSoft
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Text("…")
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .frame(width: 22)
                }
            }
            Button("下一页", action: viewModel.nextAssetPage)
                .disabled(!viewModel.canGoToNextAssetPage)
        }
        .font(.system(size: 12, weight: .medium))
    }

    /// antd 表格风格分页槽位：`nil` 表示省略号 "…"，非 nil 表示可点击的页号。
    /// 总页数 ≤ 7 时全部显示；否则始终显示首末页 + 当前页 ± 1 + 必要的省略号。
    private var visibleAssetPageSlots: [Int?] {
        let total = viewModel.totalAssetPages
        let current = viewModel.assetCurrentPage
        guard total > 0 else { return [] }
        if total <= 7 {
            return (1...total).map { Optional($0) }
        }
        var slots: [Int?] = [1]
        let left = max(2, current - 1)
        let right = min(total - 1, current + 1)
        if left > 2 {
            slots.append(nil)
        }
        for p in left...right {
            slots.append(p)
        }
        if right < total - 1 {
            slots.append(nil)
        }
        slots.append(total)
        return slots
    }
}

private struct HomeAssetRow: View {
    let item: HomeAssetItem
    let isSelected: Bool
    let selectAction: () -> Void
    let toggleSelectionAction: () -> Void
    let copyAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: toggleSelectionAction) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? AppTheme.ColorToken.accent : AppTheme.ColorToken.secondaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: selectAction) {
                HStack(alignment: .center, spacing: 12) {
                    if let imagePath = item.imagePath,
                       let image = NSImage(contentsOfFile: imagePath),
                       item.systemImage == "photo" {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 34, height: 34)
                            .background(AppTheme.ColorToken.panelBackground)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.icon, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.icon, style: .continuous)
                                    .stroke(AppTheme.ColorToken.panelStroke, lineWidth: AppTheme.Border.panelLineWidth)
                            )
                    } else {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(AppTheme.ColorToken.accent)
                            .frame(width: 34, height: 34)
                            .background(AppTheme.ColorToken.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.ColorToken.primaryText)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Text(item.sourceTitle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.ColorToken.accent)
                            Text(item.contentTypeTitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                            if !item.previewText.isEmpty {
                                Text(item.previewText)
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: copyAction) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.ColorToken.accent)

            Button(role: .destructive, action: deleteAction) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(isSelected ? AppTheme.ColorToken.selectionBackground : AppTheme.ColorToken.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(
                    isSelected ? AppTheme.ColorToken.selectionBorder : AppTheme.ColorToken.panelStroke,
                    lineWidth: AppTheme.Border.panelLineWidth
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
    }
}

private struct HomeAssetDetailModal: View {
    @ObservedObject var viewModel: HomeDashboardViewModel
    let detail: HomeAssetItem

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail.title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                    HStack(spacing: 8) {
                        Text(detail.sourceTitle)
                        Text(detail.contentTypeTitle)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                Spacer()
                Button {
                    viewModel.clearSelectedHomeDetail()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }

            if let imagePath = detail.imagePath,
               let image = NSImage(contentsOfFile: imagePath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 360)
                    .background(AppTheme.ColorToken.pageBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
            }

            ScrollView {
                Text(detail.previewText.isEmpty ? "无可预览内容" : detail.previewText)
                    .font(.system(size: 15))
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 140, maxHeight: 260)
            .padding(14)
            .background(AppTheme.ColorToken.pageBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))

            HStack {
                Button {
                    viewModel.copyAssetItem(id: detail.id)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                Button(role: .destructive) {
                    viewModel.deleteAssetItem(id: detail.id)
                } label: {
                    Label("删除", systemImage: "trash")
                }
                Spacer()
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(width: 720)
        .background(AppTheme.ColorToken.panelBackground)
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
                                        .help(Self.tooltipText(for: day))
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
            return "本周 \(activity.thisWeekAssets) 条资产"
        }
        return "\(Self.dateFormatter.string(from: selectedDate)) \(selectedDay.assetCount) 条资产"
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

    private static func tooltipText(for day: HomeActivityDay) -> String {
        let dateText = dateFormatter.string(from: day.date)
        guard day.assetCount > 0 else {
            return "\(dateText) · 0 条资产"
        }
        return "\(dateText) · \(day.sourceBreakdown.summaryText)"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}

private struct HomeStatsGrid: View {
    let stats: HomeDashboardStats
    let focusedAssetsTitle: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: AppTheme.Spacing.grid)], spacing: AppTheme.Spacing.grid) {
            HomeStatCard(title: "累计资产", value: "\(stats.totalAssets)", systemImage: "tray.full")
            HomeStatCard(title: focusedAssetsTitle, value: "\(stats.focusedAssets)", systemImage: "calendar.badge.plus")
            HomeStatCard(title: "来源分布", value: stats.sourceBreakdown.summaryText, systemImage: "square.grid.2x2")
            HomeStatCard(title: "可复用内容", value: "\(stats.reusableAssets)", systemImage: "arrowshape.turn.up.right")
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
                .font(.system(size: value.count > 8 ? 18 : 30, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(AppTheme.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel()
    }
}

struct HomeDetailOverlay: View {
    @ObservedObject var viewModel: HomeDashboardViewModel
    let detail: HomeDetailSelection
    @State private var escapeMonitor: Any?

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.clearSelectedHomeDetail()
                }

            modalContent
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 28, y: 12)
                .contentShape(Rectangle())
                .onTapGesture {}
        }
        .onExitCommand(perform: viewModel.clearSelectedHomeDetail)
        .onAppear { attachEscapeMonitorIfNeeded() }
        .onDisappear { detachEscapeMonitor() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var modalContent: some View {
        switch detail {
        case .voice(let voiceDetail):
            HomeHistoryDetailModal(viewModel: viewModel, detail: voiceDetail)
        case .asset(let assetDetail):
            HomeAssetDetailModal(viewModel: viewModel, detail: assetDetail)
        }
    }

    private func attachEscapeMonitorIfNeeded() {
        guard escapeMonitor == nil else {
            return
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == Self.escapeKeyCode else {
                return event
            }
            viewModel.clearSelectedHomeDetail()
            return nil
        }
    }

    private func detachEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    private static let escapeKeyCode: UInt16 = 53
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
                    if detail.taskMode == .agentDispatch {
                        dispatchSection
                    } else {
                        traceSection
                    }
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
                Text(detailTitle)
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
            if detail.taskMode == .agentCompose || detail.taskMode == .agentDispatch {
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
                viewModel.clearSelectedHomeDetail()
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
                        : detail.taskMode == .agentDispatch
                            ? "发送到终端助手的语音指令"
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
                    DetailMetaItem(title: "服务地址", value: llmTrace.endpoint)
                }
                if let contextBoostTrace = detail.trace?.contextBoost {
                    ContextBoostTraceBlock(trace: contextBoostTrace)
                }
                if let voiceCorrectionTrace = detail.trace?.voiceCorrection {
                    VoiceCorrectionTraceBlock(trace: voiceCorrectionTrace)
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(detail.taskMode == .agentCompose ? "用户说的话" : "发送给模型的内容")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        Text(HomeHistoryDetailPresentation.modelInputPreview(
                            rawText: detail.rawText,
                            requestBodyJSON: llmTrace.requestBodyJSON,
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
        } else if let voiceCorrectionTrace = detail.trace?.voiceCorrection {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("文本纠错过程", systemImage: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text("本地后处理")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.accent)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(AppTheme.ColorToken.accent.opacity(0.10))
                        .clipShape(Capsule())
                }
                VoiceCorrectionTraceBlock(trace: voiceCorrectionTrace)
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

    private var dispatchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("调度结果", systemImage: "paperplane")
                .font(.system(size: 16, weight: .semibold))
            Text(detail.outputResultRaw ?? "未记录调度结果")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .historyDetailPanel()
    }

    private var metadataSection: some View {
        let textCorrectionValue = HomeHistoryDetailPresentation.textCorrectionName(
            providerID: detail.llmProviderID,
            traceProviderName: detail.trace?.llm?.providerName
        )
        return LazyVGrid(
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
            DetailProviderMetaItem(
                title: "语音识别",
                value: HomeHistoryDetailPresentation.recognitionProviderName(for: detail.asrProviderID),
                providerIcon: .asrProvider(detail.asrProviderID)
            )
            DetailProviderMetaItem(
                title: detail.taskMode == .agentCompose ? "生成模型" : "文本纠错",
                value: textCorrectionValue,
                providerIcon: .llmProvider
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
        if detail.taskMode == .agentDispatch {
            return "查看语音指令、任务助手投递结果和失败信息"
        }
        if detail.trace?.llm != nil {
            return "对比识别原文与最终文本，并查看本次文本纠错过程"
        }
        return "对比识别原文与最终文本；旧记录可重新处理查看纠错过程"
    }

    private var detailTitle: String {
        switch detail.taskMode {
        case .agentCompose: return "任务助手详情"
        case .agentDispatch: return "AI 编程详情"
        case .dictation, nil: return "转写详情"
        }
    }

    private static func format(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }

}

private struct ContextBoostTraceBlock: View {
    let trace: ContextBoostTrace

    private var sourceApplication: String {
        trace.appName ?? trace.bundleID ?? "未知应用"
    }

    private var statusColor: Color {
        trace.appliedToLLMPrompt ? AppTheme.ColorToken.accent : Color.orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("本次图片文字识别上下文", systemImage: "text.viewfinder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                Spacer(minLength: 8)
                Text(HomeHistoryDetailPresentation.contextBoostStatusText(
                    appliedToPrompt: trace.appliedToLLMPrompt
                ))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(statusColor.opacity(0.10))
                    .clipShape(Capsule())
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                DetailMetaItem(title: "来源应用", value: sourceApplication)
                DetailMetaItem(
                    title: "上下文来源",
                    value: HomeHistoryDetailPresentation.contextBoostSourceName(for: trace.source)
                )
                DetailMetaItem(title: "有效期", value: "\(trace.ttlSeconds) 秒")
                if let ocrCharacterCount = trace.ocrCharacterCount {
                    DetailMetaItem(title: "图片文字识别字符数", value: "\(ocrCharacterCount)")
                }
                if let candidateCount = trace.candidateCount {
                    DetailMetaItem(title: "候选数", value: "\(candidateCount)")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("前 K 条候选词")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                Text(HomeHistoryDetailPresentation.contextBoostHotwordsText(trace.hotwords))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !trace.hotwordDetails.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("候选词证据")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    ForEach(trace.hotwordDetails.prefix(8), id: \.text) { detail in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(detail.text)  ·  \(String(format: "%.1f", detail.score))  ·  \(detail.source)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(AppTheme.ColorToken.primaryText)
                                .textSelection(.enabled)
                            if !detail.evidenceReasons.isEmpty {
                                Text(detail.evidenceReasons.joined(separator: "、"))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }

            if let failureReason = trace.failureReason, !failureReason.isEmpty {
                Text("原因：\(HomeHistoryDetailPresentation.contextBoostFailureReasonText(failureReason))")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.ColorToken.controlBackground.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct VoiceCorrectionTraceBlock: View {
    let trace: VoiceCorrectionTrace

    private var displayedEvents: [CorrectionEvent] {
        trace.appliedEvents.isEmpty ? trace.candidateEvents : trace.appliedEvents
    }

    private var statusColor: Color {
        trace.failureReason == nil ? AppTheme.ColorToken.accent : Color.orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("本地后处理", systemImage: "wand.and.stars")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                Spacer(minLength: 8)
                Text(HomeHistoryDetailPresentation.voiceCorrectionStatusText(
                    candidateCount: trace.candidateEvents.count,
                    appliedCount: trace.appliedEvents.count,
                    failed: trace.failureReason != nil
                ))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(statusColor.opacity(0.10))
                    .clipShape(Capsule())
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                DetailMetaItem(title: "候选命中", value: "\(trace.candidateEvents.count) 条")
                DetailMetaItem(title: "实际替换", value: "\(trace.appliedEvents.count) 处")
                DetailMetaItem(title: "处理方式", value: "易错词规则")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(trace.appliedEvents.isEmpty ? "命中证据" : "替换明细")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                if displayedEvents.isEmpty {
                    Text("未命中任何易错词规则")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(displayedEvents.prefix(6), id: \.id) { event in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(event.original) -> \(event.replacement)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                                    .textSelection(.enabled)
                                Text("\(HomeHistoryDetailPresentation.voiceCorrectionScopeText(event.scope)) · \(event.source.rawValue)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if displayedEvents.count > 6 {
                            Text("另有 \(displayedEvents.count - 6) 条未展开")
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        }
                    }
                }
            }

            if !trace.warnings.isEmpty {
                Text("提示：\(trace.warnings.joined(separator: "、"))")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let failureReason = trace.failureReason, !failureReason.isEmpty {
                Text("原因：\(failureReason)")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.ColorToken.controlBackground.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                    Text("查看完整请求内容")
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

private struct DetailProviderMetaItem: View {
    enum ProviderIcon {
        case asrProvider(String?)
        case llmProvider
    }

    let title: String
    let value: String
    let providerIcon: ProviderIcon

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            HStack(alignment: .center, spacing: 7) {
                providerBadge
                Text(value)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var providerBadge: some View {
        switch providerIcon {
        case .asrProvider(let providerID):
            ASRProviderImageBadge(providerID: providerID)
        case .llmProvider:
            ProviderInitialBadge(text: value)
        }
    }
}

private struct ASRProviderImageBadge: View {
    let providerID: String?

    var body: some View {
        RoundedRectangle(cornerRadius: ProviderInitialBadge.metadataSize * 0.28, style: .continuous)
            .fill(AppTheme.ColorToken.controlBackground)
            .frame(width: ProviderInitialBadge.metadataSize, height: ProviderInitialBadge.metadataSize)
            .overlay(
                RoundedRectangle(cornerRadius: ProviderInitialBadge.metadataSize * 0.28, style: .continuous)
                    .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
            )
            .overlay {
                if let providerID, let image = ASRProviderIcon.load(providerID: providerID) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(AppTheme.ColorToken.accent)
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.accent)
                }
            }
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
                    SourceApplicationIcon(
                        appName: appName,
                        bundleID: appBundleID,
                        size: ProviderInitialBadge.metadataSize
                    )
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

@MainActor
private enum SourceApplicationIconResolver {
    private static var imageCache: [String: NSImage] = [:]

    static func image(for appName: String, bundleID: String? = nil) -> NSImage? {
        let trimmedName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return nil
        }
        let cacheKey = "\(bundleID ?? "")|\(trimmedName.lowercased())"
        if let cachedImage = imageCache[cacheKey] {
            return cachedImage
        }

        // Prefer bundleID-based lookup (most reliable)
        if let bundleID, !bundleID.isEmpty {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let image = NSWorkspace.shared.icon(forFile: appURL.path)
                imageCache[cacheKey] = image
                return image
            }
        }

        // Fall back to appName-based lookup
        guard let resolvedBundleID = bundleIDFromAppName(for: trimmedName),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: resolvedBundleID) else {
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: appURL.path)
        imageCache[cacheKey] = image
        return image
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
