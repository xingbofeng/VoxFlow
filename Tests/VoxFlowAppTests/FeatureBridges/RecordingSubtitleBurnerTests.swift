import AVFoundation
import XCTest
@testable import VoxFlowApp

final class RecordingSubtitleBurnerTests: XCTestCase {
    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    // MARK: - 4.3 协议可注入

    func testBurnerProtocolIsInjectableViaFake() async throws {
        let burner = StubBurner(resultURL: URL(fileURLWithPath: "/tmp/out.mp4"))
        let draft = RecordingSubtitleDraft(
            mediaRecordID: "rec",
            sourceVideoPath: "/tmp/rec.mp4",
            segments: [RecordingSubtitleSegment(startMS: 0, endMS: 1_000, text: "hi")],
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        let result = try await burner.burn(
            sourceVideoURL: URL(fileURLWithPath: "/tmp/rec.mp4"),
            draft: draft,
            outputURL: URL(fileURLWithPath: "/tmp/out.mp4")
        )
        XCTAssertEqual(result.outputURL.path, "/tmp/out.mp4")
    }

    // MARK: - 4.4 overlay 固定 V1 样式

    func testOverlayLayerAppliesFixedV1Style() {
        let draft = RecordingSubtitleDraft(
            mediaRecordID: "rec",
            sourceVideoPath: "/tmp/rec.mp4",
            segments: [
                RecordingSubtitleSegment(id: "s1", startMS: 0, endMS: 1_000, text: "第一句字幕"),
                RecordingSubtitleSegment(id: "s2", startMS: 1_000, endMS: 2_000, text: "第二句字幕")
            ],
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        let size = CGSize(width: 1280, height: 720)
        let overlay = LiveRecordingSubtitleBurner.makeOverlayLayer(for: draft, size: size)

        // 两个字幕段 → 两个背景层 + 两个文字层。
        XCTAssertEqual(overlay.sublayers?.filter { $0.name == "subtitleBackground" }.count, 2)
        XCTAssertEqual(overlay.sublayers?.filter { $0.name == "subtitleText" }.count, 2)

        guard let background = overlay.sublayers?.first(where: { $0.name == "subtitleBackground" }),
              let textLayer = overlay.sublayers?.first(where: { $0.name == "subtitleText" }) as? CAShapeLayer else {
            XCTFail("overlay 结构不符合 videoLayer + 文本层")
            return
        }
        // 白字、半粗体、默认不可见。
        XCTAssertEqual(textLayer.fillColor, NSColor.white.cgColor)
        XCTAssertNotNil(textLayer.path)
        XCTAssertEqual(background.opacity, 0, "字幕段默认不可见，仅在时间窗口内显示")
        XCTAssertEqual(textLayer.opacity, 0, "字幕文字默认不可见，仅在时间窗口内显示")
        XCTAssertNotNil(background.animation(forKey: "subtitleVisibility"))
        XCTAssertNotNil(textLayer.animation(forKey: "subtitleVisibility"))

        // 底部居中：overlay 使用 flipped geometry，y 需要换算成距底部约 8% 高度。
        let bottomMargin = size.height * RecordingSubtitleStyle.bottomRatio
        let expectedY = size.height - bottomMargin - background.frame.height
        XCTAssertEqual(background.frame.origin.y, expectedY, accuracy: 1)
        let centeredX = (size.width - background.frame.width) / 2
        XCTAssertEqual(background.frame.origin.x, centeredX, accuracy: 1)
    }

    func testTextSizeRespectsMaxLinesAndSafeMargins() {
        let size = LiveRecordingSubtitleBurner.textSize(
            string: "一段较长的字幕文本用于验证换行与最大行数限制",
            font: NSFont.boldSystemFont(ofSize: 36),
            maxWidth: 400,
            maxLines: RecordingSubtitleStyle.maxLines
        )
        let lineCap = NSFont.boldSystemFont(ofSize: 36).boundingRectForFont.height * CGFloat(RecordingSubtitleStyle.maxLines)
        XCTAssertLessThanOrEqual(size.height, lineCap + 1)
        XCTAssertLessThanOrEqual(size.width, 400)
    }

    func testOverlayLayerSkipsBlankSubtitleSegments() {
        let draft = RecordingSubtitleDraft(
            mediaRecordID: "rec",
            sourceVideoPath: "/tmp/rec.mp4",
            segments: [
                RecordingSubtitleSegment(id: "blank", startMS: 0, endMS: 1_000, text: "   \n"),
                RecordingSubtitleSegment(id: "text", startMS: 1_000, endMS: 2_000, text: "  有效字幕  ")
            ],
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )

        let overlay = LiveRecordingSubtitleBurner.makeOverlayLayer(for: draft, size: CGSize(width: 1280, height: 720))

        XCTAssertEqual(
            overlay.sublayers?.filter { $0.name == "subtitleBackground" }.count,
            1,
            "空白字幕段不应烧出只有背景的黑块"
        )
        XCTAssertEqual(overlay.sublayers?.filter { $0.name == "subtitleText" }.count, 1)
        let textLayer = overlay.sublayers?.first(where: { $0.name == "subtitleText" }) as? CAShapeLayer
        XCTAssertNotNil(textLayer?.path)
    }

    func testBurnedVideoPreservesSourceVideoFrames() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingSubtitleBurnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let sourceURL = temporaryDirectory.appendingPathComponent("source.mp4")
        let outputURL = temporaryDirectory.appendingPathComponent("subtitled.mp4")
        try Self.makeSolidColorVideo(url: sourceURL, size: CGSize(width: 160, height: 90))

        let draft = RecordingSubtitleDraft(
            mediaRecordID: "rec",
            sourceVideoPath: sourceURL.path,
            segments: [RecordingSubtitleSegment(startMS: 100, endMS: 900, text: "测试字幕")],
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )

        _ = try await LiveRecordingSubtitleBurner().burn(
            sourceVideoURL: sourceURL,
            draft: draft,
            outputURL: outputURL
        )

        let sourceBrightness = try await Self.averageFrameBrightness(url: sourceURL, at: 0.5)
        let outputBrightness = try await Self.averageFrameBrightness(url: outputURL, at: 0.5)
        XCTAssertGreaterThan(sourceBrightness, 40)
        XCTAssertGreaterThan(
            outputBrightness,
            40,
            "烧录后的视频必须保留原视频画面，不能导出为黑屏。"
        )
    }

    func testBurnedVideoRendersVisibleSubtitleText() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingSubtitleBurnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let sourceURL = temporaryDirectory.appendingPathComponent("source.mp4")
        let outputURL = temporaryDirectory.appendingPathComponent("subtitled.mp4")
        try Self.makeSolidColorVideo(url: sourceURL, size: CGSize(width: 320, height: 180))

        let draft = RecordingSubtitleDraft(
            mediaRecordID: "rec",
            sourceVideoPath: sourceURL.path,
            segments: [RecordingSubtitleSegment(startMS: 100, endMS: 900, text: "字幕文字")],
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )

        _ = try await LiveRecordingSubtitleBurner().burn(
            sourceVideoURL: sourceURL,
            draft: draft,
            outputURL: outputURL
        )

        let sourceWhitePixels = try await Self.whitePixelCount(url: sourceURL, at: 0.5)
        let outputWhitePixels = try await Self.whitePixelCount(url: outputURL, at: 0.5)
        XCTAssertGreaterThan(
            outputWhitePixels,
            sourceWhitePixels + 20,
            "烧录结果必须包含可见白色字幕文字，不能只有黑色字幕底板。"
        )
    }

