import AppKit
import Combine
import Foundation

@MainActor
final class ScreenshotRecordViewModel: ObservableObject {
    @Published var records: [ScreenshotRecord] = []
    @Published var searchText: String = ""
    @Published var onlyFavorites: Bool = false {
        didSet {
            if oldValue != onlyFavorites {
                currentPage = 1
                load()
            }
        }
    }
    @Published var stats: ScreenshotRecordStats?
    @Published var lastError: String?
    @Published var lastActionMessage: String?
    @Published private(set) var currentPage = 1
    @Published private(set) var pageSize: Int = 20
    @Published private(set) var totalRecords = 0

    private let environment: any AppServiceProviding
    private let clipboardService: SystemClipboardService
    private let imageCache = NSCache<NSString, NSImage>()
    private var hasLoaded = false

    init(environment: any AppServiceProviding, clipboardService: SystemClipboardService) {
        self.environment = environment
        self.clipboardService = clipboardService
        imageCache.countLimit = 60
        imageCache.totalCostLimit = 120 * 1024 * 1024
    }

    var totalPages: Int { max(1, Int(ceil(Double(totalRecords) / Double(pageSize)))) }
    var canGoToPreviousPage: Bool { currentPage > 1 }
    var canGoToNextPage: Bool { currentPage < totalPages }

    func load() {
        do {
            let page = try environment.screenshotRecordRepository.page(
                limit: pageSize,
                offset: (currentPage - 1) * pageSize,
                search: searchText.isEmpty ? nil : searchText,
                onlyFavorites: onlyFavorites
            )
            records = page.records
            totalRecords = page.totalCount
            stats = try environment.screenshotRecordRepository.stats()
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
            try environment.screenshotRecordRepository.toggleFavorite(
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
            let imagePath = try environment.screenshotRecordRepository.record(id: id)?.imagePath
            try environment.screenshotRecordRepository.softDelete(
                id: id,
                deletedAt: environment.clock.now
            )
            imageCache.removeObject(forKey: id as NSString)
            if let imagePath {
                try ScreenshotImageStorage.deleteImage(at: imagePath)
            }
            load()
            lastActionMessage = "已删除"
        } catch {
            lastError = error.localizedDescription
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

    func loadImage(for record: ScreenshotRecord) -> NSImage? {
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
