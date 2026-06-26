import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

private final class NonSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

enum ScreenRecordingFrameTiming {
    static func relativePresentationTime(_ presentationTime: CMTime, firstPresentationTime: CMTime) -> CMTime {
        let relative = CMTimeSubtract(presentationTime, firstPresentationTime)
        return relative < .zero ? .zero : relative
    }
}

/// 区域录屏请求。overlay 回传选区后由 coordinator 组装。
struct ScreenRecordingRequest: Equatable, Sendable {
    let displayID: CGDirectDisplayID
    /// 选区所在显示器的全局 frame。
    let displayFrame: CGRect
    /// 选区在全局坐标系中的矩形（必须完全位于单个显示器内）。
    let selectionRect: CGRect
    /// 显示器 backing scale。
    let scale: CGFloat
    /// 音频模式：默认 `.none`，可选 `.microphone`。
    let audioMode: MediaAudioMode
    /// 需要从录制画面中排除的窗口（VoxFlow toolbar/HUD）。
    let excludedWindowIDs: [CGWindowID]

    init(
        displayID: CGDirectDisplayID,
        displayFrame: CGRect,
        selectionRect: CGRect,
        scale: CGFloat,
        audioMode: MediaAudioMode = .none,
        excludedWindowIDs: [CGWindowID] = []
    ) {
        self.displayID = displayID
        self.displayFrame = displayFrame
        self.selectionRect = selectionRect
        self.scale = scale
        self.audioMode = audioMode
        self.excludedWindowIDs = excludedWindowIDs
    }
}

/// 录屏完成元数据，用于持久化与结果 HUD 展示。
struct ScreenRecordingCompletion: Equatable, Sendable {
    let url: URL
    let durationMs: Int
    let width: Int
    let height: Int
    let fileSizeBytes: Int
    let audioMode: MediaAudioMode
    let thumbnailPath: String?
}

enum ScreenRecordingServiceError: Error, LocalizedError {
    case displayNotFound
    case writerSetupFailed(String)
    case writerStartFailed(String)
    case streamStartFailed(String)
    case microphonePermissionDenied
    case finalizeFailed(String)
    case notRunning

    var errorDescription: String? {
        switch self {
        case .displayNotFound: return "找不到目标显示器。"
        case .writerSetupFailed(let r): return "录屏编码器初始化失败：\(r)"
        case .writerStartFailed(let r): return "录屏编码器启动失败：\(r)"
        case .streamStartFailed(let r): return "屏幕采集启动失败：\(r)"
        case .microphonePermissionDenied: return "麦克风权限被拒绝。"
        case .finalizeFailed(let r): return "录屏文件完成失败：\(r)"
        case .notRunning: return "没有正在进行的录屏。"
        }
    }
}

/// 区域录屏服务契约。便于在 coordinator/UI 层用 fake 替换。
protocol ScreenRecordingServicing: AnyObject, Sendable {
    func start(_ request: ScreenRecordingRequest, outputURL: URL) async throws
    func stop() async throws -> ScreenRecordingCompletion
    func cancel() async
    var isRunning: Bool { get }
}

/// 基于 ScreenCaptureKit + AVAssetWriter 的区域录屏实现。
///
/// 采集整个显示器（排除 VoxFlow 窗口），每帧用 CIImage 裁剪到选区像素矩形，
/// 通过 `AVAssetWriterInputPixelBufferAdaptor` 以 H.264 写入 `.mp4`。
/// 无声模式为默认；麦克风模式会请求权限（V1 音频轨道写入需运行时验证）。
/// 该实现涉及 macOS 运行时服务，需手工真实验证（见 tasks 7.6-7.9）。
final class ScreenRecordingService: ScreenRecordingServicing, @unchecked Sendable {
    private let fileStorage: ScreenRecordingFileStorage
    private let queue = DispatchQueue(label: "com.voxflow.screenrecording.service")

    private var stream: SCStream?
    private var streamDelegate: ScreenRecordingStreamDelegate?
    private var videoSink: ScreenRecordingVideoSink?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var outputURL: URL?
    fileprivate var request: ScreenRecordingRequest?
    private var startedAt: Date?
    private var firstSamplePresentationTime: CMTime?
    fileprivate var videoDimensions: (width: Int, height: Int)?
    private var isRunningFlag = false
    private var stopContinuation: CheckedContinuation<ScreenRecordingCompletion, Error>?

