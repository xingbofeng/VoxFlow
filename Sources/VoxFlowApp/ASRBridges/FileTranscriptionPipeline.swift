import Foundation
@preconcurrency import AVFoundation

/// 文件转写 pipeline 的段级进度更新（OpenSpec revamp-file-transcription-and-notes §2）。
struct PipelineSegmentUpdate: Sendable, Equatable {
    let index: Int
    let startMS: Int
    let endMS: Int
    let status: TranscriptionSegmentStatus
    let text: String?
    let fallbackReason: SegmentFallbackReason?
    let retryCount: Int
    let providerID: String?
    let providerMode: TranscriptionProviderMode
    let error: String?
}

/// 文件转写 pipeline 协议。负责按 provider 能力选择原生文件 API 或 VoxFlow 分段 worker，
/// 并通过 `onSegment` 回调报告段级进度，供 ViewModel 持久化和 UI 展示。
protocol FileTranscriptionPipeline: Sendable {
    func transcribe(
        fileURL: URL,
        asrProviderID: String?,
        locale: Locale,
        existingSegments: [TranscriptionSegmentRecord],
        onSegment: @escaping @Sendable (PipelineSegmentUpdate) -> Void,
        progress: @escaping @Sendable (Double, Int, Int) -> Void
    ) async throws -> FileTranscriptionResult
}

/// 原生文件转写能力。Groq 等支持 `transcribeFile` 的 provider 通过此协议注入。
protocol NativeFileTranscribing: Sendable {
    func transcribeFile(
        _ fileURL: URL,
        asrProviderID: String,
        locale: Locale,
        prompt: String?
    ) async throws -> FileTranscriptionResult
}

/// 默认 window 长度（毫秒）。贴近 OpenAI Whisper long-form 的 30 秒窗口。
enum FileTranscriptionPipelineConstants {
    static let windowLengthMS: Int = 30_000
    /// 窗口之间的 overlap（毫秒），用于 overlap 去重。
    static let overlapMS: Int = 1_500
    /// 单段最大重试次数。
    static let maxRetryCount: Int = 2
    /// 单段超时秒数。
    static let segmentTimeoutSeconds: Double = 60
}

/// VoxFlow 文件转写 pipeline 默认实现。
///
/// 调度顺序：
/// 1. 若 provider 为 `nativeFile` 且无已有分段：尝试原生文件 API 转写整段。
///    成功则返回单段结果；失败则降级到分段 worker。
/// 2. 分段 worker：按约 30 秒窗口切分音频，顺序处理，携带前文上下文 prompt，
///    失败重试，最后做 overlap 去重并合并。
final class VoxFlowFileTranscriptionPipeline: FileTranscriptionPipeline, @unchecked Sendable {
    private let makeSegmentWorker: (Locale) -> any FileTranscriptionWorking
    private let nativeFileTranscriber: NativeFileTranscribing?
    private let windowLengthMS: Int
    private let overlapMS: Int
    private let maxRetryCount: Int

    init(
        makeSegmentWorker: @escaping (Locale) -> any FileTranscriptionWorking,
        nativeFileTranscriber: NativeFileTranscribing? = nil,
        windowLengthMS: Int = FileTranscriptionPipelineConstants.windowLengthMS,
        overlapMS: Int = FileTranscriptionPipelineConstants.overlapMS,
        maxRetryCount: Int = FileTranscriptionPipelineConstants.maxRetryCount
    ) {
        self.makeSegmentWorker = makeSegmentWorker
        self.nativeFileTranscriber = nativeFileTranscriber
        self.windowLengthMS = windowLengthMS
        self.overlapMS = overlapMS
        self.maxRetryCount = maxRetryCount
    }

