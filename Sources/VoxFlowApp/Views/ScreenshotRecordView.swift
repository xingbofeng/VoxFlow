import AppKit
import SwiftUI

struct ScreenshotRecordView: View {
    @ObservedObject var viewModel: ScreenshotRecordViewModel
    @State private var selectedRecord: MediaRecord?

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    /// antd 表格风格分页槽位：nil 表示省略号。
    private var visiblePageSlots: [Int?] {
        let total = viewModel.totalPages
        let current = viewModel.currentPage
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                pageHeader
                statsGrid
                paginationBar
                recordsGrid
            }
            .padding(AppTheme.Spacing.page)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.ColorToken.pageBackground)
        .tint(AppTheme.ColorToken.accent)
        .actionFeedbackOverlay(
            message: viewModel.lastActionMessage,
            error: viewModel.lastError,
            onDismiss: viewModel.clearFeedback
        )
        .overlay {
            if let selectedRecord {
                // 透明遮罩层，点击关闭 modal
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        self.selectedRecord = nil
                    }
                    .transition(.opacity)
                    .overlay {
                        ScreenshotRecordDetailView(initialRecord: selectedRecord, viewModel: viewModel) {
                            self.selectedRecord = nil
                        }
                    }
            }
        }
        .onAppear {
            viewModel.loadIfNeeded()
        }
    }

    // MARK: - Header

    private var pageHeader: some View {
        HStack {
            Label("多媒体", systemImage: "rectangle.stack.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
            Spacer()
        }
    }

    // MARK: - Statistics Cards

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180), spacing: AppTheme.Spacing.grid)],
            spacing: AppTheme.Spacing.grid
        ) {
            ScreenshotStatCard(
                title: "全部媒体",
                value: "\(viewModel.mediaStats?.totalMedia ?? 0)",
                unit: "项",
                systemImage: "rectangle.stack.fill"
            )
            ScreenshotStatCard(
                title: "今日媒体",
                value: "\(viewModel.mediaStats?.todayMedia ?? 0)",
                unit: "项",
                systemImage: "calendar"
            )
            ScreenshotStatCard(
                title: "截图",
                value: "\(viewModel.mediaStats?.screenshotCount ?? 0)",
                unit: "张",
                systemImage: "photo.on.rectangle.angled"
            )
            ScreenshotStatCard(
                title: "录屏",
                value: "\(viewModel.mediaStats?.recordingCount ?? 0)",
                unit: "段",
                systemImage: "record.circle"
            )
        }
    }

    // MARK: - Pagination Bar (antd style, top)

    private var paginationBar: some View {
        HStack(spacing: 8) {
            Picker("类型", selection: Binding(
                get: { viewModel.selectedFilter },
                set: { viewModel.selectedFilter = $0 }
            )) {
                ForEach(MediaRecordFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            TextField(
                "搜索媒体或识别文本…",
                text: Binding(
                    get: { viewModel.searchText },
                    set: { viewModel.updateSearch($0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)

            Text("共 \(viewModel.totalRecords) 条")
                .foregroundStyle(AppTheme.ColorToken.secondaryText)

            Picker("每页", selection: Binding(
                get: { viewModel.pageSize },
                set: { viewModel.updatePageSize($0) }
            )) {
                ForEach([20, 50, 100], id: \.self) { size in
                    Text("\(size) 条/页").tag(size)
                }
            }
            .labelsHidden()
            .frame(width: 110)

            Spacer()

            Button("上一页", action: viewModel.previousPage)
                .disabled(!viewModel.canGoToPreviousPage)
            ForEach(visiblePageSlots, id: \.self) { slot in
                if let page = slot {
                    Button("\(page)") { viewModel.goToPage(page) }
                        .buttonStyle(.bordered)
                        .background(
                            page == viewModel.currentPage
                                ? AppTheme.ColorToken.accentSoft
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Text("…")
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .frame(width: 24)
                }
            }
            Button("下一页", action: viewModel.nextPage)
                .disabled(!viewModel.canGoToNextPage)
        }
        .font(.system(size: 12, weight: .medium))
    }

    // MARK: - Records Grid

    private var recordsGrid: some View {
        Group {
            if viewModel.records.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText.opacity(0.4))
                    Text("暂无多媒体记录")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    Text("使用 ⌘⇧A 截图或录屏后，记录将自动保存到这里")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText.opacity(0.7))
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .appPanel()
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: AppTheme.Spacing.grid),
                              GridItem(.flexible(), spacing: AppTheme.Spacing.grid),
                              GridItem(.flexible(), spacing: AppTheme.Spacing.grid)],
                    spacing: AppTheme.Spacing.grid
                ) {
                    ForEach(viewModel.records) { record in
                        ScreenshotRecordCard(record: record, viewModel: viewModel) {
                            selectedRecord = record
                        }
                    }
                }
            }
        }
    }

    private func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Stat Card

