import CoreGraphics
import Foundation

@MainActor
public protocol InteractiveScreenshotCaptureLeasing: AnyObject {
    func tryAcquire() -> Bool
    func release()
}

@MainActor
public final class InteractiveScreenshotCaptureLease: InteractiveScreenshotCaptureLeasing {
    public static let shared = InteractiveScreenshotCaptureLease()

    private var isAcquired = false

    public init() {}

    public func tryAcquire() -> Bool {
        guard !isAcquired else { return false }
        isAcquired = true
        return true
    }

    public func release() {
        isAcquired = false
    }
}

@MainActor
public final class VoxFlowInteractiveScreenshotProvider: InteractiveScreenshotProviding {
    public typealias SelectionProvider = ([ScreenshotDisplayFrame]) async -> SelectionOverlayResult
    public typealias OverlayControllerFactory = (
        @escaping @MainActor (SelectionOverlayResult) -> Void
    ) -> SelectionOverlayController

    private let frameProvider: ScreenCaptureFrameProvider
    private let annotationEditor: any AnnotationEditing
    private let annotationRenderer: any AnnotationRendering
    private let shouldOpenAnnotationEditor: Bool
    private let selectionProvider: SelectionProvider?
    private let overlayControllerFactory: OverlayControllerFactory
    private let inlineTranslator: (any InlineSelectionTranslating)?
    private let captureLease: any InteractiveScreenshotCaptureLeasing
    private var activeOverlayController: SelectionOverlayController?
    private var cancelActiveSelection: (() -> Void)?

    public init(
        frameProvider: ScreenCaptureFrameProvider = ScreenCaptureFrameProvider(),
        annotationEditor: any AnnotationEditing = AnnotationEditorPresenter(),
        annotationRenderer: any AnnotationRendering = AnnotationRenderer(),
        shouldOpenAnnotationEditor: Bool = false,
        selectionProvider: SelectionProvider? = nil,
        inlineTranslator: (any InlineSelectionTranslating)? = nil,
        captureLease: any InteractiveScreenshotCaptureLeasing = InteractiveScreenshotCaptureLease.shared,
        overlayControllerFactory: OverlayControllerFactory? = nil
    ) {
        self.frameProvider = frameProvider
        self.annotationEditor = annotationEditor
        self.annotationRenderer = annotationRenderer
        self.shouldOpenAnnotationEditor = shouldOpenAnnotationEditor
        self.selectionProvider = selectionProvider
        self.inlineTranslator = inlineTranslator
        self.captureLease = captureLease
        self.overlayControllerFactory = overlayControllerFactory ?? { onResult in
            SelectionOverlayController(
                inlineTranslator: inlineTranslator,
                onResult: onResult
            )
        }
    }

    public func captureImage() async throws -> CGImage {
        let result = try await capture()
        return result.image
    }

    public func capture() async throws -> InteractiveScreenshotCaptureResult {
        guard captureLease.tryAcquire() else {
            throw InteractiveScreenshotError.captureFailed(ScreenshotL10n.ScreenshotKit.Capture.Error.sessionInProgress)
        }
        defer { captureLease.release() }

        let frames: [ScreenshotDisplayFrame]
        do {
            frames = try await frameProvider.captureDisplayFrames()
        } catch ScreenCaptureFrameProviderError.cancelled {
            throw InteractiveScreenshotError.cancelled
        } catch {
            throw InteractiveScreenshotError.captureFailed(error.localizedDescription)
        }

        guard !frames.isEmpty else {
            throw InteractiveScreenshotError.captureFailed(ScreenshotL10n.ScreenshotKit.Capture.Error.noActiveDisplay)
        }

        let result = await waitForSelection(frames: frames)
        switch result {
        case .cancelled:
            throw InteractiveScreenshotError.cancelled
        case .accepted(let state):
            let croppedImage = try cropSelection(state, from: frames)
            guard shouldOpenAnnotationEditor else {
                return InteractiveScreenshotCaptureResult(image: croppedImage)
            }
            let editedImage = try await editSelectionImage(croppedImage)
            return InteractiveScreenshotCaptureResult(image: editedImage)
        case .acceptedAnnotated(let state, let document):
            let croppedImage = try cropSelection(state, from: frames)
            return try InteractiveScreenshotCaptureResult(image: renderAnnotations(document, onto: croppedImage))
        case .acceptedScrolling(let result):
            return InteractiveScreenshotCaptureResult(
                image: result.image,
                completionKind: .scrollingScreenshot
            )
        case .acceptedTextRecognition(let state):
            let croppedImage = try cropSelection(state, from: frames)
            guard shouldOpenAnnotationEditor else {
                return InteractiveScreenshotCaptureResult(image: croppedImage, completionKind: .textRecognition)
            }
            let editedImage = try await editSelectionImage(croppedImage)
            return InteractiveScreenshotCaptureResult(
                image: editedImage,
                completionKind: .textRecognition
            )
        case .acceptedAnnotatedTextRecognition(let state, let document):
            let croppedImage = try cropSelection(state, from: frames)
            return try InteractiveScreenshotCaptureResult(
                image: renderAnnotations(document, onto: croppedImage),
                completionKind: .textRecognition
            )
        case .acceptedTranslation(let state):
            let croppedImage = try cropSelection(state, from: frames)
            return InteractiveScreenshotCaptureResult(
                image: croppedImage,
                completionKind: .translate
            )
        case .acceptedScreenRecording:
            // 录屏结果由 app 层 ScreenRecordingCoordinator 处理，不应进入截图 provider 流程。
            throw InteractiveScreenshotError.cancelled
        }
    }

