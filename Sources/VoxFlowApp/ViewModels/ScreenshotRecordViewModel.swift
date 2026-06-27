import AppKit
import AVFoundation
import Combine
import Foundation

@MainActor
final class ScreenshotRecordViewModel: ObservableObject {
    @Published var records: [MediaRecord] = []
    @Published var searchText: String = ""
    @Published var selectedFilter: MediaRecordFilter = .all {
        didSet {
            guard oldValue != selectedFilter else { return }
            onlyFavorites = selectedFilter == .favorites
            currentPage = 1
            load()
        }
    }
    @Published var onlyFavorites: Bool = false {
        didSet {
            if oldValue != onlyFavorites {
                selectedFilter = onlyFavorites ? .favorites : .all
            }
        }
    }
    @Published var stats: ScreenshotRecordStats?
    @Published var mediaStats: MediaRecordStats?
    @Published var lastError: String?
    @Published var lastActionMessage: String?
    @Published private(set) var currentPage = 1
    @Published private(set) var pageSize: Int = 20
    @Published private(set) var totalRecords = 0

    private let environment: any AppServiceProviding
    private let clipboardService: SystemClipboardService
    private let imageCache = NSCache<NSString, NSImage>()
    private let videoThumbnailCache = NSCache<NSString, NSImage>()
    private var pendingVideoThumbnailIDs: Set<String> = []
    private var videoThumbnailGenerators: [String: AVAssetImageGenerator] = [:]
    private var hasLoaded = false

    init(environment: any AppServiceProviding, clipboardService: SystemClipboardService) {
        self.environment = environment
        self.clipboardService = clipboardService
        imageCache.countLimit = 60
        imageCache.totalCostLimit = 120 * 1024 * 1024
        videoThumbnailCache.countLimit = 60
        videoThumbnailCache.totalCostLimit = 80 * 1024 * 1024
    }

    var totalPages: Int { max(1, Int(ceil(Double(totalRecords) / Double(pageSize)))) }
    var canGoToPreviousPage: Bool { currentPage > 1 }
    var canGoToNextPage: Bool { currentPage < totalPages }

