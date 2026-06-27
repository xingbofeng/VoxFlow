import Foundation

/// 字幕草稿 JSON 读写：原子写入、覆盖更新、删除清理。
///
/// 草稿路径由 `ApplicationSupportPaths.recordingSubtitleDraftURL(forID:)` 提供，
/// 独立于原录屏文件，删除时不影响原视频。
final class RecordingSubtitleDraftStore {
    private let paths: ApplicationSupportPaths
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        paths: ApplicationSupportPaths,
        fileManager: FileManager = .default,
        dateEncodingStrategy: JSONEncoder.DateEncodingStrategy = .iso8601,
        dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .iso8601
    ) {
        self.paths = paths
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = dateEncodingStrategy
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dateDecodingStrategy
        self.decoder = decoder
    }

    /// 草稿文件 URL。
    func draftURL(for mediaID: String) -> URL {
        paths.recordingSubtitleDraftURL(forID: mediaID)
    }

    /// 原子写入草稿；已存在则覆盖。
    func save(_ draft: RecordingSubtitleDraft) throws {
        let url = draftURL(for: draft.mediaRecordID)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(draft)
        try atomicWrite(data: data, to: url)
    }

    /// 读取草稿；文件不存在返回 nil。
    func load(mediaID: String) throws -> RecordingSubtitleDraft? {
        let url = draftURL(for: mediaID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(RecordingSubtitleDraft.self, from: data)
    }

    /// 删除草稿；文件不存在时静默成功。
    func remove(mediaID: String) throws {
        let url = draftURL(for: mediaID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    /// 写入临时文件后原子替换，避免半成品污染。
    private func atomicWrite(data: Data, to url: URL) throws {
        let temporaryURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            try data.write(to: temporaryURL, options: [.atomic])
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try fileManager.moveItem(at: temporaryURL, to: url)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}

/// 字幕 SRT 导出器：把草稿 segments 导出为 `HH:MM:SS,mmm` 时间轴的 SRT 文本。
enum RecordingSubtitleSRTExporter {
    /// 生成 SRT 文本；空草稿返回空字符串。
    static func srt(for draft: RecordingSubtitleDraft) -> String {
        guard !draft.segments.isEmpty else { return "" }
        var blocks: [String] = []
        for (index, segment) in draft.segments.enumerated() {
            let start = format(timestampMS: segment.startMS)
            let end = format(timestampMS: segment.endMS)
            let block = """
            \(index + 1)
            \(start) --> \(end)
            \(segment.text)
            """
            blocks.append(block)
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    /// 把 SRT 写入指定 URL。
    static func export(draft: RecordingSubtitleDraft, to url: URL) throws {
        let content = srt(for: draft)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.data(using: .utf8)?.write(to: url, options: [.atomic])
    }

    /// `毫秒 -> HH:MM:SS,mmm`。
    static func format(timestampMS ms: Int) -> String {
        let clamped = max(0, ms)
        let totalSeconds = clamped / 1_000
        let millis = clamped % 1_000
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }
}
