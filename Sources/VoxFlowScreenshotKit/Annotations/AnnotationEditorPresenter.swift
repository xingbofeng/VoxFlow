import AppKit
import CoreGraphics
import SwiftUI

@MainActor
public protocol AnnotationEditing: AnyObject {
    func edit(image: CGImage) async throws -> CGImage
}

@MainActor
public final class AnnotationEditorPresenter: AnnotationEditing {
    private var activeWindow: NSWindow?

    public init() {}

    public func edit(image: CGImage) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            var window: NSWindow?

            let finish: (Result<CGImage, Error>) -> Void = { [weak self] result in
                guard !didResume else { return }
                didResume = true
                window?.close()
                self?.activeWindow = nil
                continuation.resume(with: result)
            }

            let viewModel = AnnotationEditorViewModel(image: image)
            let view = AnnotationEditorView(
                viewModel: viewModel,
                onComplete: { image in finish(.success(image)) },
                onCancel: { finish(.failure(InteractiveScreenshotError.cancelled)) },
                onError: { _ in NSSound.beep() }
            )

            let targetSize = Self.windowSize(for: image)
            let panel = NSPanel(
                contentRect: CGRect(origin: .zero, size: targetSize),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.contentView = NSHostingView(rootView: view)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.center()

            window = panel
            activeWindow = panel
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private static func windowSize(for image: CGImage) -> CGSize {
        let width = min(max(CGFloat(image.width) + 56, 640), 1_320)
        let height = min(max(CGFloat(image.height) + 118, 360), 920)
        return CGSize(width: width, height: height)
    }
}