    func load() {
        do {
            let page = try environment.mediaRecordRepository.page(
                limit: pageSize,
                offset: (currentPage - 1) * pageSize,
                filter: selectedFilter,
                search: searchText.isEmpty ? nil : searchText
            )
            records = page.records
            totalRecords = page.totalCount
            stats = try environment.screenshotRecordRepository.stats()
            mediaStats = try environment.mediaRecordRepository.stats()
            hasLoaded = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        load()
    }

    func refreshAfterExternalInsert() {
        searchText = ""
        selectedFilter = .all
        onlyFavorites = false
        currentPage = 1
        load()
    }

    func updateSearch(_ text: String) {
        searchText = text
        currentPage = 1
        load()
    }

    func goToPage(_ page: Int) {
        let target = min(max(1, page), totalPages)
        guard target != currentPage else { return }
        currentPage = target
        load()
    }

    func previousPage() {
        goToPage(currentPage - 1)
    }

    func nextPage() {
        goToPage(currentPage + 1)
    }

    func updatePageSize(_ size: Int) {
        guard size != pageSize else { return }
        pageSize = size
        currentPage = 1
        load()
    }

    func toggleFavorite(id: String) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        let newValue = !record.isFavorited
        do {
            try environment.mediaRecordRepository.toggleFavorite(
                id: id,
                isFavorited: newValue,
                updatedAt: environment.clock.now
            )
            load()
            lastActionMessage = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteRecord(id: String) {
        do {
            let media = try environment.mediaRecordRepository.record(id: id)
            try environment.mediaRecordRepository.softDelete(
                id: id,
                deletedAt: environment.clock.now
            )
            // 取消进行中的字幕任务，避免删除后仍写入文件。
            environment.subtitleCoordinator?.cancelInFlightTasks(recordID: id)
            imageCache.removeObject(forKey: id as NSString)
            videoThumbnailCache.removeObject(forKey: id as NSString)
            pendingVideoThumbnailIDs.remove(id)
            videoThumbnailGenerators[id]?.cancelAllCGImageGeneration()
            videoThumbnailGenerators[id] = nil
            if let imagePath = media?.imagePath {
                try ScreenshotImageStorage.deleteImage(at: imagePath)
            }
            if let videoPath = media?.videoPath {
                try? FileManager.default.removeItem(atPath: videoPath)
            }
            // 删除录屏时同步清理字幕草稿、SRT、带字幕视频；缺失文件不导致失败。
            removeSubtitleArtifacts(for: media)
            load()
            lastActionMessage = "已删除"
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 删除字幕相关文件；任意文件缺失都静默忽略。
    private func removeSubtitleArtifacts(for media: MediaRecord?) {
        guard let media else { return }
        let paths = [media.subtitleDraftPath, media.subtitleSrtPath, media.subtitledVideoPath].compactMap { $0 }
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    func copyText(id: String) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        let textToCopy = record.ocrText
        guard !textToCopy.isEmpty else {
            lastError = "该记录无识别文字"
            return
        }
        clipboardService.setString(textToCopy)
        lastActionMessage = "已复制到剪贴板"
    }

    func copyImage(id: String) {
        guard let record = records.first(where: { $0.id == id }) else { return }
        guard let image = loadImage(for: record),
              let cgImage = image.cgImageForClipboard() else {
            lastError = "该记录无可复制图片"
            return
        }
        clipboardService.setImage(cgImage)
        lastActionMessage = "已复制图片"
    }

    func openFile(id: String) {
        guard let url = fileURL(for: id) else { return }
        NSWorkspace.shared.open(url)
        lastActionMessage = "已打开文件"
    }

    func copyFile(id: String) {
        guard let url = fileURL(for: id) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.writeObjects([url as NSURL]) {
            lastActionMessage = "已复制文件"
        } else {
            lastError = "复制文件失败"
        }
    }

    func revealInFinder(id: String) {
        guard let url = fileURL(for: id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        lastActionMessage = "已在 Finder 中显示"
    }

    // MARK: - 字幕

    func addSubtitle(id: String) {
        guard let coordinator = environment.subtitleCoordinator else {
            lastError = "字幕功能未就绪"
            return
        }
        coordinator.addSubtitle(recordID: id)
    }

    func openSubtitleEditor(id: String) {
        guard let coordinator = environment.subtitleCoordinator else { return }
        coordinator.openEditor(recordID: id)
    }

    func startSubtitleBurn(id: String) {
        guard let coordinator = environment.subtitleCoordinator else { return }
        coordinator.startBurn(recordID: id)
        lastActionMessage = "开始烧录字幕"
    }

    func openSubtitledVideo(id: String) {
        guard let record = records.first(where: { $0.id == id }),
              let path = record.subtitledVideoPath else {
            lastError = "带字幕视频不可用"
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        lastActionMessage = "已打开带字幕视频"
    }

    func openOriginalVideo(id: String) {
        guard let record = records.first(where: { $0.id == id }),
              let path = record.videoPath else {
            lastError = "原视频不可用"
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        lastActionMessage = "已打开原视频"
    }

    func retrySubtitle(id: String) {
        addSubtitle(id: id)
    }

    func loadImage(for record: MediaRecord) -> NSImage? {
        if let cached = imageCache.object(forKey: record.id as NSString) {
            return cached
        }
        guard let path = record.imagePath else {
            return nil
        }
        let image = ScreenshotImageStorage.loadImage(at: path)
        if let image {
            imageCache.setObject(
                image,
                forKey: record.id as NSString,
                cost: max(1, Int(image.size.width * image.size.height * 4))
            )
        }
        return image
    }

    func loadVideoThumbnail(for record: MediaRecord) -> NSImage? {
        if let cached = videoThumbnailCache.object(forKey: record.id as NSString) {
            return cached
        }
        guard record.mediaType == .screenRecording,
              let path = record.primaryVideoPath else {
            return nil
        }
        guard !pendingVideoThumbnailIDs.contains(record.id) else {
            return nil
        }
        pendingVideoThumbnailIDs.insert(record.id)

        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        videoThumbnailGenerators[record.id] = generator

        let recordID = record.id
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.generateCGImageAsynchronously(for: time) { [weak self] cgImage, _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.pendingVideoThumbnailIDs.remove(recordID)
                self.videoThumbnailGenerators[recordID] = nil

                guard let cgImage else {
                    return
                }
                let image = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: cgImage.width, height: cgImage.height)
                )
                self.videoThumbnailCache.setObject(
                    image,
                    forKey: recordID as NSString,
                    cost: max(1, cgImage.width * cgImage.height * 4)
                )
                self.objectWillChange.send()
            }
        }
        return nil
    }

    private func fileURL(for id: String) -> URL? {
        guard let record = records.first(where: { $0.id == id }) else {
            lastError = "该记录无可用文件"
            return nil
        }
        let paths = [
            record.primaryFilePath,
            record.videoPath,
            record.imagePath
        ]
        .compactMap { $0 }
        .reduce(into: [String]()) { result, path in
            if !result.contains(path) {
                result.append(path)
            }
        }

        guard let existingPath = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            lastError = paths.isEmpty ? "该记录无可用文件" : "文件不存在"
            lastActionMessage = nil
            return nil
        }
        return URL(fileURLWithPath: existingPath)
    }

    func clearFeedback() {
        lastError = nil
        lastActionMessage = nil
    }
}

private extension NSImage {
    func cgImageForClipboard() -> CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
