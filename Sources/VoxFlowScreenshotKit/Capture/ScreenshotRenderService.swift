import CoreGraphics
import Foundation

public struct ScreenshotRenderService {
    private let renderer: any AnnotationRendering

    public init(renderer: any AnnotationRendering = AnnotationRenderer()) {
        self.renderer = renderer
    }

    public func render(
        originalImage: CGImage,
        document: AnnotationDocument
    ) throws -> CGImage {
        try renderer.render(image: originalImage, document: document)
    }
}
