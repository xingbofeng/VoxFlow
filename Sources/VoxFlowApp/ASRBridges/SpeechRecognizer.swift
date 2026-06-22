import AVFoundation
import Speech
import VoxFlowAudio

/// Streaming speech recognizer using Apple's SFSpeechRecognizer.
/// Provides real-time transcription updates as audio is received.
final class SpeechRecognizer: NSObject, @unchecked Sendable, ASREngine {
    // MARK: - Types

    typealias TranscriptionHandler = (String, Bool) -> Void  // (text, isFinal)
    typealias ErrorHandler = (Swift.Error) -> Void

    // MARK: - Properties

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    var onTranscription: TranscriptionHandler?
    var onError: ErrorHandler?
    private(set) var isAvailable = false

    // MARK: - Permission

    static func checkPermission() -> AudioRecorder.PermissionStatus {
        let status = SFSpeechRecognizer.authorizationStatus()
        AppLogger.audio.debug("Apple speech permission status=\(status.rawValue)")
        switch status {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    static func requestPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                AppLogger.audio.debug("Apple speech permission requested status=\(status.rawValue)")
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Lifecycle

    func configure(locale: Locale) {
        AppLogger.audio.debug("Apple speech recognizer configure locale=\(locale.identifier)")
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizer = SFSpeechRecognizer(locale: locale)
        isAvailable = recognizer?.isAvailable ?? false
        AppLogger.audio.debug("Apple speech recognizer available=\(isAvailable)")
    }

    func start() throws {
        AppLogger.audio.debug("Apple speech recognizer start")
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            AppLogger.audio.warning("Apple speech recognizer start blocked: permission denied")
            throw Error.authorizationDenied
        }

        guard let recognizer = recognizer, recognizer.isAvailable else {
            AppLogger.audio.warning("Apple speech recognizer start blocked: recognizer unavailable")
            throw Error.recognizerUnavailable
        }

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        recognitionRequest?.requiresOnDeviceRecognition = false
        recognitionRequest?.taskHint = .dictation
        AppLogger.audio.debug("Apple speech recognizer request created")

        guard let request = recognitionRequest else { return }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                let nsError = error as NSError
                let wasCancelled =
                    (nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216)
                    || (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
                if wasCancelled {
                    AppLogger.audio.debug("Apple speech recognizer result cancelled")
                    return
                }
                AppLogger.audio.warning("Apple speech recognizer error: \(error.localizedDescription)")
                let capturedOnError = self.onError
                DispatchQueue.main.async {
                    capturedOnError?(error)
                }
                return
            }

            if let result = result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                AppLogger.audio.debug("Apple speech recognizer callback isFinal=\(isFinal) len=\(text.count)")
                let capturedOnTranscription = self.onTranscription
                DispatchQueue.main.async {
                    capturedOnTranscription?(text, isFinal)
                }
            }
        }
    }

    func appendAudioFrame(_ frame: AudioFrame) {
        guard let buffer = Self.makeAudioBuffer(from: frame) else {
            AppLogger.audio.warning("Apple speech appendAudioFrame failed: invalid buffer")
            return
        }
        recognitionRequest?.append(buffer)
    }

    func endAudio() {
        AppLogger.audio.debug("Apple speech endAudio")
        recognitionRequest?.endAudio()
    }

    func stop() {
        AppLogger.audio.debug("Apple speech stop")
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest = nil
    }

    func cancel() {
        AppLogger.audio.debug("Apple speech cancel")
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    // MARK: - Errors

    enum Error: Swift.Error, LocalizedError {
        case authorizationDenied
        case recognizerUnavailable

        var errorDescription: String? {
            switch self {
            case .authorizationDenied:
                return "未获得语音识别权限。"
            case .recognizerUnavailable:
                return "语音识别服务不可用，请检查网络连接。"
            }
        }
    }

    private static func makeAudioBuffer(from frame: AudioFrame) -> AVAudioPCMBuffer? {
        guard !frame.samples.isEmpty,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: Double(frame.sampleRate),
                  channels: 1,
                  interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(frame.samples.count)
              ),
              let channel = buffer.floatChannelData?[0] else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(frame.samples.count)
        for index in frame.samples.indices {
            channel[index] = frame.samples[index]
        }
        return buffer
    }
}
