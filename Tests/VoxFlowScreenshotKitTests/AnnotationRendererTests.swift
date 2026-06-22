import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

final class AnnotationRendererTests: XCTestCase {
    func testRendererCompositesAllAnnotationElementTypesWithoutChangingImageSize() throws {
        let sourceImage = makeImage(width: 120, height: 80)
        var document = AnnotationDocument()
        document.add(.pen(FreehandAnnotationElement(points: [CGPoint(x: 2, y: 2), CGPoint(x: 10, y: 8)])))
        document.add(.ellipse(EllipseAnnotationElement(rect: CGRect(x: 10, y: 10, width: 30, height: 20))))
        document.add(.rectangle(RectangleAnnotationElement(rect: CGRect(x: 20, y: 20, width: 30, height: 20))))
        document.add(.arrow(ArrowAnnotationElement(startPoint: CGPoint(x: 4, y: 50), endPoint: CGPoint(x: 40, y: 60))))
        document.add(.dotMarker(DotMarkerAnnotationElement(center: CGPoint(x: 60, y: 20))))
        document.add(.numberedMarker(NumberedMarkerAnnotationElement(center: CGPoint(x: 70, y: 20), number: 3)))
        document.add(.text(TextAnnotationElement(position: CGPoint(x: 8, y: 65), content: "注")))
        document.add(.mosaic(MosaicAnnotationElement(
            points: [CGPoint(x: 80, y: 20), CGPoint(x: 100, y: 40)],
            brushSize: 12
        )))

        let rendered = try AnnotationRenderer().render(image: sourceImage, document: document)

        XCTAssertEqual(rendered.width, 120)
        XCTAssertEqual(rendered.height, 80)
    }

    func testRendererPreservesRetinaPixelDimensions() throws {
        let sourceImage = makeImage(width: 240, height: 160)
        var document = AnnotationDocument()
        document.add(
            .rectangle(
                RectangleAnnotationElement(
                    rect: CGRect(x: 40, y: 32, width: 80, height: 44),
                    style: ScreenshotAnnotationStyle(color: .voxGreen, lineWidth: 4)
                )
            )
        )

        let rendered = try AnnotationRenderer().render(image: sourceImage, document: document)

        XCTAssertEqual(rendered.width, 240)
        XCTAssertEqual(rendered.height, 160)
    }

    func testMosaicChangesOnlyInsideElementBounds() throws {
        let sourceImage = makeGradientImage(width: 80, height: 80)
        var document = AnnotationDocument()
        document.add(.mosaic(MosaicAnnotationElement(
            points: [CGPoint(x: 24, y: 36), CGPoint(x: 48, y: 36)],
            brushSize: 20,
            blockSize: 6
        )))

        let rendered = try AnnotationRenderer().render(image: sourceImage, document: document)

        XCTAssertEqual(pixel(in: rendered, x: 4, y: 4), pixel(in: sourceImage, x: 4, y: 4))
        XCTAssertEqual(pixel(in: rendered, x: 70, y: 70), pixel(in: sourceImage, x: 70, y: 70))
        XCTAssertNotEqual(pixel(in: rendered, x: 31, y: 36), pixel(in: sourceImage, x: 31, y: 36))
        XCTAssertEqual(pixel(in: rendered, x: 31, y: 55), pixel(in: sourceImage, x: 31, y: 55))
    }

    func testMosaicPixelatesSourceImageInsteadOfDrawingTintedOverlay() throws {
        let sourceImage = makeGradientImage(width: 32, height: 32)
        var document = AnnotationDocument()
        document.add(.mosaic(MosaicAnnotationElement(
            points: [CGPoint(x: 16, y: 16), CGPoint(x: 24, y: 16)],
            brushSize: 16,
            blockSize: 8
        )))

        let rendered = try AnnotationRenderer().render(image: sourceImage, document: document)

        XCTAssertEqual(pixel(in: rendered, x: 2, y: 2), pixel(in: sourceImage, x: 2, y: 2))
        XCTAssertEqual(pixel(in: rendered, x: 18, y: 18), pixel(in: sourceImage, x: 16, y: 16))
        XCTAssertEqual(pixel(in: rendered, x: 22, y: 18), pixel(in: sourceImage, x: 16, y: 16))
        XCTAssertNotEqual(pixel(in: rendered, x: 18, y: 18), pixel(in: sourceImage, x: 18, y: 18))
    }

