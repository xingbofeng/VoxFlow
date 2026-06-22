import CoreGraphics
@preconcurrency import ScreenCaptureKit
import XCTest
@testable import VoxFlowScreenshotKit

final class ScreenCaptureFrameProviderTests: XCTestCase {
    func testAvailableDisplaysUsesInjectedDisplayLoader() async throws {
        let displays = [
            ScreenshotDisplay(
                id: 1,
                name: "Built-in Display",
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                scale: 2,
                isPrimary: true
            )
        ]
        let provider = ScreenCaptureFrameProvider(
            displayLoader: { displays },
            displayCapture: { _, _ in Self.makeImage(width: 1, height: 1) }
        )

        let loadedDisplays = try await provider.availableDisplays()

        XCTAssertEqual(loadedDisplays, displays)
    }

    func testCaptureDisplayPassesExcludedWindowIDsToInjectedCapture() async throws {
        let display = ScreenshotDisplay(
            id: 2,
            name: "External",
            frame: CGRect(x: 1440, y: 0, width: 800, height: 600),
            scale: 1,
            isPrimary: false
        )
        var capturedDisplay: ScreenshotDisplay?
        var capturedExcludedWindowIDs: [CGWindowID] = []
        let provider = ScreenCaptureFrameProvider(
            displayLoader: { [display] },
            displayCapture: { display, excludedWindowIDs in
                capturedDisplay = display
                capturedExcludedWindowIDs = excludedWindowIDs
                return Self.makeImage(width: 2, height: 3)
            },
            excludedWindowIDs: { [42, 99] }
        )

        let image = try await provider.captureDisplay(display)

        XCTAssertEqual(capturedDisplay, display)
        XCTAssertEqual(capturedExcludedWindowIDs, [42, 99])
        XCTAssertEqual(image.width, 2)
        XCTAssertEqual(image.height, 3)
    }

    func testPermissionFailureUsesTypedProviderError() async {
        let display = ScreenshotDisplay(
            id: 3,
            name: "Denied",
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            scale: 1,
            isPrimary: true
        )
        let provider = ScreenCaptureFrameProvider(
            displayLoader: { [display] },
            displayCapture: { _, _ in throw ScreenCaptureFrameProviderError.permissionDenied }
        )

        do {
            _ = try await provider.captureDisplay(display)
            XCTFail("Expected permissionDenied")
        } catch let error as ScreenCaptureFrameProviderError {
            XCTAssertEqual(error, .permissionDenied)
        } catch {
            XCTFail("Expected ScreenCaptureFrameProviderError, got \(error)")
        }
    }

    func testWindowExclusionUsesExplicitWindowIDsWithoutHidingWholeVoxFlowApp() {
        XCTAssertFalse(ScreenCaptureFrameProvider.shouldExcludeWindow(
            windowID: 7,
            owningBundleIdentifier: "com.voxflow.app",
            excludedWindowIDs: [],
            ownBundleIdentifier: "com.voxflow.app"
        ))
        XCTAssertTrue(ScreenCaptureFrameProvider.shouldExcludeWindow(
            windowID: 42,
            owningBundleIdentifier: "com.other.app",
            excludedWindowIDs: [42],
            ownBundleIdentifier: "com.voxflow.app"
        ))
        XCTAssertFalse(ScreenCaptureFrameProvider.shouldExcludeWindow(
            windowID: 11,
            owningBundleIdentifier: "com.other.app",
            excludedWindowIDs: [42],
            ownBundleIdentifier: "com.voxflow.app"
        ))
    }

    func testCaptureConfigurationMatchesShotShotScaleAndResolutionSettings() {
        let display = ScreenshotDisplay(
            id: 4,
            name: "Retina",
            frame: CGRect(x: 0, y: 0, width: 1200, height: 800),
            scale: 2,
            isPrimary: true
        )

        let configuration = ScreenCaptureFrameProvider.captureConfiguration(for: display)

        XCTAssertEqual(configuration.width, 2400)
        XCTAssertEqual(configuration.height, 1600)
        XCTAssertFalse(configuration.showsCursor)
        XCTAssertFalse(configuration.scalesToFit)
        XCTAssertEqual(configuration.captureResolution, .best)
    }

    private static func makeImage(width: Int, height: Int) -> CGImage {
        let bytesPerPixel = 4
        let data = Data(repeating: 0, count: width * height * bytesPerPixel)
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
