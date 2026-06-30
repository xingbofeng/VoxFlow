import AppKit
import SwiftUI

struct ScreenshotRecordView: View {
    @ObservedObject var viewModel: ScreenshotRecordViewModel
    @State private var selectedRecord: MediaRecord?

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = L10n.localize("screenshot.record.format.datetime", comment: "")
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
                    .onExitCommand {
                        self.selectedRecord = nil
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
            Label(L10n.localize("screenshot.record.header_title", comment: ""), systemImage: "rectangle.stack.fill")
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
                title: L10n.localize("screenshot.record.stats.total_media", comment: ""),
                value: "\(viewModel.mediaStats?.totalMedia ?? 0)",
                unit: L10n.localize("screenshot.record.stats.unit_items", comment: ""),
                systemImage: "rectangle.stack.fill"
            )
            ScreenshotStatCard(
                title: L10n.localize("screenshot.record.stats.today_media", comment: ""),
                value: "\(viewModel.mediaStats?.todayMedia ?? 0)",
                unit: L10n.localize("screenshot.record.stats.unit_items", comment: ""),
                systemImage: "calendar"
            )
            ScreenshotStatCard(
                title: L10n.localize("screenshot.record.stats.screenshot", comment: ""),
                value: "\(viewModel.mediaStats?.screenshotCount ?? 0)",
                unit: L10n.localize("screenshot.record.stats.unit_screenshots", comment: ""),
                systemImage: "photo.on.rectangle.angled"
            )
            ScreenshotStatCard(
                title: L10n.localize("screenshot.record.stats.screen_recording", comment: ""),
                value: "\(viewModel.mediaStats?.recordingCount ?? 0)",
                unit: L10n.localize("screenshot.record.stats.unit_recordings", comment: ""),
                systemImage: "record.circle"
            )
        }
    }

    // MARK: - Pagination Bar (antd style, top)

    private var paginationBar: some View {
        HStack(spacing: 8) {
            Picker(
                L10n.localize("screenshot.record.filter_label", comment: ""),
                selection: Binding(
                    get: { viewModel.selectedFilter },
                    set: { viewModel.selectedFilter = $0 }
                )
            ) {
                ForEach(MediaRecordFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            TextField(
                L10n.localize("screenshot.record.search_placeholder", comment: ""),
                text: Binding(
                    get: { viewModel.searchText },
                    set: { viewModel.updateSearch($0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 240)

            Text(
                L10n.format("screenshot.record.total_count_format", comment: "",
                    viewModel.totalRecords
                )
            )
            .foregroundStyle(AppTheme.ColorToken.secondaryText)

            Picker(
                L10n.localize("screenshot.record.page_size_label", comment: ""),
                selection: Binding(
                    get: { viewModel.pageSize },
                    set: { viewModel.updatePageSize($0) }
                )
            ) {
                ForEach([20, 50, 100], id: \.self) { size in
                    Text(
                        L10n.format("screenshot.record.page_size_format", comment: "",
                            size
                        )
                    )
                    .tag(size)
                }
            }
            .labelsHidden()
            .frame(width: 110)

            Spacer()

            Button(L10n.localize("screenshot.record.page_prev", comment: ""), action: viewModel.previousPage)
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
            Button(L10n.localize("screenshot.record.page_next", comment: ""), action: viewModel.nextPage)
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
                    Text(L10n.localize("screenshot.record.empty_title", comment: ""))
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    Text(L10n.localize("screenshot.record.empty_hint", comment: ""))
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
                Text(L10n.localize("screenshot.record.no_text", comment: ""))
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
                    Text(
                        L10n.format("screenshot.record.char_count_format", comment: "",
                            record.charCount
                        )
                    )
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
        return L10n.localize("screenshot.record.no_text", comment: "")
    }

    private var actionIcons: some View {
        HStack(spacing: 0) {
            if record.mediaType == .screenRecording {
                actionIcon(
                    "arrow.up.right.square",
                    help: L10n.localize("screenshot.record.action.open_file_help", comment: "")
                ) {
                    viewModel.openFile(id: record.id)
                }
                actionIcon(
                    "doc.on.doc",
                    help: L10n.localize("screenshot.record.action.copy_file_help", comment: "")
                ) {
                    viewModel.copyFile(id: record.id)
                }
                actionIcon(
                    "folder",
                    help: L10n.localize("screenshot.record.action.reveal_in_finder_help", comment: "")
                ) {
                    viewModel.revealInFinder(id: record.id)
                }
            } else {
                actionIcon(
                    "photo.on.rectangle",
                    help: L10n.localize("screenshot.record.action.copy_image_help", comment: "")
                ) {
                    viewModel.copyImage(id: record.id)
                }
                if !record.ocrText.isEmpty {
                    actionIcon(
                        "doc.on.doc",
                        help: L10n.localize("screenshot.record.action.copy_text_help", comment: "")
                    ) {
                        viewModel.copyText(id: record.id)
                    }
                }
            }
            actionIcon(
                record.isFavorited ? "star.fill" : "star",
                help: record.isFavorited
                    ? L10n.localize("screenshot.record.action.unfavorite_help", comment: "")
                    : L10n.localize("screenshot.record.action.favorite_help", comment: ""),
                tint: record.isFavorited ? .yellow : nil
            ) {
                viewModel.toggleFavorite(id: record.id)
            }
            actionIcon("trash", help: L10n.localize("screenshot.record.action.delete_help", comment: "")) {
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
        guard width > 0, height > 0 else {
            return L10n.localize("screenshot.record.format.unknown_resolution", comment: "")
        }
        return "\(width)×\(height)"
    }

    private func formatFileSize(_ bytes: Int) -> String {
        guard bytes > 0 else {
            return L10n.localize("screenshot.record.format.unknown_file_size", comment: "")
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func audioModeTitle(_ audioMode: MediaAudioMode) -> String {
        switch audioMode {
        case .none:
            return L10n.localize("screenshot.record.audio.no_sound", comment: "")
        case .microphone:
            return L10n.localize("screenshot.record.audio.microphone", comment: "")
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
