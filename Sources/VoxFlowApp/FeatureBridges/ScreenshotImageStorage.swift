import AppKit
import CoreGraphics
import Foundation

enum ScreenshotImageStorageError: Error, LocalizedError {
    case bitmapRepCreationFailed
    case pngEncodingFailed
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .bitmapRepCreationFailed:
            return "无法创建图片位图表示"
        case .pngEncodingFailed:
            return "PNG 编码失败"
        case .writeFailed(let reason):
            return "写入截图文件失败: \(reason)"
        }
    }
}

enum ScreenshotImageStorage {
    private static let logger = AppLogger.general

    static func save(image: CGImage, id: String, directory: URL) throws -> String {
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            Self.logger.warning("ScreenshotImageStorage save failed: png encoding failed for id=\(id)")
            throw ScreenshotImageStorageError.pngEncodingFailed
        }

        let fileURL = directory.appendingPathComponent("\(id).png", isDirectory: false)
        do {
            Self.logger.debug("ScreenshotImageStorage write image start id=\(id) path=\(fileURL.path)")
            try pngData.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("ScreenshotImageStorage save failed id=\(id) path=\(fileURL.path) reason=\(error.localizedDescription)")
            throw ScreenshotImageStorageError.writeFailed(error.localizedDescription)
        }
        Self.logger.debug("ScreenshotImageStorage save completed id=\(id) path=\(fileURL.path)")
        return fileURL.path
    }

    static func loadImage(at path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path) else {
            Self.logger.debug("ScreenshotImageStorage load missing path=\(path)")
            return nil
        }
        Self.logger.debug("ScreenshotImageStorage load found path=\(path)")
        return NSImage(contentsOfFile: path)
    }
}
