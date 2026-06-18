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
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    static func requestPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Lifecycle

    func configure(locale: Locale) {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizer = SFSpeechRecognizer(locale: locale)
        isAvailable = recognizer?.isAvailable ?? false
    }

    func start() throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw Error.authorizationDenied
        }

        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw Error.recognizerUnavailable
        }

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        recognitionRequest?.requiresOnDeviceRecognition = false
        recognitionRequest?.taskHint = .dictation

        guard let request = recognitionRequest else { return }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                let nsError = error as NSError
                let wasCancelled =
                    (nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216)
                    || (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
                if wasCancelled {
                    return
                }
                let capturedOnError = self.onError
                DispatchQueue.main.async {
                    capturedOnError?(error)
                }
                return
            }

            if let result = result {
                let text = result.bestTranscription.formattedString
                let isFinal = result.isFinal
                let capturedOnTranscription = self.onTranscription
                DispatchQueue.main.async {
                    capturedOnTranscription?(text, isFinal)
                }
            }
        }
    }

    func appendAudioFrame(_ frame: AudioFrame) {
        guard let buffer = Self.makeAudioBuffer(from: frame) else { return }
        recognitionRequest?.append(buffer)
    }

    func endAudio() {
        recognitionRequest?.endAudio()
    }

    func stop() {
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest = nil
    }

    func cancel() {
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
