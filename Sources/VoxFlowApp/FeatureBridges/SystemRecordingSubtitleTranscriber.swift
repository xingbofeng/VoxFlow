import AVFoundation
import Foundation
import Speech

/// 字幕生成阶段错误。
enum RecordingSubtitleTranscriptionError: Error, Equatable, LocalizedError {
    /// 录屏没有麦克风音轨，无法生成字幕。
    case noMicrophoneAudio
    /// Speech 识别权限缺失或被拒。
    case speechPermissionDenied
    /// 从视频抽取音轨失败。
    case audioExtractionFailed(String)
    /// 语音识别失败。
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noMicrophoneAudio:
            return "这段录屏没有麦克风音频，无法添加字幕"
        case .speechPermissionDenied:
            return "需要语音识别权限才能生成字幕"
        case .audioExtractionFailed(let reason):
            return "抽取录屏音轨失败：\(reason)"
        case .recognitionFailed(let reason):
            return "字幕生成失败：\(reason)"
        }
    }
}

/// 识别结果。
struct RecordingTranscriptionResult: Equatable, Sendable {
    let segments: [RecordingSubtitleSegment]
}

/// 带时间范围的识别片段（毫秒）。
struct TimedSpeechSegment: Equatable, Sendable {
    let startMS: Int
    let durationMS: Int
    let text: String
}

// MARK: - Ports

/// 语音识别端口：封装系统 Speech framework，便于测试注入。
protocol RecordingSpeechRecognizerPort: Sendable {
    func currentAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus
    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus
    func transcribeAudioFile(at url: URL) async throws -> [TimedSpeechSegment]
}

/// 音轨抽取端口：从录屏视频抽取麦克风音轨到临时音频文件。
protocol RecordingAudioTrackExtractorPort: Sendable {
    func extractAudio(from videoURL: URL) async throws -> URL
    func removeTempAudio(_ url: URL)
}

// MARK: - Transcriber 协议

/// 系统字幕生成器：输入录屏视频，输出带时间轴的字幕段。
///
/// V1 只使用系统 Speech framework；具体实现通过注入的 ports 完成音轨抽取与识别，
/// 便于在测试中模拟 timed segments。
protocol SystemRecordingSubtitleTranscriber: Sendable {
    func transcribe(videoURL: URL, audioMode: MediaAudioMode) async throws -> RecordingTranscriptionResult
}

// MARK: - Live 实现

final class LiveSystemRecordingSubtitleTranscriber: SystemRecordingSubtitleTranscriber {
    private let recognizer: any RecordingSpeechRecognizerPort
    private let extractor: any RecordingAudioTrackExtractorPort

    init(
        recognizer: any RecordingSpeechRecognizerPort,
        extractor: any RecordingAudioTrackExtractorPort
    ) {
        self.recognizer = recognizer
        self.extractor = extractor
    }

    func transcribe(videoURL: URL, audioMode: MediaAudioMode) async throws -> RecordingTranscriptionResult {
        // 3.1 无麦克风音轨：直接拒绝，不做任何后续工作。
        guard audioMode == .microphone else {
            throw RecordingSubtitleTranscriptionError.noMicrophoneAudio
        }

        // 3.2 Speech 权限：缺失或被拒则抛错，原视频不被触碰。
        var status = recognizer.currentAuthorizationStatus()
        if status == .notDetermined {
            status = await recognizer.requestAuthorization()
        }
        guard status == .authorized else {
            throw RecordingSubtitleTranscriptionError.speechPermissionDenied
        }

        // 3.4 抽取音轨到临时文件；无论成功失败都清理。
        let audioURL: URL
        do {
            audioURL = try await extractor.extractAudio(from: videoURL)
        } catch let error as RecordingSubtitleTranscriptionError {
            throw error
        } catch {
            throw RecordingSubtitleTranscriptionError.audioExtractionFailed(error.localizedDescription)
        }

        let timedSegments: [TimedSpeechSegment]
        do {
            timedSegments = try await recognizer.transcribeAudioFile(at: audioURL)
        } catch let error as RecordingSubtitleTranscriptionError {
            extractor.removeTempAudio(audioURL)
            throw error
        } catch {
            extractor.removeTempAudio(audioURL)
            throw RecordingSubtitleTranscriptionError.recognitionFailed(error.localizedDescription)
        }
        extractor.removeTempAudio(audioURL)

        let segments = timedSegments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(Self.map)
        return RecordingTranscriptionResult(segments: segments)
    }

    /// 把 `TimedSpeechSegment` 映射为可烧录的 `RecordingSubtitleSegment`。
    static func map(_ timed: TimedSpeechSegment) -> RecordingSubtitleSegment {
        RecordingSubtitleSegment(
            startMS: timed.startMS,
            endMS: timed.startMS + timed.durationMS,
            text: timed.text
        )
    }
}

// MARK: - Live ports

/// 基于 AVAssetExportSession 的音轨抽取：导出为临时 m4a。
final class LiveRecordingAudioTrackExtractor: RecordingAudioTrackExtractorPort {
    func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecordingSubtitleTranscriptionError.audioExtractionFailed("无法创建导出会话")
        }

        let tempDirectory = FileManager.default.temporaryDirectory
        let outputURL = tempDirectory.appendingPathComponent(
            "voxflow-subtitle-\(UUID().uuidString).m4a",
            isDirectory: false
        )
        session.outputURL = outputURL
        session.outputFileType = .m4a

        do {
            try await session.export(to: outputURL, as: .m4a)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw RecordingSubtitleTranscriptionError.audioExtractionFailed(error.localizedDescription)
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw RecordingSubtitleTranscriptionError.audioExtractionFailed("导出后音轨文件不存在")
        }
        return outputURL
    }

    func removeTempAudio(_ url: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }
}

/// 基于 SFSpeechRecognizer 的文件识别：读取 SFTranscriptionSegment 时间信息。
final class LiveRecordingSpeechRecognizer: RecordingSpeechRecognizerPort {
    private let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func currentAuthorizationStatus() -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    func transcribeAudioFile(at url: URL) async throws -> [TimedSpeechSegment] {
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer() else {
            throw RecordingSubtitleTranscriptionError.recognitionFailed("当前语言不可用")
        }
        guard recognizer.isAvailable else {
            throw RecordingSubtitleTranscriptionError.recognitionFailed("语音识别不可用")
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: RecordingSubtitleTranscriptionError.recognitionFailed(error.localizedDescription))
                    return
                }
                guard let result, result.isFinal else { return }
                let segments = result.bestTranscription.segments.map { segment in
                    TimedSpeechSegment(
                        startMS: Int(segment.timestamp * 1_000),
                        durationMS: Int(segment.duration * 1_000),
                        text: segment.substring
                    )
                }
                continuation.resume(returning: segments)
            }
        }
    }
}
