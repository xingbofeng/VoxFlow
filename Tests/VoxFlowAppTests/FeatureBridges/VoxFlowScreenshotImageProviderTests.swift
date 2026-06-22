import CoreGraphics
import XCTest
import VoxFlowScreenshotKit
@testable import VoxFlowApp

@MainActor
final class VoxFlowScreenshotImageProviderTests: XCTestCase {
    func testCaptureReturnsImageFromScreenshotKitProvider() async throws {
        let image = makeImage(width: 3, height: 2)
        let provider = VoxFlowScreenshotImageProvider(
            screenshotProvider: StubInteractiveScreenshotProvider(result: .success(image))
        )

        let captured = try await provider.captureImage()

        XCTAssertEqual(captured.width, 3)
        XCTAssertEqual(captured.height, 2)
    }

    func testCapturePreservesTextRecognitionCompletionKind() async throws {
        let image = makeImage(width: 3, height: 2)
        let provider = VoxFlowScreenshotImageProvider(
            screenshotProvider: StubInteractiveScreenshotProvider(
                result: .success(
                    InteractiveScreenshotCaptureResult(
                        image: image,
                        completionKind: .textRecognition
                    )
                )
            )
        )

        let captured = try await provider.capture()

        XCTAssertEqual(captured.image.width, 3)
        XCTAssertEqual(captured.image.height, 2)
        XCTAssertEqual(captured.completionKind, .textRecognition)
    }

    func testCapturePreservesScrollingScreenshotCompletionKind() async throws {
        let image = makeImage(width: 3, height: 12)
        let provider = VoxFlowScreenshotImageProvider(
            screenshotProvider: StubInteractiveScreenshotProvider(
                result: .success(
                    InteractiveScreenshotCaptureResult(
                        image: image,
                        completionKind: .scrollingScreenshot
                    )
                )
            )
        )

        let captured = try await provider.capture()

        XCTAssertEqual(captured.image.width, 3)
        XCTAssertEqual(captured.image.height, 12)
        XCTAssertEqual(captured.completionKind, .scrollingScreenshot)
    }

    func testCancellationMapsToScreenshotOCRCancellation() async {
        let provider = VoxFlowScreenshotImageProvider(
            screenshotProvider: StubInteractiveScreenshotProvider(
                result: Result<InteractiveScreenshotCaptureResult, Error>
                    .failure(InteractiveScreenshotError.cancelled)
            )
        )

        do {
            _ = try await provider.captureImage()
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? ScreenshotOCRServiceError, .captureCancelled)
        }
    }

    func testFailureMapsToScreenshotOCRCaptureFailed() async {
        let provider = VoxFlowScreenshotImageProvider(
            screenshotProvider: StubInteractiveScreenshotProvider(
                result: Result<InteractiveScreenshotCaptureResult, Error>
                    .failure(InteractiveScreenshotError.captureFailed("boom"))
            )
        )

        do {
            _ = try await provider.captureImage()
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(error as? ScreenshotOCRServiceError, .captureFailed("boom"))
        }
    }

}

private final class StubInteractiveScreenshotProvider: InteractiveScreenshotProviding {
    private let result: Result<InteractiveScreenshotCaptureResult, Error>

    init(result: Result<CGImage, Error>) {
        self.result = result.map { InteractiveScreenshotCaptureResult(image: $0) }
    }

    init(result: Result<InteractiveScreenshotCaptureResult, Error>) {
        self.result = result
    }

    func captureImage() async throws -> CGImage {
        try await capture().image
    }

    func capture() async throws -> InteractiveScreenshotCaptureResult {
        try result.get()
    }
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
