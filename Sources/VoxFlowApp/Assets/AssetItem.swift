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

enum AssetValidationError: Error, Equatable, LocalizedError {
    case missingRequiredField(contentType: AssetContentType, field: String)

    var errorDescription: String? {
        switch self {
        case .missingRequiredField(let contentType, let field):
            return "Invalid \(contentType.rawValue) asset: missing required field \(field)."
        }
    }
}

extension AssetItem {
    static func makeText(
        id: String,
        source: AssetSource,
        title: String,
        text: String,
        rawText: String? = nil,
        previewText: String? = nil,
        contentHash: String,
        captureReason: AssetCaptureReason,
        metadataJSON: String? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) throws -> AssetItem {
        try AssetItem(
            id: id,
            source: source,
            contentType: .text,
            title: title,
            previewText: previewText ?? text,
            text: text,
            rawText: rawText,
            imagePath: nil,
            filePath: nil,
            url: nil,
            colorValue: nil,
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID,
            contentHash: contentHash,
            captureReason: captureReason,
            metadataJSON: metadataJSON,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
            deletedAt: deletedAt
        ).validated()
    }

    static func makeImage(
        id: String,
        source: AssetSource,
        title: String,
        imagePath: String,
        previewText: String? = nil,
        text: String? = nil,
        contentHash: String,
        captureReason: AssetCaptureReason,
        metadataJSON: String? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) throws -> AssetItem {
        try AssetItem(
            id: id,
            source: source,
            contentType: .image,
            title: title,
            previewText: previewText,
            text: text,
            rawText: nil,
            imagePath: imagePath,
            filePath: nil,
            url: nil,
            colorValue: nil,
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID,
            contentHash: contentHash,
            captureReason: captureReason,
            metadataJSON: metadataJSON,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
            deletedAt: deletedAt
        ).validated()
    }

    static func makeFile(
        id: String,
        source: AssetSource,
        title: String,
        filePath: String,
        previewText: String? = nil,
        contentHash: String,
        captureReason: AssetCaptureReason,
        metadataJSON: String? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) throws -> AssetItem {
        try AssetItem(
            id: id,
            source: source,
            contentType: .file,
            title: title,
            previewText: previewText ?? filePath,
            text: nil,
            rawText: nil,
            imagePath: nil,
            filePath: filePath,
            url: nil,
            colorValue: nil,
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID,
            contentHash: contentHash,
            captureReason: captureReason,
            metadataJSON: metadataJSON,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
            deletedAt: deletedAt
        ).validated()
    }

    static func makeLink(
        id: String,
        source: AssetSource,
        title: String,
        url: String,
        previewText: String? = nil,
        text: String? = nil,
        contentHash: String,
        captureReason: AssetCaptureReason,
        metadataJSON: String? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) throws -> AssetItem {
        try AssetItem(
            id: id,
            source: source,
            contentType: .link,
            title: title,
            previewText: previewText ?? text ?? url,
            text: text,
            rawText: nil,
            imagePath: nil,
            filePath: nil,
            url: url,
            colorValue: nil,
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID,
            contentHash: contentHash,
            captureReason: captureReason,
            metadataJSON: metadataJSON,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
            deletedAt: deletedAt
        ).validated()
    }

    static func makeColor(
        id: String,
        source: AssetSource,
        title: String,
        colorValue: String,
        previewText: String? = nil,
        contentHash: String,
        captureReason: AssetCaptureReason,
        metadataJSON: String? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil
    ) throws -> AssetItem {
        try AssetItem(
            id: id,
            source: source,
            contentType: .color,
            title: title,
            previewText: previewText ?? colorValue,
            text: colorValue,
            rawText: nil,
            imagePath: nil,
            filePath: nil,
            url: nil,
            colorValue: colorValue,
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID,
            contentHash: contentHash,
            captureReason: captureReason,
            metadataJSON: metadataJSON,
            createdAt: createdAt,
            updatedAt: updatedAt ?? createdAt,
            deletedAt: deletedAt
        ).validated()
    }

    func validated() throws -> AssetItem {
        try validate()
        return self
    }

    func validate() throws {
        try requireNonEmpty(id, field: "id")
        try requireNonEmpty(title, field: "title")
        try requireNonEmpty(contentHash, field: "content_hash")

        switch contentType {
        case .text:
            try requireNonEmpty(text, field: "text")
        case .image:
            try requireNonEmpty(imagePath, field: "image_path")
        case .file:
            try requireNonEmpty(filePath, field: "file_path")
        case .link:
            try requireNonEmpty(url, field: "url")
        case .color:
            try requireNonEmpty(colorValue, field: "color_value")
        }
    }

    private func requireNonEmpty(_ value: String?, field: String) throws {
        guard value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw AssetValidationError.missingRequiredField(contentType: contentType, field: field)
        }
    }
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
