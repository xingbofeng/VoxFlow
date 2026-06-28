import Foundation

/// 录屏字幕状态机。
///
/// 覆盖 `none / generating / draftReady / burning / burned / failed`，
/// 详见 `docs/assets/recording-subtitles-v1-interaction-design.md`。
enum RecordingSubtitleStatus: String, CaseIterable, Codable, Equatable, Sendable {
    /// 未添加字幕。
    case none
    /// 字幕草稿生成中。
    case generating
    /// 字幕草稿已就绪，等待用户编辑确认。
    case draftReady
    /// 字幕烧录导出中。
    case burning
    /// 字幕已烧录为带字幕新视频。
    case burned
    /// 生成或烧录失败。
    case failed

    /// 详情页/HUD 展示用的中文文案。
    var displayTitle: String {
        switch self {
        case .none: return L10n.localize("subtitle.status.none", comment: "")
        case .generating: return L10n.localize("subtitle.status.generating", comment: "")
        case .draftReady: return L10n.localize("subtitle.status.draft_ready", comment: "")
        case .burning: return L10n.localize("subtitle.status.burning", comment: "")
        case .burned: return L10n.localize("subtitle.status.burned", comment: "")
        case .failed: return L10n.localize("subtitle.status.failed", comment: "")
        }
    }
}

/// 字幕段：带时间范围的文本，时间单位为毫秒。
struct RecordingSubtitleSegment: Codable, Equatable, Sendable, Identifiable {
    let id: String
    var startMS: Int
    var endMS: Int
    var text: String

    init(id: String = UUID().uuidString, startMS: Int, endMS: Int, text: String) {
        self.id = id
        self.startMS = startMS
        self.endMS = endMS
        self.text = text
    }
}

/// 字幕草稿：识别结果 + 编辑后的可烧录数据。
struct RecordingSubtitleDraft: Codable, Equatable, Sendable {
    let mediaRecordID: String
    let sourceVideoPath: String
    var segments: [RecordingSubtitleSegment]
    let createdAt: Date
    var updatedAt: Date

    init(
        mediaRecordID: String,
        sourceVideoPath: String,
        segments: [RecordingSubtitleSegment] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.mediaRecordID = mediaRecordID
        self.sourceVideoPath = sourceVideoPath
        self.segments = segments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 字幕持久化状态：写入 `MediaRecord` 的字幕字段集合。
struct RecordingSubtitleState: Equatable, Sendable {
    var status: RecordingSubtitleStatus
    var draftPath: String?
    var srtPath: String?
    var subtitledVideoPath: String?
    var errorMessage: String?
    var updatedAt: Date?

    static let none = RecordingSubtitleState(
        status: .none,
        draftPath: nil,
        srtPath: nil,
        subtitledVideoPath: nil,
        errorMessage: nil,
        updatedAt: nil
    )
}

/// V1 固定字幕样式摘要，用于编辑确认界面展示。
enum RecordingSubtitleStyle {
    /// 底部居中，距底部约 8% 视频高度。
    static let bottomRatio: Double = 0.08
    /// 左右安全区占比。
    static let horizontalSafeMarginRatio: Double = 0.08
    /// 最多行数。
    static let maxLines = 2

    /// 编辑界面底部展示的样式摘要文案。
    static let summary = L10n.localize("subtitle.style.summary", comment: "")
}