    // MARK: - 源码断言：AVFoundation + Core Animation overlay + 固定样式常量

    func testBurnerSourceUsesAVFoundationCoreAnimationAndFixedStyle() throws {
        let source = try String(
            contentsOf: repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/FeatureBridges/RecordingSubtitleBurner.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("AVMutableVideoComposition"))
        XCTAssertTrue(source.contains("AVVideoCompositionCoreAnimationTool"))
        XCTAssertTrue(source.contains("AVMutableComposition"))
        XCTAssertTrue(source.contains("CAShapeLayer"))
        XCTAssertTrue(source.contains("CAKeyframeAnimation(keyPath: \"opacity\")"))
        XCTAssertTrue(
            source.contains("d: -1"),
            "CoreText glyph path 是 y-up 坐标，加入 Core Animation layer 前必须翻转 y 轴，避免字幕倒置。"
        )
        XCTAssertTrue(source.contains("NSColor.white.cgColor"))
        XCTAssertTrue(source.contains("NSColor.black.withAlphaComponent"))
        XCTAssertTrue(source.contains("RecordingSubtitleStyle.bottomRatio"))
        XCTAssertTrue(source.contains("RecordingSubtitleStyle.horizontalSafeMarginRatio"))
        XCTAssertTrue(source.contains("RecordingSubtitleStyle.maxLines"))
        // 原子移动：先写临时文件再 moveItem。
        XCTAssertTrue(source.contains("moveItem(at: tempOutputURL, to: outputURL)"))
        XCTAssertTrue(source.contains("removeItem(at: tempOutputURL)"))
        XCTAssertTrue(source.contains("AVAssetExportPresetHighestQuality"))
    }

