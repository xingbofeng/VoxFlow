import AVFoundation
import AppKit
import CoreGraphics
import CoreText
import Foundation
import QuartzCore

/// 字幕烧录错误。
enum RecordingSubtitleBurnError: Error, Equatable, LocalizedError {
    case exportFailed(String)
    case outputMissing
    case invalidSource(String)

    var errorDescription: String? {
        switch self {
        case .exportFailed(let reason):
            return L10n.format("subtitle.error.burn_failed_format", comment: "", reason)
        case .outputMissing:
            return L10n.localize("subtitle.error.burn_output_missing", comment: "")
        case .invalidSource(let reason):
            return L10n.format("subtitle.error.invalid_source_format", comment: "", reason)
        }
    }
}

/// 烧录结果。
struct RecordingSubtitleBurnResult: Equatable, Sendable {
    let outputURL: URL
}

/// 字幕烧录器协议：输入原视频、字幕草稿和输出路径，输出带字幕新 mp4。
///
/// V1 使用 AVFoundation/Core Animation overlay；测试中可注入 fake 实现。
protocol RecordingSubtitleBurner: Sendable {
    func burn(
        sourceVideoURL: URL,
        draft: RecordingSubtitleDraft,
        outputURL: URL
    ) async throws -> RecordingSubtitleBurnResult
}

/// 基于 AVFoundation + Core Animation overlay 的烧录实现。
///
/// 固定 V1 样式：底部居中、白字半粗体、黑色半透明圆角底、最多两行、左右 8% 安全区。
/// 导出先写入临时文件，成功后原子移动到最终路径；失败或取消删除半成品，绝不覆盖原视频。
final class LiveRecordingSubtitleBurner: RecordingSubtitleBurner {
    func burn(
        sourceVideoURL: URL,
        draft: RecordingSubtitleDraft,
        outputURL: URL
    ) async throws -> RecordingSubtitleBurnResult {
        let fileManager = FileManager.default
        let asset = AVURLAsset(url: sourceVideoURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw RecordingSubtitleBurnError.invalidSource(
                L10n.localize("subtitle.error.missing_video_track", comment: "")
            )
        }
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let compositionSize = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform).size