    func transcribe(
        fileURL: URL,
        asrProviderID: String?,
        locale: Locale,
        existingSegments: [TranscriptionSegmentRecord],
        onSegment: @escaping @Sendable (PipelineSegmentUpdate) -> Void,
        progress: @escaping @Sendable (Double, Int, Int) -> Void
    ) async throws -> FileTranscriptionResult {
        let capability = FileTranscriptionCapabilityResolver.resolve(providerID: asrProviderID)
        let providerMode = pipelineProviderMode(for: capability)

        // 1. 原生文件路径：无已有分段时尝试整段转写。
        if capability == .nativeFile,
           let nativeFileTranscriber,
           existingSegments.allSatisfy({ $0.status == TranscriptionSegmentStatus.completed.rawValue }) {
            do {
                let result = try await nativeFileTranscriber.transcribeFile(
                    fileURL,
                    asrProviderID: asrProviderID ?? "",
                    locale: locale,
                    prompt: nil
                )
                let durationMS = max(result.durationMS, 1)
                onSegment(
                    PipelineSegmentUpdate(
                        index: 0,
                        startMS: 0,
                        endMS: durationMS,
                        status: .completed,
                        text: result.text,
                        fallbackReason: nil,
                        retryCount: 0,
                        providerID: asrProviderID,
                        providerMode: .nativeFile,
                        error: nil
                    )
                )
                progress(1, 1, 1)
                return result
            } catch {
                // 原生文件失败，降级到分段 worker。
                AppLogger.general.warning(
                    "原生文件转写失败，降级到分段 worker：\(error.localizedDescription)"
                )
            }
        }

        // 2. 分段 worker。
        return try await transcribeSegmented(
            fileURL: fileURL,
            asrProviderID: asrProviderID,
            locale: locale,
            providerMode: providerMode,
            existingSegments: existingSegments,
            onSegment: onSegment,
            progress: progress
        )
    }

    // MARK: - Segmented

