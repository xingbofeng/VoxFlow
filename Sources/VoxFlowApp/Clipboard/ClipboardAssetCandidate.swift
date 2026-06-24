import AppKit
import CryptoKit
import Foundation

struct ClipboardSourceApplication: Equatable, Sendable {
    let name: String?
    let bundleID: String?
}

struct ClipboardAssetCandidate: Equatable, Sendable {
    let contentType: AssetContentType
    let title: String
    let previewText: String?
    let text: String?
    let imageData: Data?
    let filePath: String?
    let url: String?
    let colorValue: String?
    let contentHash: String

    func makeAsset(
        now: Date,
        createdAt: Date? = nil,
        sourceApplication: ClipboardSourceApplication?,
        imagePath: String? = nil
    ) -> AssetItem {
        AssetItem(
            id: "clipboard-\(contentHash)",
            source: .clipboard,
            contentType: contentType,
            title: title,
            previewText: previewText,
            text: text,
            rawText: nil,
            imagePath: imagePath,
            filePath: filePath,
            url: url,
            colorValue: colorValue,
            sourceAppName: sourceApplication?.name,
            sourceAppBundleID: sourceApplication?.bundleID,
            contentHash: contentHash,
            captureReason: .userCopied,
            metadataJSON: nil,
            createdAt: createdAt ?? now,
            updatedAt: now,
            deletedAt: nil
        )
    }
}

enum ClipboardAssetCandidateExtractor {
    /// Adapted from Stash ClipboardMonitor.swift (MIT): https://github.com/hex/Stash
    /// and Maccy HistoryItem.swift (MIT): https://github.com/p0deje/Maccy
    static func candidate(
        from pasteboard: NSPasteboard,
        item: NSPasteboardItem
    ) -> ClipboardAssetCandidate? {
        let plainText = item.string(forType: .string)
        guard let contentType = ClipboardContentClassifier.detect(
            from: item.types,
            plainText: plainText
        ) else {
            return nil
        }

        switch contentType {
        case .text:
            return textCandidate(plainText: plainText)
        case .link:
            return linkCandidate(item: item, plainText: plainText)
        case .color:
            return colorCandidate(plainText: plainText)
        case .file:
            return fileCandidate(from: pasteboard, item: item)
        case .image:
            return imageCandidate(from: pasteboard, item: item)
        }
    }

    private static func textCandidate(plainText: String?) -> ClipboardAssetCandidate? {
        guard let text = nonEmpty(plainText) else { return nil }
        return ClipboardAssetCandidate(
            contentType: .text,
            title: title(from: text),
            previewText: text,
            text: text,
            imageData: nil,
            filePath: nil,
            url: nil,
            colorValue: nil,
            contentHash: hash(parts: ["text", text])
        )
    }

    private static func linkCandidate(
        item: NSPasteboardItem,
        plainText: String?
    ) -> ClipboardAssetCandidate? {
        let url = nonEmpty(item.string(forType: .URL))
            ?? exactURL(from: plainText)
        guard let url else { return nil }
        let text = nonEmpty(plainText) ?? url
        return ClipboardAssetCandidate(
            contentType: .link,
            title: title(from: url),
            previewText: text,
            text: text,
            imageData: nil,
            filePath: nil,
            url: url,
            colorValue: nil,
            contentHash: hash(parts: ["link", url])
        )
    }

    private static func colorCandidate(plainText: String?) -> ClipboardAssetCandidate? {
        guard let color = nonEmpty(plainText),
              ClipboardContentClassifier.isExactColor(color) else {
            return nil
        }
        return ClipboardAssetCandidate(
            contentType: .color,
            title: color,
            previewText: color,
            text: color,
            imageData: nil,
            filePath: nil,
            url: nil,
            colorValue: color,
            contentHash: hash(parts: ["color", color])
        )
    }

    private static func fileCandidate(
        from pasteboard: NSPasteboard,
        item: NSPasteboardItem
    ) -> ClipboardAssetCandidate? {
        let path = filePath(from: pasteboard)
            ?? nonEmpty(item.string(forType: .fileURL)).flatMap { URL(string: $0)?.path }
        guard let path else { return nil }
        return ClipboardAssetCandidate(
            contentType: .file,
            title: URL(fileURLWithPath: path).lastPathComponent,
            previewText: path,
            text: path,
            imageData: nil,
            filePath: path,
            url: nil,
            colorValue: nil,
            contentHash: hash(parts: ["file", path])
        )
    }

    private static func imageCandidate(
        from pasteboard: NSPasteboard,
        item: NSPasteboardItem
    ) -> ClipboardAssetCandidate? {
        guard let data = item.data(forType: .png)
            ?? item.data(forType: .tiff)
            ?? pasteboard.data(forType: .png)
            ?? pasteboard.data(forType: .tiff) else {
            return nil
        }
        return ClipboardAssetCandidate(
            contentType: .image,
            title: "Image",
            previewText: "\(data.count) bytes",
            text: nil,
            imageData: data,
            filePath: nil,
            url: nil,
            colorValue: nil,
            contentHash: hash(parts: ["image"], data: data)
        )
    }

    private static func filePath(from pasteboard: NSPasteboard) -> String? {
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return nil
        }
        return urls.first?.path
    }

    private static func exactURL(from plainText: String?) -> String? {
        guard let text = nonEmpty(plainText) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
              let match = detector.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.range.location == 0,
              match.range.length == trimmed.utf16.count else {
            return nil
        }
        return match.url?.absoluteString ?? trimmed
    }

    private static func title(from text: String) -> String {
        let collapsed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? text
        guard collapsed.count > 80 else { return collapsed }
        return String(collapsed.prefix(80))
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func hash(parts: [String], data: Data? = nil) -> String {
        var input = Data()
        for part in parts {
            input.append(contentsOf: part.utf8)
            input.append(0)
        }
        if let data {
            input.append(data)
        }
        return SHA256.hash(data: input)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
