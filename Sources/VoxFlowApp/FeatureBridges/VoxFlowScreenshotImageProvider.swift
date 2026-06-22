import CoreGraphics
import VoxFlowScreenshotKit

@MainActor
final class VoxFlowScreenshotImageProvider: ScreenshotImageProviding {
    private static let logger = AppLogger.general

    private let screenshotProvider: any InteractiveScreenshotProviding

    init(
        screenshotProvider: (any InteractiveScreenshotProviding)? = nil,
        inlineTranslator: (any InlineSelectionTranslating)? = nil
    ) {
        self.screenshotProvider = screenshotProvider ?? VoxFlowInteractiveScreenshotProvider(
            inlineTranslator: inlineTranslator
        )
    }

    func captureImage() async throws -> CGImage {
        Self.logger.debug("VoxFlowScreenshotImageProvider captureImage start")
        let result = try await capture()
        Self.logger.debug("VoxFlowScreenshotImageProvider captureImage completion kind=\(result.completionKind) size=\(result.image.width)x\(result.image.height)")
        return result.image
    }

    func capture() async throws -> ScreenshotImageCaptureResult {
        Self.logger.debug("VoxFlowScreenshotImageProvider capture start")
        do {
            let result = try await screenshotProvider.capture()
            Self.logger.debug("VoxFlowScreenshotImageProvider capture core success kind=\(result.completionKind)")
            return ScreenshotImageCaptureResult(
                image: result.image,
                completionKind: result.completionKind.screenshotCaptureCompletionKind
            )
        } catch InteractiveScreenshotError.cancelled {
            Self.logger.info("VoxFlowScreenshotImageProvider capture cancelled")
            throw ScreenshotOCRServiceError.captureCancelled
        } catch InteractiveScreenshotError.captureFailed(let reason) {
            Self.logger.warning("VoxFlowScreenshotImageProvider capture failed reason=\(reason)")
            throw ScreenshotOCRServiceError.captureFailed(reason)
        } catch {
            Self.logger.warning("VoxFlowScreenshotImageProvider capture failed unknown: \(error.localizedDescription)")
            throw ScreenshotOCRServiceError.captureFailed(error.localizedDescription)
        }
    }
}

private extension InteractiveScreenshotCompletionKind {
    var screenshotCaptureCompletionKind: ScreenshotCaptureCompletionKind {
        switch self {
        case .complete:
            return .complete
        case .scrollingScreenshot:
            return .scrollingScreenshot
        case .textRecognition:
            return .textRecognition
        case .translate:
            return .translate
        }
    }
}