    private func transcribeSegmented(
        fileURL: URL,
        asrProviderID: String?,
        locale: Locale,
        providerMode: TranscriptionProviderMode,
        existingSegments: [TranscriptionSegmentRecord],
        onSegment: @escaping @Sendable (PipelineSegmentUpdate) -> Void,
        progress: @escaping @Sendable (Double, Int, Int) -> Void
    ) async throws -> FileTranscriptionResult {
        let preparedAudio = try await FileTranscriptionAudioAssetPreparer.prepare(fileURL)
        defer { preparedAudio.cleanup() }
        let readableFileURL = preparedAudio.url
        let audioDurationMS = try Self.audioDurationMS(fileURL: readableFileURL)
        let windows = Self.makeWindows(
            durationMS: audioDurationMS,
            windowLengthMS: windowLengthMS,
            overlapMS: overlapMS
        )
        let totalSegments = windows.count
        var completedTexts: [Int: String] = [:]
        var promptContext: String? = nil
        var completedCount = 0
        var failedCount = 0

        let existingByIndex = Dictionary(uniqueKeysWithValues: existingSegments.map { ($0.index, $0) })

        for (index, window) in windows.enumerated() {
            if Task.isCancelled {
                throw CancellationError()
            }

            // 续跑：已有完成段直接复用。
            if let existing = existingByIndex[index],
               existing.status == TranscriptionSegmentStatus.completed.rawValue,
               let text = existing.finalText {
                completedTexts[index] = text
                completedCount += 1
                promptContext = Self.advancePromptContext(current: promptContext, appended: text)
                onSegment(
                    PipelineSegmentUpdate(
                        index: index,
                        startMS: window.startMS,
                        endMS: window.endMS,
                        status: .completed,
                        text: text,
                        fallbackReason: nil,
                        retryCount: existing.retryCount,
                        providerID: existing.providerID ?? asrProviderID,
                        providerMode: providerMode,
                        error: nil
                    )
                )
                progress(Double(completedCount) / Double(totalSegments), completedCount, totalSegments)
                continue
            }

            // 标记段为 running。
            onSegment(
                PipelineSegmentUpdate(
                    index: index,
                    startMS: window.startMS,
                    endMS: window.endMS,
                    status: .running,
                    text: nil,
                    fallbackReason: nil,
                    retryCount: 0,
                    providerID: asrProviderID,
                    providerMode: providerMode,
                    error: nil
                )
            )

            // 切出临时窗口文件。
            let windowFileURL: URL
            do {
                windowFileURL = try Self.writeWindowAudioFile(
                    sourceURL: readableFileURL,
                    startMS: window.startMS,
                    endMS: window.endMS,
                    overlapMS: overlapMS
                )
            } catch {
                failedCount += 1
                onSegment(
                    PipelineSegmentUpdate(
                        index: index,
                        startMS: window.startMS,
                        endMS: window.endMS,
                        status: .failed,
                        text: nil,
                        fallbackReason: .providerError,
                        retryCount: 0,
                        providerID: asrProviderID,
                        providerMode: providerMode,
                        error: error.localizedDescription
                    )
                )
                continue
            }
            defer { try? FileManager.default.removeItem(at: windowFileURL) }

            // 重试循环。
            var attempt = 0
            var segmentText: String? = nil
            var segmentError: String? = nil
            var fallbackReason: SegmentFallbackReason? = nil
            while attempt <= maxRetryCount && segmentText == nil {
                if Task.isCancelled {
                    throw CancellationError()
                }
                do {
                    let worker = makeSegmentWorker(locale)
                    let result = try await Self.transcribeSegment(
                        worker: worker,
                        fileURL: windowFileURL,
                        asrProviderID: asrProviderID,
                        prompt: promptContext
                    )
                    let trimmed = Self.trimOverlap(
                        text: result.text,
                        previousContext: promptContext
                    )
                    if trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        attempt += 1
                        fallbackReason = .emptyResult
                        continue
                    }
                    if Self.looksLikeDuplicate(text: trimmed, previousContext: promptContext) {
                        attempt += 1
                        fallbackReason = .duplicateText
                        continue
                    }
                    segmentText = trimmed
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    attempt += 1
                    segmentError = error.localizedDescription
                    fallbackReason = .providerError
                }
            }

            if let text = segmentText {
                completedTexts[index] = text
                completedCount += 1
                promptContext = Self.advancePromptContext(current: promptContext, appended: text)
                onSegment(
                    PipelineSegmentUpdate(
                        index: index,
                        startMS: window.startMS,
                        endMS: window.endMS,
                        status: .completed,
                        text: text,
                        fallbackReason: fallbackReason,
                        retryCount: max(0, attempt - 1),
                        providerID: asrProviderID,
                        providerMode: providerMode,
                        error: nil
                    )
                )
            } else {
                failedCount += 1
                onSegment(
                    PipelineSegmentUpdate(
                        index: index,
                        startMS: window.startMS,
                        endMS: window.endMS,
                        status: .failed,
                        text: nil,
                        fallbackReason: fallbackReason ?? .providerError,
                        retryCount: attempt,
                        providerID: asrProviderID,
                        providerMode: providerMode,
                        error: segmentError
                    )
                )
            }

            progress(Double(completedCount) / Double(totalSegments), completedCount, totalSegments)
        }

        let mergedText = Self.mergeTexts(
            windows: windows,
            completedTexts: completedTexts,
            overlapMS: overlapMS
        )
        let finalStatus: TranscriptionSegmentStatus = failedCount > 0 && completedCount > 0
            ? .completed  // 段级部分失败通过 segment 状态表达；job 级由 ViewModel 决定
            : (failedCount > 0 ? .failed : .completed)

        if finalStatus == .failed && completedCount == 0 {
            throw FileTranscriptionError.resultUnavailable
        }

