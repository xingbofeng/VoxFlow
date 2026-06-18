import AppKit
import CoreGraphics

@MainActor
final class SystemClipboardImageProvider: ClipboardImageProviding {
    func currentImage() -> CGImage? {
        guard let image = NSImage(pasteboard: NSPasteboard.general) else {
            return nil
        }
        var proposedRect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
}