private struct ScreenshotStatCard: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ColorToken.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(unit)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
        }
        .padding(AppTheme.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appPanel()
    }
}

// MARK: - Record Card

private struct ScreenshotRecordCard: View {
    let record: MediaRecord
    @ObservedObject var viewModel: ScreenshotRecordViewModel
    let onTap: () -> Void
    private let thumbnailHeight: CGFloat = 150
    private let contentHeight: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailPreview
            cardContent
        }
        .frame(height: thumbnailHeight + contentHeight)
        .appPanel(cornerRadius: AppTheme.Radius.card)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    // MARK: - Thumbnail

    private var thumbnailPreview: some View {
        Group {
            if record.mediaType == .screenRecording {
                recordingThumbnail
            } else if let image = viewModel.loadImage(for: record) {
                ZStack {
                    AppTheme.ColorToken.controlBackground.opacity(0.34)
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                }
                .frame(maxWidth: .infinity)
                .frame(height: thumbnailHeight)
                .clipped()
            } else {
                placeholderThumbnail
            }
        }
    }

    private var recordingThumbnail: some View {
        ZStack {
            AppTheme.ColorToken.controlBackground.opacity(0.5)
            if let thumbnail = viewModel.loadVideoThumbnail(for: record) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(AppTheme.ColorToken.accent)
                    Text(formatDuration(record.durationMs))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                }
            }

            VStack {
                Spacer()
                HStack {
                    Label(formatDuration(record.durationMs), systemImage: "video.fill")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.58))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    Spacer()
                }
                .padding(10)
            }
        }
        .frame(height: thumbnailHeight)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var placeholderThumbnail: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.ColorToken.secondaryText.opacity(0.3))
            if record.ocrText.isEmpty {
                Text("未识别到文字")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText.opacity(0.5))
            }
        }
        .frame(height: thumbnailHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .background(AppTheme.ColorToken.controlBackground.opacity(0.5))
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ScreenshotRecordView.dateFormatter.string(from: record.createdAt))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                Spacer()
            }

            Text(primaryText)
                .font(.system(size: 13))
                .foregroundStyle(record.ocrText.isEmpty ? AppTheme.ColorToken.secondaryText : AppTheme.ColorToken.primaryText)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(height: 34, alignment: .topLeading)

            HStack(spacing: 4) {
                if record.mediaType == .screenRecording {
                    Text(formatResolution(record.width, record.height))
                    Text("·")
                    Text(formatFileSize(record.fileSizeBytes))
                    Text("·")
                    Text(audioModeTitle(record.audioMode))
                } else {
                    Text("\(record.charCount) 字")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(AppTheme.ColorToken.secondaryText)

            actionIcons
        }
        .padding(14)
        .frame(height: contentHeight, alignment: .top)
    }

    private var primaryText: String {
        if !record.ocrText.isEmpty {
            return record.ocrText
        }
        if record.mediaType == .screenRecording {
            return formatDuration(record.durationMs)
        }
        return "未识别到文字"
    }

    private var actionIcons: some View {
        HStack(spacing: 0) {
            if record.mediaType == .screenRecording {
                actionIcon("arrow.up.right.square", help: "打开文件") {
                    viewModel.openFile(id: record.id)
                }
                actionIcon("doc.on.doc", help: "复制文件") {
                    viewModel.copyFile(id: record.id)
                }
                actionIcon("folder", help: "在 Finder 中显示") {
                    viewModel.revealInFinder(id: record.id)
                }
            } else {
                actionIcon("photo.on.rectangle", help: "复制图片") {
                    viewModel.copyImage(id: record.id)
                }
                if !record.ocrText.isEmpty {
                    actionIcon("doc.on.doc", help: "复制文字") {
                        viewModel.copyText(id: record.id)
                    }
                }
            }
            actionIcon(record.isFavorited ? "star.fill" : "star", help: "收藏", tint: record.isFavorited ? .yellow : nil) {
                viewModel.toggleFavorite(id: record.id)
            }
            actionIcon("trash", help: "删除") {
                viewModel.deleteRecord(id: record.id)
            }
            Spacer(minLength: 0)
        }
    }

    private func formatDuration(_ durationMs: Int) -> String {
        let totalSeconds = max(0, durationMs / 1_000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatResolution(_ width: Int, _ height: Int) -> String {
        guard width > 0, height > 0 else { return "未知分辨率" }
        return "\(width)×\(height)"
    }

    private func formatFileSize(_ bytes: Int) -> String {
        guard bytes > 0 else { return "未知大小" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func audioModeTitle(_ audioMode: MediaAudioMode) -> String {
        switch audioMode {
        case .none:
            return "无声"
        case .microphone:
            return "麦克风"
        }
    }

    private func actionIcon(_ systemName: String, help: String, tint: Color? = nil, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .foregroundStyle(tint ?? AppTheme.ColorToken.secondaryText)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
