import Foundation

enum AssetSource: String, Codable, Sendable, CaseIterable {
    case dictation
    case screenshot
    case clipboard
}

enum AssetContentType: String, Codable, Sendable, CaseIterable {
    case text
    case image
    case file
    case link
    case color
}

enum AssetCaptureReason: String, Codable, Sendable, CaseIterable {
    case dictationCompleted
    case screenshotCaptured
    case userCopied
    case fallbackCopied
}

struct AssetItem: Equatable, Identifiable, Sendable {
    let id: String
    let source: AssetSource
    let contentType: AssetContentType
    let title: String
    let previewText: String?
    let text: String?
    let rawText: String?
    let imagePath: String?
    let filePath: String?
    let url: String?
    let colorValue: String?
    let sourceAppName: String?
    let sourceAppBundleID: String?
    let contentHash: String
    let captureReason: AssetCaptureReason
    let metadataJSON: String?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}

struct AssetQuery: Equatable, Sendable {
    var searchText: String = ""
    var sources: Set<AssetSource> = []
    var contentTypes: Set<AssetContentType> = []
    var startDate: Date?
    var endDate: Date?
    var limit: Int
    var offset: Int
}

struct AssetPage: Equatable, Sendable {
    let items: [AssetItem]
    let totalCount: Int
}