    private func waitForSelection(frames: [ScreenshotDisplayFrame]) async -> SelectionOverlayResult {
        if let selectionProvider {
            return await selectionProvider(frames)
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                var didResume = false
                let finish: @MainActor (SelectionOverlayResult) -> Void = { [weak self] result in
                    guard !didResume else { return }
                    didResume = true
                    self?.cancelActiveSelection = nil
                    self?.activeOverlayController = nil
                    continuation.resume(returning: result)
                }
                let controller = overlayControllerFactory(finish)
                activeOverlayController = controller
                cancelActiveSelection = {
                    controller.close()
                    finish(.cancelled)
                }
                if Task.isCancelled {
                    cancelActiveSelection?()
                } else {
                    controller.present(frames: frames)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelActiveSelection?()
            }
        }
    }

    private func editSelectionImage(_ image: CGImage) async throws -> CGImage {
        do {
            return try await annotationEditor.edit(image: image)
        } catch InteractiveScreenshotError.cancelled {
            throw InteractiveScreenshotError.cancelled
        } catch {
            throw InteractiveScreenshotError.captureFailed(error.localizedDescription)
        }
    }

    private func renderAnnotations(_ document: AnnotationDocument, onto image: CGImage) throws -> CGImage {
        do {
            return try annotationRenderer.render(image: image, document: document)
        } catch {
            throw InteractiveScreenshotError.captureFailed(error.localizedDescription)
        }
    }

    private func cropSelection(
        _ state: SelectionState,
        from frames: [ScreenshotDisplayFrame]
    ) throws -> CGImage {
        guard let cropped = ScreenshotSelectionImageComposer.cropSelection(state, from: frames) else {
            throw InteractiveScreenshotError.captureFailed(ScreenshotL10n.ScreenshotKit.Capture.Error.cropFailed)
        }
        return cropped
    }
}

enum ScreenshotSelectionImageComposer {
    static func cropSelection(
        _ state: SelectionState,
        from frames: [ScreenshotDisplayFrame]
    ) -> CGImage? {
        let selectionRect = state.normalizedRect
        let intersectingFrames = frames.compactMap { frame -> (ScreenshotDisplayFrame, CGRect)? in
            guard frame.image != nil else {
                return nil
            }
            let intersection = selectionRect.intersection(frame.display.frame)
            guard intersection.width > 0, intersection.height > 0 else {
                return nil
            }
            return (frame, intersection)
        }
        guard !intersectingFrames.isEmpty else {
            return nil
        }

        let outputScale = max(state.displayScale, intersectingFrames.map { $0.0.display.scale }.max() ?? 1, 1)
        let outputWidth = Int(ceil(selectionRect.width * outputScale))
        let outputHeight = Int(ceil(selectionRect.height * outputScale))
        guard outputWidth > 0, outputHeight > 0 else {
            return nil
        }

        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
        context.interpolationQuality = .high

        for (frame, pointIntersection) in intersectingFrames {
            guard let image = frame.image else {
                continue
            }
            let sourceScale = max(frame.display.scale, 1)
            let sourceRect = CGRect(
                x: (pointIntersection.minX - frame.display.frame.minX) * sourceScale,
                y: (pointIntersection.minY - frame.display.frame.minY) * sourceScale,
                width: pointIntersection.width * sourceScale,
                height: pointIntersection.height * sourceScale
            ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard sourceRect.width > 0,
                  sourceRect.height > 0,
                  let cropped = image.cropping(to: sourceRect) else {
                continue
            }

            let adjustedPointRect = CGRect(
                x: frame.display.frame.minX + sourceRect.minX / sourceScale,
                y: frame.display.frame.minY + sourceRect.minY / sourceScale,
                width: sourceRect.width / sourceScale,
                height: sourceRect.height / sourceScale
            )
            let destinationRect = CGRect(
                x: (adjustedPointRect.minX - selectionRect.minX) * outputScale,
                y: (adjustedPointRect.minY - selectionRect.minY) * outputScale,
                width: adjustedPointRect.width * outputScale,
                height: adjustedPointRect.height * outputScale
            )
            context.draw(cropped, in: destinationRect)
        }

        return context.makeImage()
    }
}
