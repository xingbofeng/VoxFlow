import AppKit
import CoreGraphics

@MainActor
final class SystemClipboardImageProvider: ClipboardImageProviding {
    private let logger = AppLogger.general

    func currentImage() -> CGImage? {
        guard let image = NSImage(pasteboard: NSPasteboard.general) else {
            logger.debug("SystemClipboardImageProvider no image on pasteboard")
            return nil
        }
        logger.debug("SystemClipboardImageProvider got NSImage size=\(image.size.width)x\(image.size.height)")
        var proposedRect = CGRect(origin: .zero, size: image.size)
        let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        if let cgImage {
            logger.debug("SystemClipboardImageProvider extracted CGImage size=\(cgImage.width)x\(cgImage.height)")
        } else {
            logger.warning("SystemClipboardImageProvider failed to extract CGImage")
        }
        return cgImage
    }
}