    init(fileStorage: ScreenRecordingFileStorage) {
        self.fileStorage = fileStorage
    }

    var isRunning: Bool { isRunningFlag }

    func start(_ request: ScreenRecordingRequest, outputURL: URL) async throws {
        guard !isRunningFlag else { return }
        self.request = request
        self.outputURL = outputURL
        self.startedAt = Date()

        let pixelWidth = codecEven(Int((request.selectionRect.width * request.scale).rounded()))
        let pixelHeight = codecEven(Int((request.selectionRect.height * request.scale).rounded()))
        videoDimensions = (pixelWidth, pixelHeight)

        if request.audioMode == .microphone {
            guard await ensureMicrophonePermission() else {
                throw ScreenRecordingServiceError.microphonePermissionDenied
            }
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw ScreenRecordingServiceError.writerSetupFailed(error.localizedDescription)
        }
        let videoInput = makeVideoInput(width: pixelWidth, height: pixelHeight)
        guard writer.canAdd(videoInput) else {
            throw ScreenRecordingServiceError.writerSetupFailed("无法添加视频输入")
        }
        writer.add(videoInput)
        self.videoInput = videoInput
        if request.audioMode == .microphone {
            let audioInput = makeAudioInput()
            guard writer.canAdd(audioInput) else {
                throw ScreenRecordingServiceError.writerSetupFailed("无法添加麦克风音频输入")
            }
            writer.add(audioInput)
            self.audioInput = audioInput
        }
        self.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: pixelWidth,
                kCVPixelBufferHeightKey as String: pixelHeight
            ]
        )
        self.assetWriter = writer

        guard writer.startWriting() else {
            throw ScreenRecordingServiceError.writerStartFailed(writer.error?.localizedDescription ?? "unknown")
        }
        writer.startSession(atSourceTime: .zero)

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == request.displayID }) else {
            throw ScreenRecordingServiceError.displayNotFound
        }
        let excluded = content.windows.filter { request.excludedWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        let config = SCStreamConfiguration()
        config.sourceRect = request.selectionRect.offsetBy(
            dx: -request.displayFrame.minX,
            dy: -request.displayFrame.minY
        )
        config.width = pixelWidth
        config.height = pixelHeight
        config.showsCursor = true
        config.queueDepth = 5
        config.scalesToFit = false
        config.captureResolution = .best
        config.colorSpaceName = CGColorSpace.sRGB
        config.pixelFormat = kCVPixelFormatType_32BGRA
        if request.audioMode == .microphone {
            config.captureMicrophone = true
        }

        let delegate = ScreenRecordingStreamDelegate { [weak self] error in
            self?.resumeStop(with: .failure(error))
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: delegate)
        self.streamDelegate = delegate

        let sink = ScreenRecordingVideoSink(owner: self)
        try stream.addStreamOutput(sink, type: SCStreamOutputType.screen, sampleHandlerQueue: queue)
        if request.audioMode == .microphone {
            try stream.addStreamOutput(sink, type: SCStreamOutputType.microphone, sampleHandlerQueue: queue)
        }
        self.videoSink = sink
        self.stream = stream
        try await stream.startCapture()
        isRunningFlag = true
    }

    func stop() async throws -> ScreenRecordingCompletion {
        guard isRunningFlag, let request, let outputURL, let startedAt else {
            throw ScreenRecordingServiceError.notRunning
        }
        let capturedDimensions = videoDimensions
        let audioMode = request.audioMode
        return try await withCheckedThrowingContinuation { continuation in
            self.stopContinuation = continuation
            self.finishRecording(
                outputURL: outputURL,
                startedAt: startedAt,
                dimensions: capturedDimensions,
                audioMode: audioMode
            )
        }
    }

    func cancel() async {
        await teardownStream()
        if let outputURL {
            fileStorage.removeTemporary(at: outputURL)
        }
        resetState()
    }

    // MARK: - Setup helpers

    private func makeVideoInput(width: Int, height: Int) -> AVAssetWriterInput {
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        return input
    }

    private func makeAudioInput() -> AVAssetWriterInput {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        return input
    }

    private func codecEven(_ value: Int) -> Int {
        max(2, value - (value % 2))
    }

    private func ensureMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    // MARK: - Sample append

    fileprivate func appendVideoSample(_ sample: CMSampleBuffer) {
        guard let videoInput, videoInput.isReadyForMoreMediaData,
              let adaptor = pixelBufferAdaptor else {
            return
        }
        guard let sourceBuffer = CMSampleBufferGetImageBuffer(sample) else { return }
        let pts = relativePresentationTime(for: sample)
        adaptor.append(sourceBuffer, withPresentationTime: pts)
    }

    fileprivate func appendMicrophoneSample(_ sample: CMSampleBuffer) {
        guard let audioInput, audioInput.isReadyForMoreMediaData,
              let retimed = sampleBufferByRebasingPresentationTime(sample) else { return }
        audioInput.append(retimed)
    }

    // MARK: - Teardown

    private func finishRecording(
        outputURL: URL,
        startedAt: Date,
        dimensions: (width: Int, height: Int)?,
        audioMode: MediaAudioMode
    ) {
        Task {
            await teardownStream()
            guard let assetWriter else {
                resumeStop(with: .failure(ScreenRecordingServiceError.finalizeFailed("writer missing")))
                return
            }
            let writerBox = NonSendableBox(assetWriter)
            assetWriter.finishWriting { [weak self, writerBox] in
                guard let self else { return }
                let assetWriter = writerBox.value
                guard assetWriter.status == .completed else {
                    self.resetState()
                    self.resumeStop(with: .failure(ScreenRecordingServiceError.finalizeFailed(
                        assetWriter.error?.localizedDescription ?? "writer incomplete"
                    )))
                    return
                }
                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                let size = self.fileStorage.fileSize(at: outputURL) ?? 0
                let completion = ScreenRecordingCompletion(
                    url: outputURL,
                    durationMs: durationMs,
                    width: dimensions?.width ?? 0,
                    height: dimensions?.height ?? 0,
                    fileSizeBytes: size,
                    audioMode: audioMode,
                    thumbnailPath: nil
                )
                self.resetState()
                self.resumeStop(with: .success(completion))
            }
        }
    }

    private func teardownStream() async {
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        streamDelegate = nil
        videoSink = nil
    }

    fileprivate func resumeStop(with result: Result<ScreenRecordingCompletion, Error>) {
        guard let continuation = stopContinuation else { return }
        stopContinuation = nil
        switch result {
        case .success(let completion): continuation.resume(returning: completion)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    private func resetState() {
        isRunningFlag = false
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        pixelBufferAdaptor = nil
        request = nil
        outputURL = nil
        startedAt = nil
        videoDimensions = nil
        firstSamplePresentationTime = nil
    }

    private func relativePresentationTime(for sample: CMSampleBuffer) -> CMTime {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sample)
        if firstSamplePresentationTime == nil {
            firstSamplePresentationTime = presentationTime
        }
        return ScreenRecordingFrameTiming.relativePresentationTime(
            presentationTime,
            firstPresentationTime: firstSamplePresentationTime ?? presentationTime
        )
    }

    private func sampleBufferByRebasingPresentationTime(_ sample: CMSampleBuffer) -> CMSampleBuffer? {
        let relativePTS = relativePresentationTime(for: sample)
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sample),
            presentationTimeStamp: relativePTS,
            decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(sample)
        )
        var retimed: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sample,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &retimed
        )
        guard status == noErr else {
            return nil
        }
        return retimed
    }
}

// MARK: - SCStreamDelegate bridge

private final class ScreenRecordingStreamDelegate: NSObject, SCStreamDelegate {
    private let onStop: (Error) -> Void

    init(onStop: @escaping (Error) -> Void) {
        self.onStop = onStop
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        AppLogger.general.error("ScreenRecording stream stopped error=\(error.localizedDescription)")
        onStop(error)
    }
}

// MARK: - Video output sink

private final class ScreenRecordingVideoSink: NSObject, SCStreamOutput {
    private weak var owner: ScreenRecordingService?

    init(owner: ScreenRecordingService) {
        self.owner = owner
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case SCStreamOutputType.screen:
            owner?.appendVideoSample(sample)
        case SCStreamOutputType.microphone:
            owner?.appendMicrophoneSample(sample)
        default:
            break
        }
    }
}
