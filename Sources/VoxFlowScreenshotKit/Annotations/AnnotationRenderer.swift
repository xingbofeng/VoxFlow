import AppKit
import CoreGraphics
import Foundation

// Rendering approach adapted from sadopc/ScreenCapture ImageExporter (MIT), commit
// 081cb96b5c9f4bf72ace9187205009c92ab15f8c. VoxFlow keeps rendering separate
// from clipboard/OCR so 下载 and 完成 can use different workflow actions.

public enum AnnotationRendererError: Error, Equatable {
    case contextCreationFailed
    case imageCreationFailed
}

public protocol AnnotationRendering {
    func render(image: CGImage, document: AnnotationDocument) throws -> CGImage
}

public struct AnnotationRenderer: AnnotationRendering, Sendable {
    public init() {}

    public func render(image: CGImage, document: AnnotationDocument) throws -> CGImage {
        guard !document.elements.isEmpty else {
            return image
        }

        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AnnotationRendererError.contextCreationFailed
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let previousGraphicsContext = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer {
            NSGraphicsContext.current = previousGraphicsContext
        }

        for element in document.elements {
            render(element, in: context, sourceImage: image, imageHeight: CGFloat(height))
        }

        guard let rendered = context.makeImage() else {
            throw AnnotationRendererError.imageCreationFailed
        }
        return rendered
    }

    private func render(_ element: AnnotationElement, in context: CGContext, sourceImage: CGImage, imageHeight: CGFloat) {
        switch element {
        case .pen(let element):
            renderPen(element, in: context, imageHeight: imageHeight)
        case .ellipse(let element):
            renderEllipse(element, in: context, imageHeight: imageHeight)
        case .rectangle(let element):
            renderRectangle(element, in: context, imageHeight: imageHeight)
        case .arrow(let element):
            renderArrow(element, in: context, imageHeight: imageHeight)
        case .dotMarker(let element):
            renderDotMarker(element, in: context, imageHeight: imageHeight)
        case .numberedMarker(let element):
            renderNumberedMarker(element, in: context, imageHeight: imageHeight)
        case .text(let element):
            renderText(element, in: context, imageHeight: imageHeight)
        case .mosaic(let element):
            renderMosaic(element, in: context, sourceImage: sourceImage, imageHeight: imageHeight)
        case .translatedOverlay(let element):
            renderTranslatedOverlay(element, in: context, imageHeight: imageHeight)
        }
    }

    private func renderPen(_ element: FreehandAnnotationElement, in context: CGContext, imageHeight: CGFloat) {
        guard let first = element.points.first, element.points.count >= 2 else { return }
        context.setStrokeColor(element.style.color.cgColor)
        context.setLineWidth(element.style.lineWidth)
        context.beginPath()
        context.move(to: first.flipped(imageHeight: imageHeight))
        for point in element.points.dropFirst() {
            context.addLine(to: point.flipped(imageHeight: imageHeight))
        }
        context.strokePath()
    }

    private func renderEllipse(_ element: EllipseAnnotationElement, in context: CGContext, imageHeight: CGFloat) {
        let rect = element.rect.flipped(imageHeight: imageHeight)
        if let fillColor = element.style.fillColor {
            context.setFillColor(fillColor.cgColor)
            context.fillEllipse(in: rect)
        }
        context.setStrokeColor(element.style.color.cgColor)
        context.setLineWidth(element.style.lineWidth)
        context.strokeEllipse(in: rect)
    }

    private func renderRectangle(_ element: RectangleAnnotationElement, in context: CGContext, imageHeight: CGFloat) {
        let rect = element.rect.flipped(imageHeight: imageHeight)
        if let fillColor = element.style.fillColor {
            context.setFillColor(fillColor.cgColor)
            context.fill(rect)
        }
        context.setStrokeColor(element.style.color.cgColor)
        context.setLineWidth(element.style.lineWidth)
        context.stroke(rect)
    }

