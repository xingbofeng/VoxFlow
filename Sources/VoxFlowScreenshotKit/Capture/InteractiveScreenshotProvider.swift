import CoreGraphics
import Foundation

public enum InteractiveScreenshotError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case captureFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return ScreenshotL10n.ScreenshotKit.Capture.Error.selectionCancelled
        case .captureFailed(let reason):
            return reason
        }
    }
}

public enum InteractiveScreenshotCompletionKind: Equatable, Sendable {
    case complete
    case scrollingScreenshot
    case textRecognition
    case translate
}

public struct InteractiveScreenshotCaptureResult: Equatable {
    public let image: CGImage
    public let completionKind: InteractiveScreenshotCompletionKind

    public init(
        image: CGImage,
        completionKind: InteractiveScreenshotCompletionKind = .complete
    ) {
        self.image = image
        self.completionKind = completionKind
    }

    public static func == (
        lhs: InteractiveScreenshotCaptureResult,
        rhs: InteractiveScreenshotCaptureResult
    ) -> Bool {
        lhs.image.width == rhs.image.width &&
            lhs.image.height == rhs.image.height &&
            lhs.completionKind == rhs.completionKind
    }
}

@MainActor
public protocol InlineSelectionTranslating: AnyObject {
    func translatedOverlay(for image: CGImage) async throws -> TranslatedOverlayAnnotationElement
    func translatedOverlay(
        for image: CGImage,
        progress: @escaping @MainActor (InlineSelectionTranslationProgress) -> Void
    ) async throws -> TranslatedOverlayAnnotationElement
}

public extension InlineSelectionTranslating {
    func translatedOverlay(
        for image: CGImage,
        progress: @escaping @MainActor (InlineSelectionTranslationProgress) -> Void
    ) async throws -> TranslatedOverlayAnnotationElement {
        try await translatedOverlay(for: image)
    }
}

public struct InlineSelectionTranslationProgress: Equatable, Sendable {
    public let completed: Int
    public let total: Int
    public let partialOverlay: TranslatedOverlayAnnotationElement?

    public init(
        completed: Int,
        total: Int,
        partialOverlay: TranslatedOverlayAnnotationElement? = nil
    ) {
        self.completed = completed
        self.total = total
        self.partialOverlay = partialOverlay
    }
}

@MainActor
public protocol InteractiveScreenshotProviding {
    func captureImage() async throws -> CGImage
    func capture() async throws -> InteractiveScreenshotCaptureResult
}

public extension InteractiveScreenshotProviding {
    func capture() async throws -> InteractiveScreenshotCaptureResult {
        let image = try await captureImage()
        return InteractiveScreenshotCaptureResult(image: image)
    }
}
