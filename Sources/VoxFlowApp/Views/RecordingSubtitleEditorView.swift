import AppKit
import AVFoundation
import SwiftUI

struct RecordingSubtitleEditorSegmentPresentation: Equatable, Identifiable {
    let id: String
    let timeRangeText: String
    let text: String
    let isTextEditable: Bool
    let canDelete: Bool
    let canEditTiming: Bool

    static func make(segment: RecordingSubtitleSegment) -> RecordingSubtitleEditorSegmentPresentation {
        RecordingSubtitleEditorSegmentPresentation(
            id: segment.id,
            timeRangeText: "\(formatTimestamp(segment.startMS)) - \(formatTimestamp(segment.endMS))",
            text: segment.text,
            isTextEditable: true,
            canDelete: true,
            canEditTiming: false
        )
    }

    private static func formatTimestamp(_ ms: Int) -> String {
        let totalSeconds = max(0, ms) / 1_000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let tenths = (max(0, ms) % 1_000) / 100
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}

struct RecordingSubtitleEditorActionPresentation: Equatable, Identifiable {
    enum Kind: Equatable, Hashable {
        case cancel
        case saveDraft
        case burn
    }

    let kind: Kind
    let title: String
    let isPrimary: Bool

    var id: Kind { kind }
}

struct RecordingSubtitleEditorPresentation: Equatable {
    let title: String
    let videoPath: String
    let segmentListTitle: String
    let segmentCountText: String
    let segments: [RecordingSubtitleEditorSegmentPresentation]
    let styleSummary: String
    let footerActions: [RecordingSubtitleEditorActionPresentation]
    let allowsTimelineDragging: Bool
    let allowsMergingSegments: Bool
    let allowsSplittingSegments: Bool
    let allowsStyleEditing: Bool

    static func make(draft: RecordingSubtitleDraft) -> RecordingSubtitleEditorPresentation {
        RecordingSubtitleEditorPresentation(
            title: "添加字幕",
            videoPath: draft.sourceVideoPath,
            segmentListTitle: "字幕草稿",
            segmentCountText: "\(draft.segments.count) 段",
            segments: draft.segments.map(RecordingSubtitleEditorSegmentPresentation.make(segment:)),
            styleSummary: RecordingSubtitleStyle.summary,
            footerActions: [
                RecordingSubtitleEditorActionPresentation(kind: .cancel, title: "取消", isPrimary: false),
                RecordingSubtitleEditorActionPresentation(kind: .saveDraft, title: "保存草稿", isPrimary: false),
                RecordingSubtitleEditorActionPresentation(kind: .burn, title: "烧录字幕", isPrimary: true)
            ],
            allowsTimelineDragging: false,
            allowsMergingSegments: false,
            allowsSplittingSegments: false,
            allowsStyleEditing: false
        )
    }
}

/// 字幕编辑确认界面：左侧视频预览，右侧字幕段列表（可改文字、删除段落）。
///
/// V1 不暴露拖拽时间轴、合并、拆分、改样式控件。用户确认后才可烧录字幕，
/// 烧录前二次确认生成新 mp4 并保留原视频。
struct RecordingSubtitleEditorView: View {
    let recordID: String
    let coordinator: RecordingSubtitleCoordinator
    let onClose: () -> Void

    @State private var draft: RecordingSubtitleDraft?
    @State private var segments: [RecordingSubtitleSegment] = []
    @State private var sourceVideoPath: String?
    @State private var loadFailed = false
    @State private var isBurning = false
    @State private var showBurnConfirm = false
    @State private var burnErrorMessage: String?
    @State private var saveDraftFeedbackMessage: String?

    private var presentation: RecordingSubtitleEditorPresentation? {
        guard var draft else { return nil }
        draft.segments = segments
        return RecordingSubtitleEditorPresentation.make(draft: draft)
    }

