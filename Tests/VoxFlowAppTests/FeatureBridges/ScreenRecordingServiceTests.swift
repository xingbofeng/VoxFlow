import CoreGraphics
import CoreMedia
import XCTest
@testable import VoxFlowApp

final class ScreenRecordingServiceTests: XCTestCase {
    func testRequestDefaultsToNoAudioMode() {
        let request = ScreenRecordingRequest(
            displayID: 1,
            displayFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            selectionRect: CGRect(x: 100, y: 100, width: 320, height: 240),
            scale: 2
        )

        XCTAssertEqual(request.audioMode, .none)
        XCTAssertTrue(request.excludedWindowIDs.isEmpty)
    }

    func testMicrophoneModeConfiguresMicrophoneCaptureAndAudioWriter() throws {
        let source = try String(
            contentsOfFile: "\(FileManager.default.currentDirectoryPath)/Sources/VoxFlowApp/FeatureBridges/ScreenRecordingService.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("config.captureMicrophone = true"))
        XCTAssertTrue(source.contains("SCStreamOutputType.microphone"))
        XCTAssertTrue(source.contains("AVAssetWriterInput(mediaType: .audio"))
        XCTAssertTrue(source.contains("audioInput.append(retimed)"))
    }

    func testRecordingUsesScreenCaptureSourceRectInsteadOfManualFullScreenCrop() throws {
        let source = try String(
            contentsOfFile: "\(FileManager.default.currentDirectoryPath)/Sources/VoxFlowApp/FeatureBridges/ScreenRecordingService.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("config.sourceRect = request.selectionRect.offsetBy"))
        XCTAssertTrue(source.contains("config.width = pixelWidth"))
        XCTAssertTrue(source.contains("config.height = pixelHeight"))
        XCTAssertTrue(source.contains("config.scalesToFit = false"))
        XCTAssertFalse(source.contains("ciImage.cropped"))
    }

    func testSamplePresentationTimesAreRebasedToZero() {
        let first = CMTime(seconds: 1_080_000, preferredTimescale: 600)
        let next = CMTime(seconds: 1_080_002.5, preferredTimescale: 600)

        XCTAssertEqual(
            ScreenRecordingFrameTiming.relativePresentationTime(first, firstPresentationTime: first),
            .zero
        )
        XCTAssertEqual(
            ScreenRecordingFrameTiming.relativePresentationTime(next, firstPresentationTime: first),
            CMTime(seconds: 2.5, preferredTimescale: 600)
        )
    }
}