    private static func makeSolidColorVideo(url: URL, size: CGSize) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.001)
            }
            guard let buffer = Self.makePixelBuffer(size: size) else {
                throw RecordingSubtitleBurnError.invalidSource("无法创建测试视频帧")
            }
            let time = CMTime(value: CMTimeValue(frame), timescale: 30)
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: time))
        }

        input.markAsFinished()
        let finishSemaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            finishSemaphore.signal()
        }
        finishSemaphore.wait()
        if let error = writer.error {
            throw error
        }
    }

    private static func makePixelBuffer(size: CGSize) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let context = CGContext(
            data: baseAddress,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        context?.setFillColor(NSColor.systemTeal.cgColor)
        context?.fill(CGRect(origin: .zero, size: size))
        return pixelBuffer
    }

    private static func averageFrameBrightness(url: URL, at seconds: Double) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
            generator.generateCGImageAsynchronously(for: CMTime(seconds: seconds, preferredTimescale: 600)) { image, _, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(
                        throwing: error ?? RecordingSubtitleBurnError.invalidSource("无法读取测试视频帧")
                    )
                }
            }
        }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RecordingSubtitleBurnError.invalidSource("无法读取测试视频帧")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var total: Double = 0
        var count = 0
        let stride = max(1, (width * height) / 20_000)
        var index = 0
        while index < width * height {
            let offset = index * 4
            total += (Double(bytes[offset]) + Double(bytes[offset + 1]) + Double(bytes[offset + 2])) / 3
            count += 1
            index += stride
        }
        return total / Double(count)
    }

    private static func whitePixelCount(url: URL, at seconds: Double) async throws -> Int {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
            generator.generateCGImageAsynchronously(for: CMTime(seconds: seconds, preferredTimescale: 600)) { image, _, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(
                        throwing: error ?? RecordingSubtitleBurnError.invalidSource("无法读取测试视频帧")
                    )
                }
            }
        }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RecordingSubtitleBurnError.invalidSource("无法读取测试视频帧")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for index in 0..<(width * height) {
            let offset = index * 4
            if bytes[offset] > 210, bytes[offset + 1] > 210, bytes[offset + 2] > 210 {
                count += 1
            }
        }
        return count
    }
}

// MARK: - Stub

private final class StubBurner: RecordingSubtitleBurner, @unchecked Sendable {
    private let resultURL: URL
    init(resultURL: URL) { self.resultURL = resultURL }
    func burn(sourceVideoURL: URL, draft: RecordingSubtitleDraft, outputURL: URL) async throws -> RecordingSubtitleBurnResult {
        RecordingSubtitleBurnResult(outputURL: resultURL)
    }
}