        return FileTranscriptionResult(
            text: mergedText,
            durationMS: audioDurationMS,
            segments: windows.enumerated().compactMap { index, window in
                guard let text = completedTexts[index] else { return nil }
                return TranscriptionSegment(startMS: window.startMS, endMS: window.endMS, text: text)
            }
        )
    }

    // MARK: - Helpers

    private func pipelineProviderMode(for capability: FileTranscriptionCapability) -> TranscriptionProviderMode {
        switch capability {
        case .nativeFile: return .nativeFile
        case .segmentedCompatible: return .segmentedCompatible
        case .notRecommendedForLongFiles: return .notRecommendedForLongFiles
        }
    }

    static func audioDurationMS(fileURL: URL) throws -> Int {
        let audioFile = try AVAudioFile(forReading: fileURL)
        let ms = Int((Double(audioFile.length) / audioFile.processingFormat.sampleRate) * 1_000)
        return max(ms, 1)
    }

    struct Window: Equatable {
        let index: Int
        let startMS: Int
        let endMS: Int
    }

    static func makeWindows(durationMS: Int, windowLengthMS: Int, overlapMS: Int) -> [Window] {
        guard durationMS > 0 else { return [] }
        var windows: [Window] = []
        var start = 0
        var index = 0
        let step = max(1, windowLengthMS - overlapMS)
        while start < durationMS {
            let end = min(start + windowLengthMS, durationMS)
            windows.append(Window(index: index, startMS: start, endMS: end))
            index += 1
            if end >= durationMS { break }
            start += step
        }
        return windows
    }

    static func writeWindowAudioFile(
        sourceURL: URL,
        startMS: Int,
        endMS: Int,
        overlapMS: Int
    ) throws -> URL {
        let audioFile = try AVAudioFile(forReading: sourceURL)
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let startFrame = AVAudioFramePosition(Double(startMS) / 1_000 * sampleRate)
        // 包含 overlap，以便后续去重有素材。
        let endFrame = AVAudioFramePosition(Double(endMS + overlapMS) / 1_000 * sampleRate)
        let frameCount = AVAudioFrameCount(max(1, endFrame - startFrame))

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw FileTranscriptionError.invalidAudioBuffer
        }
        audioFile.framePosition = startFrame
        try audioFile.read(into: buffer, frameCount: frameCount)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxFlow-window-\(UUID().uuidString).wav", isDirectory: false)
        let settings = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: format.channelCount,
            interleaved: false
        )?.settings ?? format.settings
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: settings)
        try outputFile.write(from: buffer)
        return outputURL
    }

    /// 简单 overlap 去重：若 previousContext 的结尾与 text 的开头有较长公共子串，则截掉开头重复部分。
    static func trimOverlap(text: String, previousContext: String?) -> String {
        guard let previousContext,
              !previousContext.isEmpty,
              !text.isEmpty else {
            return text
        }
        let previousTail = String(previousContext.suffix(60))
        let textHead = String(text.prefix(60))
        // 找最长公共前缀/后缀子串。
        let maxOverlap = min(previousTail.count, textHead.count, 30)
        for length in stride(from: maxOverlap, through: 1, by: -1) {
            let tailSuffix = String(previousTail.suffix(length))
            let headPrefix = String(textHead.prefix(length))
            if tailSuffix == headPrefix {
                if text.count >= length {
                    return String(text.dropFirst(length)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return text
    }

    /// 检测明显重复：若 text 与 previousContext 完全相同，或 text 是 previousContext 的子串且长度大于 5。
    static func looksLikeDuplicate(text: String, previousContext: String?) -> Bool {
        guard let previousContext, !previousContext.isEmpty else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed == previousContext.trimmingCharacters(in: .whitespacesAndNewlines) {
            return true
        }
        return false
    }

    static func advancePromptContext(current: String?, appended: String) -> String {
        let prefix = current ?? ""
        let combined = prefix.isEmpty ? appended : (prefix + "\n" + appended)
        // 仅保留最近 200 字符作为上下文，避免 prompt 过长。
        return String(combined.suffix(200))
    }

	    static func mergeTexts(
	        windows: [Window],
	        completedTexts: [Int: String],
	        overlapMS: Int
	    ) -> String {
        var parts: [String] = []
        for window in windows {
            guard let text = completedTexts[window.index] else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            parts.append(trimmed)
	        }
        return parts.joined(separator: "\n")
    }

    private static func transcribeSegment(
        worker: any FileTranscriptionWorking,
        fileURL: URL,
        asrProviderID: String?,
        prompt: String?
    ) async throws -> FileTranscriptionResult {
        if let promptAwareWorker = worker as? any PromptAwareFileTranscriptionWorking {
            return try await promptAwareWorker.transcribe(
                fileURL: fileURL,
                asrProviderID: asrProviderID,
                prompt: prompt
            ) { _ in }
        }
        return try await worker.transcribe(
            fileURL: fileURL,
            asrProviderID: asrProviderID
        ) { _ in }
    }
}