        let composition = AVMutableComposition()
        let compositionVideoTrack = try await Self.insertTracks(from: asset, into: composition)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = compositionSize
        let overlayLayer = Self.makeOverlayLayer(for: draft, size: compositionSize)
        let videoLayers = Self.makeVideoLayers(size: compositionSize, overlayLayer: overlayLayer)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayers.videoLayer,
            in: videoLayers.parentLayer
        )

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: CMTime.zero, duration: composition.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        // 导出先到临时文件，成功后原子移动；失败删除半成品。
        let tempOutputURL = outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(outputURL.lastPathComponent).tmp-\(UUID().uuidString)")
        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw RecordingSubtitleBurnError.exportFailed(
                L10n.localize("subtitle.error.export_session_create_failed", comment: "")
            )
        }
        session.videoComposition = videoComposition
        session.outputURL = tempOutputURL
        session.outputFileType = .mp4

        do {
            try await session.export(to: tempOutputURL, as: .mp4)
        } catch {
            try? fileManager.removeItem(at: tempOutputURL)
            throw RecordingSubtitleBurnError.exportFailed(error.localizedDescription)
        }

        guard fileManager.fileExists(atPath: tempOutputURL.path) else {
            throw RecordingSubtitleBurnError.outputMissing
        }

        do {
            if fileManager.fileExists(atPath: outputURL.path) {
                try fileManager.removeItem(at: outputURL)
            }
            try fileManager.moveItem(at: tempOutputURL, to: outputURL)
        } catch {
            try? fileManager.removeItem(at: tempOutputURL)
            throw RecordingSubtitleBurnError.exportFailed(
                L10n.format("subtitle.error.export_subtitled_video_failed_format", comment: "", error.localizedDescription)
            )
        }

        return RecordingSubtitleBurnResult(outputURL: outputURL)
    }

    // MARK: - Composition 构建

    private static func insertTracks(
        from asset: AVURLAsset,
        into composition: AVMutableComposition
    ) async throws -> AVMutableCompositionTrack {
        let duration = try await asset.load(.duration)
        var compositionVideoTrack: AVMutableCompositionTrack?
        let mediaTypes: [AVMediaType] = [.video, .audio]
        for mediaType in mediaTypes {
            let tracks = try await asset.loadTracks(withMediaType: mediaType)
            for track in tracks {
                guard let compositionTrack = composition.addMutableTrack(
                    withMediaType: mediaType,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { continue }
                let timeRange = CMTimeRange(start: CMTime.zero, duration: duration)
                try compositionTrack.insertTimeRange(timeRange, of: track, at: CMTime.zero)
                compositionTrack.preferredTransform = try await track.load(.preferredTransform)
                if mediaType == .video, compositionVideoTrack == nil {
                    compositionVideoTrack = compositionTrack
                }
            }
        }
        guard let compositionVideoTrack else {
            throw RecordingSubtitleBurnError.invalidSource(
                L10n.localize("subtitle.error.missing_video_track", comment: "")
            )
        }
        return compositionVideoTrack
    }

    // MARK: - V1 固定样式 overlay

    /// 构建字幕 overlay 层：每个段在自身时间窗口内显示，其余时间不可见。
    static func makeOverlayLayer(for draft: RecordingSubtitleDraft, size: CGSize) -> CALayer {
        let overlay = CALayer()
        overlay.frame = CGRect(origin: .zero, size: size)
        overlay.isGeometryFlipped = true

        let fontSize = max(18, round(size.height * 0.05))
        let horizontalMargin = size.width * RecordingSubtitleStyle.horizontalSafeMarginRatio
        let maxWidth = size.width - horizontalMargin * 2
        let bottomMargin = size.height * RecordingSubtitleStyle.bottomRatio

        for segment in draft.segments {
            let subtitleText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !subtitleText.isEmpty else { continue }

            let background = CALayer()
            background.name = "subtitleBackground"
            background.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
            background.cornerRadius = fontSize * 0.35

            let textSize = Self.textSize(
                string: subtitleText,
                font: NSFont.boldSystemFont(ofSize: fontSize),
                maxWidth: maxWidth,
                maxLines: RecordingSubtitleStyle.maxLines
            )
            let padding = fontSize * 0.5
            let backgroundWidth = min(maxWidth, textSize.width + padding * 2)
            let backgroundHeight = min(size.height * 0.4, textSize.height + padding)
            let backgroundX = (size.width - backgroundWidth) / 2
            let backgroundY = size.height - bottomMargin - backgroundHeight

            background.frame = CGRect(
                x: backgroundX,
                y: backgroundY,
                width: backgroundWidth,
                height: backgroundHeight
            )
            let textFrame = CGRect(
                x: backgroundX + padding,
                y: backgroundY + (backgroundHeight - textSize.height) / 2,
                width: backgroundWidth - padding * 2,
                height: textSize.height
            )
            let textLayer = Self.makeTextShapeLayer(
                string: subtitleText,
                font: NSFont.boldSystemFont(ofSize: fontSize),
                size: textFrame.size
            )
            textLayer.name = "subtitleText"
            textLayer.frame = textFrame
            overlay.addSublayer(background)
            overlay.addSublayer(textLayer)

            // 默认不可见，仅在段时间窗口内显示。
            background.opacity = 0
            textLayer.opacity = 0
            let startSeconds = max(0, Double(segment.startMS)) / 1_000
            let durationSeconds = max(0, Double(segment.endMS - segment.startMS)) / 1_000
            background.add(
                Self.subtitleVisibilityAnimation(startSeconds: startSeconds, durationSeconds: durationSeconds),
                forKey: "subtitleVisibility"
            )
            textLayer.add(
                Self.subtitleVisibilityAnimation(startSeconds: startSeconds, durationSeconds: durationSeconds),
                forKey: "subtitleVisibility"
            )
        }
        return overlay
    }

    private static func makeTextShapeLayer(string: String, font: NSFont, size: CGSize) -> CAShapeLayer {
        let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributed = NSAttributedString(
            string: string,
            attributes: [
                kCTFontAttributeName as NSAttributedString.Key: ctFont,
                .paragraphStyle: paragraphStyle
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let framePath = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributed.length),
            framePath,
            nil
        )
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        var origins = Array(repeating: CGPoint.zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        let glyphPath = CGMutablePath()
        for (lineIndex, line) in lines.prefix(RecordingSubtitleStyle.maxLines).enumerated() {
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let lineX = max(0, (size.width - lineWidth) / 2)
            let lineOrigin = origins[lineIndex]
            let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
            for run in runs {
                let glyphCount = CTRunGetGlyphCount(run)
                var glyphs = Array(repeating: CGGlyph(), count: glyphCount)
                var positions = Array(repeating: CGPoint.zero, count: glyphCount)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                let attributes = CTRunGetAttributes(run) as NSDictionary
                let runFont = attributes[kCTFontAttributeName] as! CTFont
                for index in 0..<glyphCount {
                    guard let path = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) else { continue }
                    let transform = CGAffineTransform(
                        a: 1,
                        b: 0,
                        c: 0,
                        d: -1,
                        tx: lineX + positions[index].x,
                        ty: size.height - lineOrigin.y + positions[index].y
                    )
                    glyphPath.addPath(path, transform: transform)
                }
            }
        }

        let shapeLayer = CAShapeLayer()
        shapeLayer.path = glyphPath
        shapeLayer.fillColor = NSColor.white.cgColor
        shapeLayer.contentsScale = 2
        return shapeLayer
    }

    private static func subtitleVisibilityAnimation(startSeconds: Double, durationSeconds: Double) -> CAKeyframeAnimation {
        let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnimation.values = [1.0, 1.0]
        opacityAnimation.keyTimes = [0, 1]
        opacityAnimation.beginTime = startSeconds
        opacityAnimation.duration = durationSeconds
        opacityAnimation.calculationMode = .discrete
        return opacityAnimation
    }

    private struct VideoLayers {
        let videoLayer: CALayer
        let parentLayer: CALayer
    }

    private static func makeVideoLayers(size: CGSize, overlayLayer: CALayer) -> VideoLayers {
        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: size)
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: size)
        parent.addSublayer(videoLayer)
        parent.addSublayer(overlayLayer)
        return VideoLayers(videoLayer: videoLayer, parentLayer: parent)
    }

    /// 估算字幕文本尺寸：限制最大行数与宽度。
    static func textSize(string: String, font: NSFont, maxWidth: CGFloat, maxLines: Int) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let boundingRect = (string as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let lineHeight = font.boundingRectForFont.height
        let cappedHeight = min(boundingRect.height, lineHeight * CGFloat(maxLines))
        let width = min(maxWidth, ceil(boundingRect.width))
        return CGSize(width: max(width, 1), height: max(ceil(cappedHeight), lineHeight))
    }
}
