import CoreGraphics
import Foundation

public enum InteractiveScreenshotError: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case captureFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "已取消截图"
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