    private func renderArrow(_ element: ArrowAnnotationElement, in context: CGContext, imageHeight: CGFloat) {
        let start = element.startPoint.flipped(imageHeight: imageHeight)
        let end = element.endPoint.flipped(imageHeight: imageHeight)
        let lineWidth = element.style.lineWidth
        context.setStrokeColor(element.style.color.cgColor)
        context.setFillColor(element.style.color.cgColor)
        context.setLineWidth(lineWidth)

        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength = max(lineWidth * 4, 10)
        let arrowAngle = CGFloat.pi / 6
        let point1 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let point2 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )
        context.beginPath()
        context.move(to: end)
        context.addLine(to: point1)
        context.addLine(to: point2)
        context.closePath()
        context.fillPath()
    }

    private func renderDotMarker(_ element: DotMarkerAnnotationElement, in context: CGContext, imageHeight: CGFloat) {
        let rect = element.bounds.flipped(imageHeight: imageHeight)
        context.setFillColor((element.style.fillColor ?? element.style.color).cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(ScreenshotAnnotationColor.white.cgColor)
        context.setLineWidth(max(1, element.style.lineWidth))
        context.strokeEllipse(in: rect)
    }

    private func renderNumberedMarker(_ element: NumberedMarkerAnnotationElement, in context: CGContext, imageHeight: CGFloat) {
        renderDotMarker(
            DotMarkerAnnotationElement(
                id: element.id,
                center: element.center,
                radius: element.radius,
                style: element.style
            ),
            in: context,
            imageHeight: imageHeight
        )

        let text = "\(element.number)" as NSString
        let fontSize = max(10, element.radius)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        let center = element.center.flipped(imageHeight: imageHeight)
        let point = CGPoint(
            x: center.x - textSize.width / 2,
            y: center.y - textSize.height / 2
        )
        drawText(text, attributes: attributes, at: point)
    }

    private func renderText(_ element: TextAnnotationElement, in context: CGContext, imageHeight: CGFloat) {
        let font = NSFont(name: element.style.fontName, size: element.style.fontSize)
            ?? NSFont.systemFont(ofSize: element.style.fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: element.style.color.cgColor) ?? .systemGreen,
        ]
        let point = element.position.flipped(imageHeight: imageHeight)
        drawText(element.content as NSString, attributes: attributes, at: CGPoint(x: point.x, y: point.y - element.style.fontSize))
    }

    private func renderMosaic(_ element: MosaicAnnotationElement, in context: CGContext, sourceImage: CGImage, imageHeight: CGFloat) {
        let imageBounds = CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
        let sourceRect = element.bounds.integral.intersection(imageBounds)
        guard sourceRect.width > 0,
              sourceRect.height > 0,
              !element.points.isEmpty else {
            return
        }

        let block = max(4, element.blockSize)
        context.saveGState()
        clipMosaicStroke(element, in: context, imageHeight: imageHeight)
        context.interpolationQuality = .none

        var y = sourceRect.minY
        while y < sourceRect.maxY {
            var x = sourceRect.minX
            while x < sourceRect.maxX {
                let sampleX = min(max(Int(x.rounded(.down)), 0), sourceImage.width - 1)
                let sampleY = min(max(Int(y.rounded(.down)), 0), sourceImage.height - 1)
                let blockRect = CGRect(
                    x: x,
                    y: y,
                    width: min(block, sourceRect.maxX - x),
                    height: min(block, sourceRect.maxY - y)
                )
                if let sample = sourceImage.cropping(to: CGRect(x: sampleX, y: sampleY, width: 1, height: 1)) {
                    context.draw(sample, in: blockRect.flipped(imageHeight: imageHeight))
                }
                x += block
            }
            y += block
        }
        context.restoreGState()
    }

    private func clipMosaicStroke(_ element: MosaicAnnotationElement, in context: CGContext, imageHeight: CGFloat) {
        let flippedPoints = element.points.map { $0.flipped(imageHeight: imageHeight) }
        context.beginPath()
        if flippedPoints.count == 1, let point = flippedPoints.first {
            let radius = element.brushSize / 2
            context.addEllipse(in: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: element.brushSize,
                height: element.brushSize
            ))
            context.clip()
            return
        }

        guard let first = flippedPoints.first else { return }
        context.move(to: first)
        for point in flippedPoints.dropFirst() {
            context.addLine(to: point)
        }
        context.setLineWidth(element.brushSize)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.replacePathWithStrokedPath()
        context.clip()
    }

    private func drawText(
        _ text: NSString,
        attributes: [NSAttributedString.Key: Any],
        at point: CGPoint
    ) {
        NSGraphicsContext.saveGraphicsState()
        text.draw(at: point, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 译文覆盖渲染：对每行，先用白色 fill 覆盖原文 bbox，再用自适应字号居中绘制译文。
    /// 字号策略：从 bbox 高度的 1.0x 起，递减 0.5 直到文本能填入 bbox 宽度，最小 8pt。
    private func renderTranslatedOverlay(
        _ element: TranslatedOverlayAnnotationElement,
        in context: CGContext,
        imageHeight: CGFloat
    ) {
        for line in element.lines {
            let boundsFlipped = line.bounds.flipped(imageHeight: imageHeight)
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(boundsFlipped)

            let text = line.text as NSString
            let maxFontSize = max(8, boundsFlipped.height)
            var fontSize = maxFontSize
            let targetWidth = boundsFlipped.width - 4

            while fontSize > 8 {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                    .foregroundColor: NSColor.black,
                ]
                let textSize = text.size(withAttributes: attributes)
                if textSize.width <= targetWidth {
                    break
                }
                fontSize -= 1
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: NSColor.black,
            ]
            let textSize = text.size(withAttributes: attributes)
            let textPoint = CGPoint(
                x: boundsFlipped.midX - textSize.width / 2,
                y: boundsFlipped.midY - textSize.height / 2
            )
            drawText(text, attributes: attributes, at: textPoint)
        }
    }
}

private extension ScreenshotAnnotationColor {
    var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }

}

private extension CGPoint {
    func flipped(imageHeight: CGFloat) -> CGPoint {
        CGPoint(x: x, y: imageHeight - y)
    }
}

private extension CGRect {
    func flipped(imageHeight: CGFloat) -> CGRect {
        CGRect(x: minX, y: imageHeight - minY - height, width: width, height: height)
    }
}