    func testSmallNumberedMarkerRendersVisibleForegroundAndBackground() throws {
        let sourceImage = makeImage(width: 60, height: 60)
        var document = AnnotationDocument()
        document.add(.numberedMarker(NumberedMarkerAnnotationElement(center: CGPoint(x: 30, y: 30), number: 9, radius: 8)))

        let rendered = try AnnotationRenderer().render(image: sourceImage, document: document)
        let sampledPixels = pixels(in: rendered, rect: CGRect(x: 22, y: 22, width: 16, height: 16))

        XCTAssertTrue(sampledPixels.contains { $0.green > $0.red && $0.green > $0.blue })
        XCTAssertTrue(sampledPixels.contains { $0.red > 250 && $0.green > 250 && $0.blue > 250 })
    }

    func testTranslatedOverlayRendersAtOCRTopLeftBounds() throws {
        let sourceImage = makeGradientImage(width: 48, height: 48)
        var document = AnnotationDocument()
        document.add(.translatedOverlay(TranslatedOverlayAnnotationElement(lines: [
            .init(bounds: CGRect(x: 8, y: 6, width: 24, height: 12), text: "译")
        ])))

        let rendered = try AnnotationRenderer().render(image: sourceImage, document: document)

        XCTAssertNotEqual(pixel(in: rendered, x: 10, y: 8), pixel(in: sourceImage, x: 10, y: 8))
        XCTAssertEqual(pixel(in: rendered, x: 10, y: 34), pixel(in: sourceImage, x: 10, y: 34))
    }

    private func makeImage(width: Int, height: Int) -> CGImage {
        let bytesPerPixel = 4
        var data = Data(repeating: 255, count: width * height * bytesPerPixel)
        data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for index in stride(from: 0, to: bytes.count, by: bytesPerPixel) {
                bytes[index] = 245
                bytes[index + 1] = 248
                bytes[index + 2] = 246
                bytes[index + 3] = 255
            }
        }
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private func makeGradientImage(width: Int, height: Int) -> CGImage {
        let bytesPerPixel = 4
        var data = Data(repeating: 255, count: width * height * bytesPerPixel)
        data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for y in 0..<height {
                for x in 0..<width {
                    let index = (y * width + x) * bytesPerPixel
                    bytes[index] = UInt8((x * 7) % 256)
                    bytes[index + 1] = UInt8((y * 9) % 256)
                    bytes[index + 2] = UInt8(((x + y) * 5) % 256)
                    bytes[index + 3] = 255
                }
            }
        }
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private func pixels(in image: CGImage, rect: CGRect) -> [Pixel] {
        let minX = max(0, Int(rect.minX))
        let minY = max(0, Int(rect.minY))
        let maxX = min(image.width, Int(rect.maxX))
        let maxY = min(image.height, Int(rect.maxY))
        return (minY..<maxY).flatMap { y in
            (minX..<maxX).map { x in
                pixel(in: image, x: x, y: y)
            }
        }
    }

    private func pixel(in image: CGImage, x: Int, y: Int) -> Pixel {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        var data = Data(repeating: 0, count: width * height * bytesPerPixel)
        data.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * bytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let index = (y * width + x) * bytesPerPixel
        return Pixel(
            red: data[index],
            green: data[index + 1],
            blue: data[index + 2],
            alpha: data[index + 3]
        )
    }
}

private struct Pixel: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
}
