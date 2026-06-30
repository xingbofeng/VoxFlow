import AppKit
import SwiftUI
import VoxFlowVoiceCorrection

struct HomeDashboardView: View {
    @ObservedObject var viewModel: HomeDashboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                HStack {
                    Label(L10n.localize("navigation.route.home", comment: ""), systemImage: "house.fill")
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
                    Label(L10n.localize("home.assets.title", comment: "Home assets title"), systemImage: "tray.full")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                    Text(L10n.format("home.assets.count_format", comment: "Home assets count",
                        viewModel.totalAssetCount
                    ))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    Spacer(minLength: 16)
                    TextField(
                        L10n.localize("home.assets.search_placeholder", comment: "Home assets search placeholder"),
                        text: Binding(
                            get: { viewModel.searchText },
                            set: { viewModel.updateSearch($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                }

                HStack(alignment: .center, spacing: 10) {
                    assetToolbarButton(L10n.localize("home.assets.clear_all", comment: "Clear all assets"), systemImage: "trash", role: .destructive) {
                        viewModel.clearAllAssets()
                    }
                    .disabled(viewModel.totalAssetCount == 0)

                    assetToolbarButton(L10n.localize("home.assets.delete_selected", comment: "Delete selected assets"), systemImage: "checklist", role: .destructive) {
                        viewModel.deleteSelectedAssets()
                    }
                    .disabled(viewModel.selectedAssetIDs.isEmpty)

                    assetToolbarButton(
                        viewModel.areVisibleAssetsSelected
                            ? L10n.localize("home.assets.deselect_all", comment: "Deselect all assets")
                            : L10n.localize("home.assets.select_all", comment: "Select all assets"),
                        systemImage: "checklist"
                    ) {
                        viewModel.toggleVisibleAssetSelection()
                    }
                    .disabled(viewModel.visibleAssetIDs.isEmpty)

                    Spacer(minLength: 16)

                    assetPagination

                    Picker(L10n.localize("home.assets.page_size", comment: "Page size"), selection: Binding(
                        get: { viewModel.pageSize },
                        set: { viewModel.updateAssetPageSize($0) }
                    )) {
                        ForEach([20, 50, 100], id: \.self) { size in
                            Text(L10n.format("home.assets.page_size_option_format", comment: "Page size option",
                                size
                            )).tag(size)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
            }

            if viewModel.assetGroups.isEmpty {
                Text(L10n.localize("home.assets.empty", comment: "No assets empty state"))
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
            Button(L10n.localize("home.assets.previous_page", comment: "Previous page"), action: viewModel.previousAssetPage)
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
            Button(L10n.localize("home.assets.next_page", comment: "Next page"), action: viewModel.nextAssetPage)
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
                    if let sourceAppName = item.sourceAppName {
                        SourceApplicationIcon(
                            appName: sourceAppName,
                            bundleID: item.sourceAppBundleID,
                            size: 34
                        )
                    } else if let imagePath = item.imagePath,
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
                Text(detail.previewText.isEmpty ? L10n.localize("home.assets.no_preview", comment: "No preview") : detail.previewText)
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
                    Label(L10n.localize("home.assets.copy", comment: "Copy asset"), systemImage: "doc.on.doc")
                }
                Button(role: .destructive) {
                    viewModel.deleteAssetItem(id: detail.id)
                } label: {
                    Label(L10n.localize("home.assets.delete", comment: "Delete asset"), systemImage: "trash")
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
                    Label(L10n.localize("home.activity.title", comment: "Activity title"), systemImage: "square.grid.3x3.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(L10n.localize("home.activity.subtitle", comment: "Activity subtitle"))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(summaryText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    if selectedDate != nil {
                        Button(L10n.localize("home.activity.clear", comment: "Clear activity selection")) {
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
                Text(L10n.localize("home.activity.less", comment: "Less activity"))
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color(for: level))
                        .frame(width: 10, height: 10)
                }
                Text(L10n.localize("home.activity.more", comment: "More activity"))
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
            return L10n.format("home.activity.this_week_assets_format", comment: "This week assets",
                activity.thisWeekAssets
            )
        }
        return L10n.format("home.activity.day_assets_format", comment: "Day assets",
            Self.dateFormatter.string(from: selectedDate),
            selectedDay.assetCount
        )
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
            return L10n.localize("home.activity.weekday.monday", comment: "Monday short")
        case 1:
            return L10n.localize("home.activity.weekday.tuesday", comment: "Tuesday short")
        case 2:
            return L10n.localize("home.activity.weekday.wednesday", comment: "Wednesday short")
        case 3:
            return L10n.localize("home.activity.weekday.thursday", comment: "Thursday short")
        case 4:
            return L10n.localize("home.activity.weekday.friday", comment: "Friday short")
        case 5:
            return L10n.localize("home.activity.weekday.saturday", comment: "Saturday short")
        case 6:
            return L10n.localize("home.activity.weekday.sunday", comment: "Sunday short")
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
            return L10n.format("home.activity.tooltip_empty_format", comment: "Activity tooltip empty",
                dateText
            )
        }
        return "\(dateText) · \(day.sourceBreakdown.summaryText)"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()
}

private struct HomeStatsGrid: View {
    let stats: HomeDashboardStats
    let focusedAssetsTitle: String

    var body: some View {
        HStack(spacing: Self.cardSpacing) {
            HomeStatCard(title: L10n.localize("home.stats.total_assets", comment: "Total assets stat"), value: "\(stats.totalAssets)", systemImage: "tray.full")
                .compact()
            HomeStatCard(title: focusedAssetsTitle, value: "\(stats.focusedAssets)", systemImage: "calendar.badge.plus")
                .compact()
            HomeStatCard(title: L10n.localize("home.source.dictation", comment: "Dictation source"), value: "\(stats.sourceBreakdown.dictation)", systemImage: "waveform")
                .compact()
            HomeStatCard(title: L10n.localize("home.source.screenshot", comment: "Screenshot source"), value: "\(stats.sourceBreakdown.screenshot)", systemImage: "camera.viewfinder")
                .compact()
            HomeStatCard(title: L10n.localize("home.source.clipboard", comment: "Clipboard source"), value: "\(stats.sourceBreakdown.clipboard)", systemImage: "clipboard")
                .compact()
            HomeStatCard(title: L10n.localize("home.stats.reusable_assets", comment: "Reusable assets stat"), value: "\(stats.reusableAssets)", systemImage: "arrowshape.turn.up.right")
                .compact()
        }
    }

    private static let cardSpacing: CGFloat = 10
}

private struct HomeStatCard: View {
    let title: String
    let value: String
    let systemImage: String
    private var usesCompactLayout = false

    init(title: String, value: String, systemImage: String) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: usesCompactLayout ? 8 : 10) {
            HStack(spacing: usesCompactLayout ? 7 : 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(AppTheme.ColorToken.accent)
                Text(title)
                    .font(.system(size: usesCompactLayout ? 12 : 13, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
            }
            Text(value)
                .font(.system(size: valueFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(usesCompactLayout ? 12 : AppTheme.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel()
    }

    func compact() -> Self {
        var copy = self
        copy.usesCompactLayout = true
        return copy
    }

    private var valueFontSize: CGFloat {
        if value.count > 8 {
            return usesCompactLayout ? 17 : 18
        }
        return usesCompactLayout ? 26 : 30
    }
}

enum HomeDetailOverlayPresentation {
    static let hostsActionFeedback = true
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
        .actionFeedbackOverlay(
            message: viewModel.lastActionMessage,
            error: viewModel.lastError,
            tone: viewModel.lastActionTone,
            onDismiss: viewModel.clearFeedback
        )
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
    /// When true, the Header and top result comparison area live above the
    /// diagnostic `ScrollView`; only dispatch info, transcription info,
    /// pipeline, warnings, and diagnostics scroll.
    static let usesFixedResultSection = true
    /// When true, the lower diagnostic region scrolls independently while the
    /// Header and top result comparison stay visible.
    static let scrollsDiagnosticsBelowResults = true
    static let modalWidth: CGFloat = 980
    static let modalMinHeight: CGFloat = 480
    static let modalIdealHeight: CGFloat = 680
    static let modalMaxHeight: CGFloat = 760
    static let textComparisonMaxHeight: CGFloat = 180
    static let requestJSONMaxHeight: CGFloat = 220
}

private struct HomeHistoryDetailModal: View {
    @ObservedObject var viewModel: HomeDashboardViewModel
    let detail: HomeHistoryDetail
    @State private var isRequestJSONExpanded = false
    @State private var isResponseJSONExpanded = false
    @State private var isEditingFinalText = false
    @State private var editedFinalText = ""
    @State private var editError: String?
    @State private var learnedEditPair: LearnedCorrectionPair?
    @State private var selectedStep: HomeHistoryDetailPresentation.PipelineStepKind = .asr
    @State private var isDiagnosticRequestExpanded = false
    @State private var isDiagnosticResponseExpanded = false
    @State private var isDiagnosticFullExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 16)
            // Fixed top result area: Header and result comparison stay visible
            // while only the lower diagnostic content scrolls below.
            resultComparisonSection
                .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if detail.taskMode == .agentDispatch {
                        dispatchSection
                    }
                    transcriptionInfoSection
                    pipelineTimelineSection
                    warningsSection
                    diagnosticDisclosureSection
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
        .onAppear {
            resetFinalTextEditor()
            resetSelectedStep()
        }
        .onChange(of: detail.id) { _, _ in
            resetFinalTextEditor()
            resetSelectedStep()
        }
        .onChange(of: detail.finalText) { _, _ in
            if !isEditingFinalText {
                editedFinalText = detail.finalText
            }
        }
    }

    // MARK: - Header

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
                Text(L10n.localize("home.detail.subtitle.unified", comment: "Unified detail subtitle"))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            headerActions
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        if detail.taskMode == nil {
            if isEditingFinalText {
                Button {
                    cancelFinalTextEditing()
                } label: {
                    Label(L10n.localize("home.detail.action.cancel", comment: "Cancel edit detail text"), systemImage: "xmark")
                        .frame(height: 32)
                }
                .buttonStyle(.bordered)
            }
            Button {
                if isEditingFinalText {
                    saveEditedFinalText()
                } else {
                    beginFinalTextEditing()
                }
            } label: {
                Label(isEditingFinalText ? L10n.localize("home.detail.action.save", comment: "Save edited detail text") : L10n.localize("home.detail.action.edit", comment: "Edit detail text"), systemImage: isEditingFinalText ? "checkmark" : "square.and.pencil")
                    .frame(height: 32)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isEditingFinalText && editedFinalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        if detail.taskMode != nil {
            Button {
                viewModel.copySelectedTaskDiagnostic()
            } label: {
                Label(L10n.localize("home.detail.action.copy_diagnostic", comment: "Copy diagnostic"), systemImage: "stethoscope")
                    .frame(height: 32)
            }
            .buttonStyle(.bordered)
        }
        if detail.taskMode == .agentCompose || detail.taskMode == .agentDispatch {
            if !detail.finalText.isEmpty {
                Button {
                    viewModel.copyDetailText()
                } label: {
                    Label(L10n.localize("home.detail.action.copy_result", comment: "Copy result"), systemImage: "doc.on.doc")
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
                Label(viewModel.isReprocessing ? L10n.localize("home.detail.action.processing", comment: "Processing") : L10n.localize("home.detail.action.reprocess", comment: "Reprocess"), systemImage: viewModel.isReprocessing ? "hourglass" : "arrow.triangle.2.circlepath")
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

    // MARK: - Result comparison section

    private var resultComparisonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isEditingFinalText {
                // Edit mode keeps the existing two-card layout so the user can
                // edit the final text while still seeing the raw recognition.
                HStack(alignment: .top, spacing: 12) {
                    EditableDetailTextBlock(
                        title: L10n.localize("home.detail.text.final_title", comment: "Final text title"),
                        subtitle: L10n.localize("home.detail.text.edit_subtitle", comment: "Edited final text subtitle"),
                        text: $editedFinalText,
                        error: editError
                    )
                    DetailTextBlock(
                        title: rawCardTitle,
                        subtitle: rawCardSubtitle,
                        text: detail.rawText,
                        highlighted: false
                    )
                }
            } else {
                // View mode replaces the two-card layout with a single
                // TextComparisonView that toggles between source / processed /
                // comparison. The task-mode subtitle stays above it so users
                // still know what the final text represents.
                Text(taskModeFinalSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                TextComparisonView(input: TextComparisonInput(
                    sourceTitle: rawCardTitle,
                    processedTitle: L10n.localize("home.detail.text.final_title", comment: "Final text title"),
                    sourceText: detail.rawText,
                    processedText: detail.finalText,
                    emptyPlaceholder: L10n.localize("home.detail.deterministic.empty_text", comment: "Empty deterministic text placeholder")
                ))
            }
            diffPillRow
            if let learnedEditPair {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(AppTheme.ColorToken.accent)
                    Text(L10n.format("home.detail.learning.saved_format", comment: "Saved edit learning message",
                        learnedEditPair.original,
                        learnedEditPair.replacement
                    ))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(AppTheme.ColorToken.accentSoft.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.ColorToken.selectionBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var rawCardTitle: String {
        detail.taskMode == .agentCompose
            ? L10n.localize("home.detail.text.voice_intent_title", comment: "Voice intent title")
            : L10n.localize("home.detail.text.raw_title", comment: "Raw recognition title")
    }

    private var rawCardSubtitle: String {
        detail.taskMode == .agentCompose
            ? L10n.localize("home.detail.text.voice_intent_subtitle", comment: "Voice intent subtitle")
            : L10n.localize("home.detail.text.raw_subtitle", comment: "Raw recognition subtitle")
    }

    private var taskModeFinalSubtitle: String {
        switch detail.taskMode {
        case .agentCompose:
            return L10n.localize("home.detail.text.agent_compose_final_subtitle", comment: "Agent compose final text subtitle")
        case .agentDispatch:
            return L10n.localize("home.detail.text.agent_dispatch_final_subtitle", comment: "Agent dispatch final text subtitle")
        default:
            return L10n.localize("home.detail.text.dictation_final_subtitle", comment: "Dictation final text subtitle")
        }
    }

    @ViewBuilder
    private var diffPillRow: some View {
        if let diffPreview = HomeHistoryDetailPresentation.diffPreviewText(for: detail),
           let statusText = HomeHistoryDetailPresentation.diffStatusText(for: detail) {
            HStack(spacing: 8) {
                Text(diffPreview)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(AppTheme.ColorToken.controlBackground)
                    .clipShape(Capsule())
                Text(statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(diffStatusColor)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(diffStatusColor.opacity(0.10))
                    .clipShape(Capsule())
                Spacer(minLength: 0)
            }
        }
    }

    private var diffStatusColor: Color {
        if let llm = detail.trace?.llm, !llm.succeeded {
            return Color.orange
        }
        if let vc = detail.trace?.voiceCorrection, vc.appliedEvents.isEmpty == false {
            return AppTheme.ColorToken.accent
        }
        let raw = detail.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = detail.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw == final ? AppTheme.ColorToken.secondaryText : AppTheme.ColorToken.accent
    }

    // MARK: - Pipeline timeline section

    @ViewBuilder
    private var pipelineTimelineSection: some View {
        let steps = HomeHistoryDetailPresentation.pipelineSteps(for: detail)
        VStack(alignment: .leading, spacing: 12) {
            // Header with title and overall status
            HStack {
                Label(
                    L10n.localize("home.detail.pipeline.title", comment: "Pipeline title"),
                    systemImage: "sparkles"
                )
                .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text(HomeHistoryDetailPresentation.pipelineStatusText(for: detail))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HomeHistoryDetailPresentation.pipelineStatusColor(for: detail))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(HomeHistoryDetailPresentation.pipelineStatusColor(for: detail).opacity(0.10))
                    .clipShape(Capsule())
            }

            if steps.isEmpty {
                Text(L10n.localize("home.detail.diagnostic.missing_pipeline", comment: "Missing pipeline message"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            } else {
                // Horizontal timeline of clickable step chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(steps) { stepInfo in
                            pipelineStepChip(stepInfo)
                        }
                    }
                }

                // Step detail card for the selected step
                stepDetailCard
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .historyDetailPanel()
    }

    private func pipelineStepChip(_ stepInfo: HomeHistoryDetailPresentation.PipelineStepInfo) -> some View {
        let isSelected = selectedStep == stepInfo.kind
        let statusColor = pipelineStepStatusColor(stepInfo.status)
        return Button {
            selectedStep = stepInfo.kind
        } label: {
            HStack(spacing: 6) {
                Image(systemName: stepInfo.kind.systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(stepInfo.kind.title)
                    .font(.system(size: 12, weight: .medium))
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
            }
            .foregroundStyle(isSelected ? AppTheme.ColorToken.primaryText : AppTheme.ColorToken.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                isSelected
                    ? AppTheme.ColorToken.accent.opacity(0.12)
                    : AppTheme.ColorToken.controlBackground.opacity(0.82)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? AppTheme.ColorToken.accent : AppTheme.ColorToken.subtleStroke, lineWidth: isSelected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func pipelineStepStatusColor(_ status: HomeHistoryDetailPresentation.PipelineStepStatus) -> Color {
        switch status {
        case .success, .hit, .modified: return AppTheme.ColorToken.accent
        case .skipped, .missed: return AppTheme.ColorToken.secondaryText
        case .failed: return Color.orange
        case .executed: return AppTheme.ColorToken.accent
        }
    }

    @ViewBuilder
    private var stepDetailCard: some View {
        let steps = HomeHistoryDetailPresentation.pipelineSteps(for: detail)
        let stepInfo = steps.first(where: { $0.kind == selectedStep })
        let status = stepInfo?.status ?? .skipped

        VStack(alignment: .leading, spacing: 10) {
            // Step header with status
            HStack(spacing: 8) {
                if let stepInfo {
                    Text(stepInfo.kind.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                }
                Spacer(minLength: 8)
                Text(status.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(pipelineStepStatusColor(status))
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(pipelineStepStatusColor(status).opacity(0.10))
                    .clipShape(Capsule())
            }

            Divider()

            // Step-specific content
            stepDetailContent(for: selectedStep, status: status)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.ColorToken.controlBackground.opacity(0.42))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func stepDetailContent(
        for kind: HomeHistoryDetailPresentation.PipelineStepKind,
        status: HomeHistoryDetailPresentation.PipelineStepStatus
    ) -> some View {
        switch kind {
        case .asr:
            asrStepDetail
        case .deterministic:
            if let deterministicTrace = detail.trace?.deterministic {
                DeterministicTraceBlock(trace: deterministicTrace)
            } else {
                Text(L10n.localize("home.detail.diagnostic.no_trace", comment: "No trace for step"))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
        case .textReplacement:
            if let vcTrace = detail.trace?.voiceCorrection {
                VoiceCorrectionTraceBlock(trace: vcTrace)
            } else {
                Text(L10n.localize("home.detail.diagnostic.no_trace", comment: "No trace for step"))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
        case .styleRoute:
            if let routeTrace = detail.trace?.styleRoute {
                styleRouteStepDetail(routeTrace)
            } else {
                Text(L10n.localize("home.detail.diagnostic.no_trace", comment: "No trace for step"))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
        case .context:
            contextStepDetail
        case .llm:
            if let llmTrace = detail.trace?.llm {
                llmStepDetail(llmTrace)
            } else {
                Text(L10n.localize("home.detail.diagnostic.no_trace", comment: "No trace for step"))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
        case .output:
            Text(L10n.localize("home.detail.diagnostic.executed_no_detail", comment: "Executed no detail"))
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
    }

    @ViewBuilder
    private var contextStepDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let contextTrace = detail.trace?.contextBoost {
                ContextBoostTraceBlock(trace: contextTrace)
            } else {
                Text(L10n.localize("home.detail.diagnostic.no_trace", comment: "No trace for step"))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            ContextPreviewBlock(preview: detail.contextPreview)
        }
    }

    private var asrStepDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                DetailMetaItem(
                    title: L10n.localize("home.detail.meta.asr_provider", comment: "ASR provider"),
                    value: HomeHistoryDetailPresentation.recognitionProviderName(for: detail.asrProviderID)
                )
                DetailMetaItem(
                    title: L10n.localize("home.detail.meta.recognition_language", comment: "Recognition language"),
                    value: HomeHistoryDetailPresentation.languageName(for: detail.language)
                )
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.localize("home.detail.text.raw_title", comment: "Raw recognition title"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                Text(detail.rawText)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func styleRouteStepDetail(_ trace: StyleRouteTrace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                DetailMetaItem(
                    title: L10n.localize("home.detail.meta.application", comment: "Application used"),
                    value: detail.appName ?? detail.appBundleID ?? L10n.localize("home.detail.meta.not_recorded", comment: "Not recorded")
                )
                DetailMetaItem(
                    title: L10n.localize("home.detail.meta.style", comment: "Writing style"),
                    value: HomeHistoryDetailPresentation.styleName(for: trace.selectedStyleID)
                )
            }
            if !trace.candidateStyleIDs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.localize("home.detail.pipeline.step.style_route", comment: "Style route step title"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    Text(trace.candidateStyleIDs.map { HomeHistoryDetailPresentation.styleName(for: $0) }.joined(separator: "、"))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                        .textSelection(.enabled)
                }
            }
            if let fallbackReason = trace.fallbackReason, !fallbackReason.isEmpty {
                Text(L10n.format("home.detail.reason_format", comment: "Reason format", HomeHistoryDetailPresentation.styleRouteFallbackReasonText(fallbackReason)))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
        }
    }

    private func llmStepDetail(_ llmTrace: LLMRefinementTrace) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            llmTraceMetadata(llmTrace, taskMode: detail.taskMode)
        }
    }

    // MARK: - Transcription info section

    private var transcriptionInfoSection: some View {
        let textCorrectionValue = HomeHistoryDetailPresentation.textCorrectionName(
            providerID: detail.llmProviderID,
            traceProviderName: detail.trace?.llm?.providerName
        )
        return VStack(alignment: .leading, spacing: 12) {
            Label(
                L10n.localize("home.detail.section.transcription_info", comment: "Transcription info section title"),
                systemImage: "info.circle"
            )
            .font(.system(size: 16, weight: .semibold))

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
                    title: L10n.localize("home.detail.meta.recognition_language", comment: "Recognition language"),
                    value: HomeHistoryDetailPresentation.languageName(for: detail.language)
                )
                DetailApplicationMetaItem(title: L10n.localize("home.detail.meta.application", comment: "Application used"), appName: detail.appName, appBundleID: detail.appBundleID)
                DetailProviderMetaItem(
                    title: L10n.localize("home.detail.meta.asr_provider", comment: "ASR provider"),
                    value: HomeHistoryDetailPresentation.recognitionProviderName(for: detail.asrProviderID),
                    providerIcon: .asrProvider(detail.asrProviderID)
                )
                DetailProviderMetaItem(
                    title: detail.taskMode == .agentCompose ? L10n.localize("home.detail.meta.generation_model", comment: "Generation model") : L10n.localize("home.detail.meta.text_correction", comment: "Text correction"),
                    value: textCorrectionValue,
                    providerIcon: .llmProvider
                )
                DetailMetaItem(
                    title: L10n.localize("home.detail.meta.style", comment: "Writing style"),
                    value: HomeHistoryDetailPresentation.styleName(for: detail.styleID)
                )
                DetailMetaItem(title: L10n.localize("home.detail.meta.text_length", comment: "Text length"), value: L10n.format("home.detail.meta.characters_format", comment: "Character count", detail.charCount))
                DetailMetaItem(title: L10n.localize("home.detail.meta.processing_speed", comment: "Processing speed"), value: L10n.format("home.detail.meta.cpm_format", comment: "Characters per minute", Int(detail.cpm.rounded())))
                DetailMetaItem(title: L10n.localize("home.detail.meta.created_at", comment: "Created at"), value: Self.format(detail.createdAt))
                DetailMetaItem(title: L10n.localize("home.detail.meta.updated_at", comment: "Updated at"), value: Self.format(detail.updatedAt))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .historyDetailPanel()
    }

    // MARK: - Warnings section

    @ViewBuilder
    private var warningsSection: some View {
        if !detail.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.localize("home.detail.warnings.title", comment: "Processing warnings title"), systemImage: "exclamationmark.triangle")
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

    // MARK: - Diagnostic disclosure section

    private var diagnosticDisclosureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                L10n.localize("home.detail.section.diagnostic", comment: "Diagnostic section title"),
                systemImage: "stethoscope"
            )
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppTheme.ColorToken.secondaryText)

            DiagnosticDisclosureRow(
                title: L10n.localize("home.detail.diagnostic.request", comment: "Request diagnostic group"),
                systemImage: "arrow.up.doc",
                isExpanded: $isDiagnosticRequestExpanded
            ) {
                if let llmTrace = detail.trace?.llm {
                    LLMJSONDisclosure(
                        title: L10n.localize("home.detail.llm.request_json_title", comment: "Request JSON title"),
                        subtitle: L10n.localize("home.detail.llm.request_summary_subtitle", comment: "Request summary subtitle"),
                        summaryTitle: detail.taskMode == .agentCompose ? L10n.localize("home.detail.trace.user_speech", comment: "User speech label") : L10n.localize("home.detail.llm.pending_text", comment: "Pending text label"),
                        summaryText: HomeHistoryDetailPresentation.modelInputPreview(
                            rawText: detail.rawText,
                            requestBodyJSON: llmTrace.requestBodyJSON,
                            taskMode: detail.taskMode
                        ),
                        jsonText: llmTrace.requestBodyJSON,
                        expandTitle: L10n.localize("home.detail.llm.expand_request_json", comment: "Expand request JSON"),
                        isExpanded: $isRequestJSONExpanded
                    )
                } else {
                    diagnosticText(requestDiagnosticSummary)
                }
            }

            DiagnosticDisclosureRow(
                title: L10n.localize("home.detail.diagnostic.response", comment: "Response diagnostic group"),
                systemImage: "arrow.down.doc",
                isExpanded: $isDiagnosticResponseExpanded
            ) {
                if let llmTrace = detail.trace?.llm {
                    LLMJSONDisclosure(
                        title: L10n.localize("home.detail.llm.response_json_title", comment: "Response JSON title"),
                        subtitle: llmTrace.errorMessage == nil ? L10n.localize("home.detail.llm.response_summary_subtitle", comment: "Response summary subtitle") : L10n.localize("home.detail.trace.api_error_subtitle", comment: "API error subtitle"),
                        summaryTitle: llmTrace.errorMessage == nil ? L10n.localize("home.detail.llm.returned_text", comment: "Returned text label") : L10n.localize("home.detail.trace.failure_reason_title", comment: "Failure reason title"),
                        summaryText: HomeHistoryDetailPresentation.modelOutputPreview(
                            responseText: llmTrace.responseText,
                            errorMessage: llmTrace.errorMessage
                        ),
                        jsonText: llmTrace.errorMessage ?? llmTrace.responseText ?? L10n.localize("home.detail.trace.empty_response", comment: "Empty model response"),
                        expandTitle: L10n.localize("home.detail.llm.expand_response_json", comment: "Expand response JSON"),
                        isExpanded: $isResponseJSONExpanded
                    )
                } else {
                    diagnosticText(responseDiagnosticSummary)
                }
            }

            DiagnosticDisclosureRow(
                title: L10n.localize("home.detail.diagnostic.full_data", comment: "Full diagnostic data"),
                systemImage: "curlybraces",
                isExpanded: $isDiagnosticFullExpanded
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button {
                            viewModel.copySelectedTaskDiagnostic()
                        } label: {
                            Label(L10n.localize("home.detail.action.copy_diagnostic", comment: "Copy diagnostic"), systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Spacer(minLength: 0)
                    }

                    DiagnosticReadableSummaryView(
                        summary: HomeHistoryDetailPresentation.userVisibleDiagnosticSummary(for: detail)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .historyDetailPanel()
    }

    private func diagnosticText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(AppTheme.ColorToken.primaryText)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var requestDiagnosticSummary: String {
        guard let llmTrace = detail.trace?.llm else {
            return L10n.localize("home.detail.diagnostic.no_trace", comment: "No trace for step")
        }
        return HomeHistoryDetailPresentation.modelInputPreview(
            rawText: detail.rawText,
            requestBodyJSON: llmTrace.requestBodyJSON,
            taskMode: detail.taskMode
        )
    }

    private var responseDiagnosticSummary: String {
        guard let llmTrace = detail.trace?.llm else {
            return HomeHistoryDetailPresentation.pipelineStatusText(for: detail)
        }
        return HomeHistoryDetailPresentation.modelOutputPreview(
            responseText: llmTrace.responseText,
            errorMessage: llmTrace.errorMessage
        )
    }

    // MARK: - Dispatch section (for agentDispatch mode)

    @ViewBuilder
    private var dispatchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.localize("home.detail.dispatch.title", comment: "Dispatch result title"), systemImage: "paperplane")
                .font(.system(size: 16, weight: .semibold))
            Text(detail.outputResultRaw ?? L10n.localize("home.detail.dispatch.empty", comment: "No dispatch result recorded"))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .historyDetailPanel()
    }

    // MARK: - LLM trace metadata helper

    private func llmTraceMetadata(
        _ llmTrace: LLMRefinementTrace,
        taskMode: VoiceTaskMode?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: 180),
                        spacing: 10,
                        alignment: .top
                    )
                ],
                alignment: .leading,
                spacing: 10
            ) {
                DetailMetaItem(
                    title: taskMode == .agentCompose ? L10n.localize("home.detail.meta.generation_service", comment: "Generation service") : L10n.localize("home.detail.meta.correction_service", comment: "Correction service"),
                    value: llmTrace.providerName
                )
                DetailMetaItem(title: L10n.localize("home.detail.meta.model", comment: "Used model"), value: llmTrace.model)
                DetailMetaItem(
                    title: L10n.localize("home.detail.meta.duration", comment: "Processing duration"),
                    value: HomeHistoryDetailPresentation.durationText(milliseconds: llmTrace.durationMS)
                )
                DetailMetaItem(
                    title: L10n.localize("home.detail.meta.call_result", comment: "Call result"),
                    value: llmTrace.succeeded
                        ? L10n.format("home.detail.meta.call_success_format", comment: "Call success with optional status", llmTrace.statusCode.map { "（\($0)）" } ?? "")
                        : L10n.format("home.detail.meta.call_failure_format", comment: "Call failure with optional status", llmTrace.statusCode.map { "（\($0)）" } ?? "")
                )
            }
            DetailMetaItem(title: L10n.localize("home.detail.meta.endpoint", comment: "Service endpoint"), value: llmTrace.endpoint)
        }
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var detailTitle: String {
        switch detail.taskMode {
        case .agentCompose: return L10n.localize("home.detail.title.agent_compose", comment: "Agent compose detail title")
        case .agentDispatch: return L10n.localize("home.detail.title.agent_dispatch", comment: "Agent dispatch detail title")
        case .dictation, nil: return L10n.localize("home.detail.title.dictation", comment: "Dictation detail title")
        }
    }

    private static func format(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }

    private func beginFinalTextEditing() {
        editedFinalText = detail.finalText
        editError = nil
        learnedEditPair = nil
        isEditingFinalText = true
    }

    private func cancelFinalTextEditing() {
        resetFinalTextEditor()
    }

    private func saveEditedFinalText() {
        do {
            let learningPair = HomeHistoryDetailPresentation.learningPair(
                originalText: detail.finalText,
                editedText: editedFinalText
            )
            try viewModel.updateSelectedHistoryFinalText(editedFinalText)
            learnedEditPair = learningPair
            editError = nil
            isEditingFinalText = false
        } catch {
            editError = error.localizedDescription
        }
    }

    private func resetFinalTextEditor() {
        editedFinalText = detail.finalText
        editError = nil
        isEditingFinalText = false
    }

    private func resetSelectedStep() {
        selectedStep = HomeHistoryDetailPresentation.defaultSelectedStep(for: detail)
        isRequestJSONExpanded = false
        isResponseJSONExpanded = false
        isDiagnosticRequestExpanded = false
        isDiagnosticResponseExpanded = false
        isDiagnosticFullExpanded = false
        learnedEditPair = nil
    }
}

private struct ContextBoostTraceBlock: View {
    let trace: ContextBoostTrace

    private var sourceApplication: String {
        trace.appName ?? trace.bundleID ?? L10n.localize("home.detail.context.unknown_app", comment: "Unknown app")
    }

    private var statusColor: Color {
        trace.appliedToLLMPrompt ? AppTheme.ColorToken.accent : Color.orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(L10n.localize("home.detail.context.title", comment: "OCR context title"), systemImage: "text.viewfinder")
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
                DetailMetaItem(title: L10n.localize("home.detail.context.source_app", comment: "Context source app"), value: sourceApplication)
                DetailMetaItem(
                    title: L10n.localize("home.detail.context.source", comment: "Context source"),
                    value: HomeHistoryDetailPresentation.contextBoostSourceName(for: trace.source)
                )
                DetailMetaItem(title: L10n.localize("home.detail.context.ttl", comment: "Context TTL"), value: L10n.format("home.detail.seconds_format", comment: "Seconds format", trace.ttlSeconds))
                if let ocrCharacterCount = trace.ocrCharacterCount {
                    DetailMetaItem(title: L10n.localize("home.detail.context.ocr_characters", comment: "OCR character count"), value: "\(ocrCharacterCount)")
                }
                if let candidateCount = trace.candidateCount {
                    DetailMetaItem(title: L10n.localize("home.detail.context.candidate_count", comment: "Candidate count"), value: "\(candidateCount)")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.localize("home.detail.context.top_candidates", comment: "Top candidate hotwords"))
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
                    Text(L10n.localize("home.detail.context.candidate_evidence", comment: "Candidate evidence"))
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
                Text(L10n.format("home.detail.reason_format", comment: "Reason format", HomeHistoryDetailPresentation.contextBoostFailureReasonText(failureReason)))
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

private struct DeterministicTraceBlock: View {
    let trace: DeterministicProcessingTrace

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.ColorToken.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(trace.changed
                        ? L10n.localize("home.detail.deterministic.summary_changed", comment: "Deterministic changed summary")
                        : L10n.localize("home.detail.deterministic.summary_unchanged", comment: "Deterministic unchanged summary")
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                    Text(trace.isCodingContext
                        ? L10n.localize("home.detail.deterministic.summary_coding", comment: "Coding context deterministic summary")
                        : L10n.localize("home.detail.deterministic.summary_normal", comment: "Normal context deterministic summary")
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            DeterministicPhaseBlock(
                title: L10n.localize("home.detail.deterministic.pre_llm", comment: "Pre LLM deterministic phase"),
                subtitle: L10n.localize("home.detail.deterministic.pre_llm_subtitle", comment: "Pre LLM deterministic phase subtitle"),
                phase: trace.preLLM
            )
            DeterministicPhaseBlock(
                title: L10n.localize("home.detail.deterministic.post_llm", comment: "Post LLM deterministic phase"),
                subtitle: L10n.localize("home.detail.deterministic.post_llm_subtitle", comment: "Post LLM deterministic phase subtitle"),
                phase: trace.postLLM
            )
        }
    }
}

private struct DeterministicPhaseBlock: View {
    let title: String
    let subtitle: String
    let phase: DeterministicProcessingPhaseTrace
    @State private var selectedProcessorID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                phaseIcon
                    .frame(width: 34, height: 34)
                    .background(statusColor.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
                Text(phaseStatusText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(statusColor.opacity(0.10))
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.localize("home.detail.deterministic.effective_rules", comment: "Effective deterministic rules label"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                if phase.processorIDsForDisplay.isEmpty {
                    Text(L10n.localize("home.detail.deterministic.no_processors_sentence", comment: "No processors sentence"))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(phase.processorIDsForDisplay, id: \.self) { processorID in
                            DeterministicRuleTag(
                                title: Self.processorName(processorID),
                                isHighlighted: phase.highlightedProcessorIDs.contains(processorID),
                                isSelected: selectedProcessorID == processorID
                            ) {
                                selectedProcessorID = selectedProcessorID == processorID ? nil : processorID
                            }
                        }
                    }
                    if let selectedProcessorID {
                        Text(L10n.format("home.detail.deterministic.selected_rule_format", comment: "Selected deterministic rule format",
                            Self.processorName(selectedProcessorID)
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    }
                }
            }

            if let comparisonInput = HomeHistoryDetailPresentation.deterministicComparisonInput(for: phase) {
                // The phase's own input/output is compared here, not the
                // top-level raw/final text. Default mode is .comparison when
                // the phase changed and .processed when unchanged.
                TextComparisonView(input: comparisonInput)
            } else {
                Text(L10n.localize("home.detail.deterministic.text_unavailable", comment: "Old deterministic trace has no text"))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Label(characterChangeText, systemImage: "textformat.size")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                Spacer(minLength: 0)
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

    private var phaseIcon: some View {
        Image(systemName: phase.changed ? "checkmark.seal.fill" : phase.ran ? "checkmark.circle" : "minus.circle")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(statusColor)
    }

    private var phaseStatusText: String {
        guard phase.ran else {
            return L10n.localize("home.detail.deterministic.skipped", comment: "Phase skipped")
        }
        return phase.changed
            ? L10n.localize("home.detail.deterministic.changed", comment: "Phase changed")
            : L10n.localize("home.detail.deterministic.unchanged", comment: "Phase unchanged")
    }

    private var statusColor: Color {
        guard phase.ran else { return AppTheme.ColorToken.secondaryText }
        return phase.changed ? AppTheme.ColorToken.accent : AppTheme.ColorToken.secondaryText
    }

    private var characterChangeText: String {
        if phase.inputCharacterCount == phase.outputCharacterCount {
            return L10n.format("home.detail.deterministic.characters_same_format", comment: "Same character count format",
                phase.outputCharacterCount
            )
        }
        return L10n.format("home.detail.deterministic.characters_changed_format", comment: "Changed character count format",
            phase.inputCharacterCount,
            phase.outputCharacterCount
        )
    }

    private static func processorName(_ id: String) -> String {
        switch id {
        case "filler_word_filtering":
            return L10n.localize("settings.text_processing.filler_filter.title", comment: "Filler filter")
        case "smart_number_recognition":
            return L10n.localize("settings.text_processing.smart_number.title", comment: "Smart number")
        case "punctuation_optimization":
            return L10n.localize("settings.text_processing.punctuation.title", comment: "Punctuation")
        case "cjk_latin_spacing":
            return L10n.localize("settings.text_processing.cjk_latin_spacing.title", comment: "CJK Latin spacing")
        case "long_sentence_breaking":
            return L10n.localize("settings.text_processing.long_sentence.title", comment: "Long sentence")
        case "auto_capitalization":
            return L10n.localize("settings.text_processing.auto_capitalization.title", comment: "Auto capitalization")
        case "style_output_format":
            return L10n.localize("style.output_format.card.title", comment: "Output format")
        default:
            return id
        }
    }
}

private struct DeterministicRuleTag: View {
    let title: String
    let isHighlighted: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isHighlighted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: isSelected ? 1.4 : 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private var foregroundColor: Color {
        isHighlighted ? AppTheme.ColorToken.accent : AppTheme.ColorToken.secondaryText
    }

    private var backgroundColor: Color {
        if isSelected { return AppTheme.ColorToken.selectionBackground }
        return isHighlighted ? AppTheme.ColorToken.accentSoft.opacity(0.58) : AppTheme.ColorToken.controlBackground.opacity(0.72)
    }

    private var borderColor: Color {
        if isSelected { return AppTheme.ColorToken.accent }
        return isHighlighted ? AppTheme.ColorToken.accent.opacity(0.28) : AppTheme.ColorToken.subtleStroke
    }
}

private struct ContextPreviewBlock: View {
    let preview: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(
                    L10n.localize("home.detail.context.screenshot_title", comment: "Context screenshot title"),
                    systemImage: "photo.on.rectangle"
                )
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
                Spacer(minLength: 8)
                Text(L10n.localize("home.detail.context.no_screenshot", comment: "No screenshot attached"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(AppTheme.ColorToken.controlBackground.opacity(0.72))
                    .clipShape(Capsule())
            }

            if let preview, !preview.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.localize("home.detail.context.readable_preview", comment: "Readable context preview"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    Text(preview)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                        .textSelection(.enabled)
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(L10n.localize("home.detail.context.no_readable_preview", comment: "No readable context preview"))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
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
                Label(L10n.localize("home.detail.voice_correction.title", comment: "Text replacement trace title"), systemImage: "wand.and.stars")
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
                DetailMetaItem(title: L10n.localize("home.detail.voice_correction.candidates", comment: "Voice correction candidates"), value: L10n.format("home.detail.items_format", comment: "Items count", trace.candidateEvents.count))
                DetailMetaItem(title: L10n.localize("home.detail.voice_correction.replacements", comment: "Voice correction replacements"), value: L10n.format("home.detail.replacements_format", comment: "Replacements count", trace.appliedEvents.count))
                DetailMetaItem(title: L10n.localize("home.detail.voice_correction.method", comment: "Voice correction method"), value: L10n.localize("home.detail.voice_correction.title", comment: "Text replacement trace title"))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(trace.appliedEvents.isEmpty ? L10n.localize("home.detail.voice_correction.hit_evidence", comment: "Hit evidence") : L10n.localize("home.detail.voice_correction.replacement_details", comment: "Replacement details"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                if displayedEvents.isEmpty {
                    Text(L10n.localize("home.detail.voice_correction.no_hits", comment: "No text replacement hits"))
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
                            Text(L10n.format("home.detail.voice_correction.more_format", comment: "More hidden events", displayedEvents.count - 6))
                                .font(.system(size: 10))
                                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        }
                    }
                }
            }

            if !trace.warnings.isEmpty {
                Text(L10n.format("home.detail.warning_format", comment: "Warning format", trace.warnings.joined(separator: "、")))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let failureReason = trace.failureReason, !failureReason.isEmpty {
                Text(L10n.format("home.detail.reason_format", comment: "Reason format", failureReason))
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
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
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

private struct EditableDetailTextBlock: View {
    let title: String
    let subtitle: String
    @Binding var text: String
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            TextEditor(text: $text)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppTheme.ColorToken.selectionBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            if let error, !error.isEmpty {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .background(AppTheme.ColorToken.accentSoft.opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                .stroke(AppTheme.ColorToken.selectionBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
    }
}

private struct EmptyTraceTabMessage: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.ColorToken.controlBackground.opacity(0.52))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DiagnosticDisclosureRow<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    let content: Content

    init(
        title: String,
        systemImage: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
        }
        .padding(12)
        .background(AppTheme.ColorToken.controlBackground.opacity(0.42))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DiagnosticReadableSummaryView: View {
    let summary: String

    private var sections: [[String]] {
        summary
            .components(separatedBy: "\n\n")
            .map {
                $0.split(separator: "\n", omittingEmptySubsequences: true)
                    .map(String.init)
            }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, lines in
                diagnosticSection(lines)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func diagnosticSection(_ lines: [String]) -> some View {
        let firstLine = lines.first ?? ""
        let hasExplicitTitle = !firstLine.contains(":")
        let title = hasExplicitTitle ? firstLine : nil
        let rowLines = hasExplicitTitle ? Array(lines.dropFirst()) : lines

        return VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(rowLines.enumerated()), id: \.offset) { _, line in
                    diagnosticLine(line)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.ColorToken.panelBackground.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func diagnosticLine(_ line: String) -> some View {
        let parts = splitDiagnosticLine(line)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(parts.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .frame(width: 92, alignment: .leading)
            Text(parts.value)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func splitDiagnosticLine(_ line: String) -> (label: String, value: String) {
        guard let separator = line.firstIndex(of: ":") else {
            return ("", line)
        }
        let label = String(line[..<separator])
        let valueStart = line.index(after: separator)
        return (
            label.trimmingCharacters(in: .whitespacesAndNewlines),
            String(line[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private struct DiagnosticRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}

private struct LLMJSONDisclosure: View {
    let title: String
    let subtitle: String
    let summaryTitle: String
    let summaryText: String
    let jsonText: String
    let expandTitle: String
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                Spacer(minLength: 8)
                if isExpanded {
                    Button {
                        copy(jsonText)
                    } label: {
                        Label(L10n.localize("home.detail.action.copy", comment: "Copy action"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(summaryTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                Text(summaryText)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: isExpanded ? 0 : 58, alignment: .topLeading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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
                    Text(isExpanded ? L10n.localize("home.detail.llm.collapse_json", comment: "Collapse JSON") : expandTitle)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollView {
                    Text(jsonText)
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
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppTheme.ColorToken.controlBackground.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
                Text(L10n.localize("home.detail.meta.not_recorded", comment: "Not recorded"))
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
        .accessibilityLabel(
            L10n.format("home.detail.meta.application_accessibility_format", comment: "Application accessibility label", appName)
        )
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