    init(recordID: String, coordinator: RecordingSubtitleCoordinator, onClose: @escaping () -> Void) {
        self.recordID = recordID
        self.coordinator = coordinator
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 880, height: 560)
        .background(AppTheme.ColorToken.pageBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 8)
        .onAppear(perform: loadDraft)
        .alert("生成带字幕视频？", isPresented: $showBurnConfirm) {
            Button("取消", role: .cancel) {}
            Button("生成带字幕视频") { confirmBurn() }
        } message: {
            Text("将生成一个新的 mp4，原始录屏会保留。")
        }
        .alert("烧录失败", isPresented: .init(
            get: { burnErrorMessage != nil },
            set: { newValue in if !newValue { burnErrorMessage = nil } }
        )) {
            Button("好") { burnErrorMessage = nil }
        } message: {
            Text(burnErrorMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(presentation?.title ?? "添加字幕")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("关闭")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Content

    private var content: some View {
        HStack(spacing: 0) {
            videoPreview
            Divider()
            segmentList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var videoPreview: some View {
        ZStack {
            AppTheme.ColorToken.controlBackground.opacity(0.3)
            if let path = presentation?.videoPath ?? sourceVideoPath {
                MediaVideoPlayerView(url: URL(fileURLWithPath: path))
            } else {
                Image(systemName: "video.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText.opacity(0.4))
            }
        }
    }

    private var segmentList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(presentation?.segmentListTitle ?? "字幕草稿")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                Spacer()
                Text(presentation?.segmentCountText ?? "\(segments.count) 段")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if loadFailed {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    Text("字幕草稿加载失败")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if segments.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "captions.bubble")
                        .font(.system(size: 28))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText.opacity(0.5))
                    Text("暂无字幕段")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach($segments) { $segment in
                            segmentRow(segment: $segment)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 340)
    }

    private func segmentRow(segment: Binding<RecordingSubtitleSegment>) -> some View {
        let row = RecordingSubtitleEditorSegmentPresentation.make(segment: segment.wrappedValue)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.timeRangeText)
                    .font(.system(size: 11, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                Spacer()
                Button(action: { deleteSegment(id: segment.wrappedValue.id) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("删除该段字幕")
            }
            TextEditor(text: segment.text)
                .font(.system(size: 13))
                .frame(height: 44)
                .padding(4)
                .background(AppTheme.ColorToken.controlBackground.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .scrollContentBackground(.hidden)
        }
        .padding(8)
        .background(AppTheme.ColorToken.controlBackground.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Text("字幕样式：\(presentation?.styleSummary ?? RecordingSubtitleStyle.summary)")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            Spacer()
            if let saveDraftFeedbackMessage {
                Text(saveDraftFeedbackMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            ForEach(presentation?.footerActions ?? RecordingSubtitleEditorPresentation.make(draft: emptyDraft).footerActions) { action in
                footerActionButton(action)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyDraft: RecordingSubtitleDraft {
        RecordingSubtitleDraft(
            mediaRecordID: recordID,
            sourceVideoPath: sourceVideoPath ?? "",
            segments: [],
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    @ViewBuilder
    private func footerActionButton(_ action: RecordingSubtitleEditorActionPresentation) -> some View {
        if action.isPrimary {
            Button(action.title) {
                performFooterAction(action.kind)
            }
            .buttonStyle(.borderedProminent)
            .disabled(action.kind == .burn && (segments.isEmpty || isBurning))
        } else {
            Button(action.title) {
                performFooterAction(action.kind)
            }
            .buttonStyle(.bordered)
            .disabled(action.kind == .burn && (segments.isEmpty || isBurning))
        }
    }

    private func performFooterAction(_ kind: RecordingSubtitleEditorActionPresentation.Kind) {
        switch kind {
        case .cancel:
            onClose()
        case .saveDraft:
            saveDraft()
        case .burn:
            showBurnConfirm = true
        }
    }

    // MARK: - Actions

    private func loadDraft() {
        do {
            let loaded = try coordinator.loadDraft(recordID: recordID)
            guard let loaded else {
                loadFailed = true
                return
            }
            draft = loaded
            segments = loaded.segments
            sourceVideoPath = loaded.sourceVideoPath
        } catch {
            loadFailed = true
        }
    }

    @discardableResult
    private func saveDraft(showFeedback: Bool = true) -> Bool {
        guard var draft else { return false }
        draft.segments = segments
        draft.updatedAt = Date()
        do {
            try coordinator.saveDraft(draft)
            self.draft = draft
            if showFeedback {
                saveDraftFeedbackMessage = "草稿已保存"
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    saveDraftFeedbackMessage = nil
                }
            }
            return true
        } catch {
            saveDraftFeedbackMessage = "保存失败"
            return false
        }
    }

    private func deleteSegment(id: String) {
        segments.removeAll { $0.id == id }
    }

    private func confirmBurn() {
        guard saveDraft(showFeedback: false) else { return }
        isBurning = true
        coordinator.startBurn(recordID: recordID)
        onClose()
    }
}
