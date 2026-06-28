import Foundation

/// 多媒体记录类型。旧截图行默认为 `.screenshot`，区域录屏保存为 `.screenRecording`。
enum MediaType: String, CaseIterable, Equatable, Sendable {
    case screenshot
    case screenRecording
}

/// 录屏音频模式。默认 `.none`（无声），可选 `.microphone`。
enum MediaAudioMode: String, CaseIterable, Equatable, Sendable {
    case none
    case microphone
}

/// 统一的多媒体记录模型，覆盖旧截图记录与新区域录屏记录。
///
/// 底层仍存储在 `screenshot_records` 表中（通过媒体列扩展），
/// 旧 `ScreenshotRecord` 作为兼容过渡类型保留。新代码应优先使用 `MediaRecord`。
struct MediaRecord: Equatable, Identifiable {
    let id: String
    let mediaType: MediaType
    let ocrText: String
    let translatedText: String?
    let summaryText: String?
    /// 截图图像路径；录屏记录此处留空。
    let imagePath: String?
    /// 录屏 `.mp4` 文件路径；截图记录此处留空。
    let videoPath: String?
    /// 录屏缩略图路径（可选）。
    let thumbnailPath: String?
    /// 录屏时长（毫秒）；截图为 0。
    let durationMs: Int
    /// 媒体宽度（像素）；截图可为 0。
    let width: Int
    /// 媒体高度（像素）；截图可为 0。
    let height: Int
    /// 文件大小（字节）；截图可为 0。
    let fileSizeBytes: Int
    /// 音频模式；截图为 `.none`。
    let audioMode: MediaAudioMode
    let charCount: Int
    var isFavorited: Bool
    /// 字幕状态；截图与无声录屏为 `.none`。
    let subtitleStatus: RecordingSubtitleStatus
    /// 字幕草稿 JSON 路径。
    let subtitleDraftPath: String?
    /// 导出的 SRT 路径。
    let subtitleSrtPath: String?
    /// 带字幕视频路径；未烧录为 nil。
    let subtitledVideoPath: String?
    /// 最近一次字幕失败原因。
    let subtitleErrorMessage: String?
    /// 字幕状态最近更新时间。
    let subtitleUpdatedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(
        id: String,
        mediaType: MediaType,
        ocrText: String = "",
        translatedText: String? = nil,
        summaryText: String? = nil,
        imagePath: String? = nil,
        videoPath: String? = nil,
        thumbnailPath: String? = nil,
        durationMs: Int = 0,
        width: Int = 0,
        height: Int = 0,
        fileSizeBytes: Int = 0,
        audioMode: MediaAudioMode = .none,
        charCount: Int = 0,
        isFavorited: Bool = false,
        subtitleStatus: RecordingSubtitleStatus = .none,
        subtitleDraftPath: String? = nil,
        subtitleSrtPath: String? = nil,
        subtitledVideoPath: String? = nil,
        subtitleErrorMessage: String? = nil,
        subtitleUpdatedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.mediaType = mediaType
        self.ocrText = ocrText
        self.translatedText = translatedText
        self.summaryText = summaryText
        self.imagePath = imagePath
        self.videoPath = videoPath
        self.thumbnailPath = thumbnailPath
        self.durationMs = durationMs
        self.width = width
        self.height = height
        self.fileSizeBytes = fileSizeBytes
        self.audioMode = audioMode
        self.charCount = charCount
        self.isFavorited = isFavorited
        self.subtitleStatus = subtitleStatus
        self.subtitleDraftPath = subtitleDraftPath
        self.subtitleSrtPath = subtitleSrtPath
        self.subtitledVideoPath = subtitledVideoPath
        self.subtitleErrorMessage = subtitleErrorMessage
        self.subtitleUpdatedAt = subtitleUpdatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// 从旧截图记录转换，保留所有截图字段。
    init(fromScreenshot record: ScreenshotRecord) {
        self.init(
            id: record.id,
            mediaType: .screenshot,
            ocrText: record.ocrText,
            translatedText: record.translatedText,
            summaryText: record.summaryText,
            imagePath: record.imagePath,
            videoPath: nil,
            thumbnailPath: nil,
            durationMs: 0,
            width: 0,
            height: 0,
            fileSizeBytes: 0,
            audioMode: .none,
            charCount: record.charCount,
            isFavorited: record.isFavorited,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            deletedAt: record.deletedAt
        )
    }

    /// 返回替换字幕状态后的新记录，便于 UI/测试基于现有记录刷新字幕字段。
    func withSubtitleState(_ state: RecordingSubtitleState) -> MediaRecord {
        MediaRecord(
            id: id,
            mediaType: mediaType,
            ocrText: ocrText,
            translatedText: translatedText,
            summaryText: summaryText,
            imagePath: imagePath,
            videoPath: videoPath,
            thumbnailPath: thumbnailPath,
            durationMs: durationMs,
            width: width,
            height: height,
            fileSizeBytes: fileSizeBytes,
            audioMode: audioMode,
            charCount: charCount,
            isFavorited: isFavorited,
            subtitleStatus: state.status,
            subtitleDraftPath: state.draftPath,
            subtitleSrtPath: state.srtPath,
            subtitledVideoPath: state.subtitledVideoPath,
            subtitleErrorMessage: state.errorMessage,
            subtitleUpdatedAt: state.updatedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }

    /// UI 主播放路径：字幕烧录完成后优先展示带字幕视频，原视频仍通过显式入口保留。
    var primaryVideoPath: String? {
        if mediaType == .screenRecording,
           subtitleStatus == .burned,
           let subtitledVideoPath {
            return subtitledVideoPath
        }
        return videoPath
    }

    /// UI 主文件路径：截图使用图片；录屏烧录完成后优先使用带字幕视频。
    var primaryFilePath: String? {
        primaryVideoPath ?? imagePath
    }
}

/// 多媒体历史筛选维度。
enum MediaRecordFilter: String, CaseIterable, Identifiable, Equatable, Sendable {
    case all
    case screenshots
    case recordings
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L10n.localize("asset.media_filter.all", comment: "")
        case .screenshots: return L10n.localize("asset.media_filter.screenshots", comment: "")
        case .recordings: return L10n.localize("asset.media_filter.recordings", comment: "")
        case .favorites: return L10n.localize("asset.media_filter.favorites", comment: "")
        }
    }
}

/// 多媒体历史统计卡片数据。
struct MediaRecordStats: Equatable {
    let totalMedia: Int
    let todayMedia: Int
    let screenshotCount: Int
    let recordingCount: Int
}

/// 多媒体分页结果。
struct MediaRecordPage: Equatable {
    let records: [MediaRecord]
    let totalCount: Int
}

/// 多媒体记录仓储 facade。底层复用 `screenshot_records` 表，对外暴露媒体类型感知的查询。
protocol MediaRecordRepository {
    func save(_ record: MediaRecord) throws
    func record(id: String) throws -> MediaRecord?
    func page(limit: Int, offset: Int, filter: MediaRecordFilter, search: String?) throws -> MediaRecordPage
    func toggleFavorite(id: String, isFavorited: Bool, updatedAt: Date) throws
    func updateSubtitleState(id: String, state: RecordingSubtitleState, updatedAt: Date) throws
    func softDelete(id: String, deletedAt: Date) throws
    func stats() throws -> MediaRecordStats
}
