import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

@MainActor
final class ScreenshotRenderAndSaveServiceTests: XCTestCase {
    func testScreenshotRenderServiceReturnsOriginalImageWhenDocumentIsEmpty() throws {
        let image = makeImage(width: 30, height: 12)

        let rendered = try ScreenshotRenderService().render(originalImage: image, document: AnnotationDocument())

        XCTAssertEqual(rendered.width, 30)
        XCTAssertEqual(rendered.height, 12)
    }

    func testScreenshotRenderServiceRendersAnnotatedDocument() throws {
        let image = makeImage(width: 30, height: 12)
        var document = AnnotationDocument()
        document.add(.dotMarker(DotMarkerAnnotationElement(center: CGPoint(x: 8, y: 8))))

        let rendered = try ScreenshotRenderService().render(originalImage: image, document: document)

        XCTAssertEqual(rendered.width, 30)
        XCTAssertEqual(rendered.height, 12)
    }

    func testSavePanelPresenterKeepsSavePanelBehindAdapter() throws {
        let presenter = CapturingScreenshotSavePanelPresenter()
        let image = makeImage(width: 30, height: 12)

        _ = try presenter.savePNG(image: image)

        XCTAssertEqual(presenter.savedImageWidths, [30])
    }

    func testSavePanelPresenterDefaultNameIncludesTimestampAndShortID() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let timestamp = calendar.date(from: DateComponents(
            year: 2024,
            month: 6,
            day: 20,
            hour: 14,
            minute: 42,
            second: 10
        ))!
        let id = UUID(uuidString: "A1B2C3D4-E5F6-4789-ABCD-1234567890AB")!

        let name = ScreenshotSavePanelPresenter.defaultPNGName(
            timestamp: timestamp,
            id: id,
            timeZone: TimeZone(secondsFromGMT: 8 * 3_600)!
        )

        XCTAssertEqual(name, "VoxFlow截图-20240620-224210-A1B2C3D4.png")
    }

    private func makeImage(width: Int, height: Int) -> CGImage {
        let bytesPerPixel = 4
        let data = Data(repeating: 255, count: width * height * bytesPerPixel)
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
}

private final class CapturingScreenshotSavePanelPresenter: ScreenshotSavePanelPresenting {
    private(set) var savedImageWidths: [Int] = []

    func savePNG(image: CGImage) throws -> Bool {
        savedImageWidths.append(image.width)
        return true
    }
}
