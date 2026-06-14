@preconcurrency import AVFoundation
import Foundation
import Speech

@MainActor
protocol NotesTranscribing: AnyObject {
    var onTranscription: ((String, Bool) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }

    func start() async throws
    func finish()
    func cancel()
}

@MainActor
final class NotesRecordingService: NSObject, NotesTranscribing {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?

    private let asrManager: ASRManager
    private let recorder: AudioRecorder
    private var engine: ASREngine?

    init(
        asrManager: ASRManager = ASRManager(),
        recorder: AudioRecorder = AudioRecorder()
    ) {
        self.asrManager = asrManager
        self.recorder = recorder
        super.init()
        self.recorder.delegate = self
    }

    func start() async throws {
        guard await ensureMicrophonePermission() else {
            throw NotesRecordingError.microphonePermissionDenied
        }

        let engineType = asrManager.effectiveSelectedEngineType
        if engineType == .apple {
            guard await ensureSpeechRecognitionPermission() else {
                throw NotesRecordingError.speechRecognitionPermissionDenied
            }
        }

        let engine = asrManager.makeEngine(type: engineType)
        engine.configure(locale: RecognitionLanguage.default.locale)
        engine.onTranscription = { [weak self] text, isFinal in
            self?.onTranscription?(text, isFinal)
        }
        engine.onError = { [weak self] error in
            guard let self else { return }
            self.recorder.stop()
            self.engine?.cancel()
            self.engine = nil
            self.onError?(error)
        }

        do {
            try engine.start()
            self.engine = engine
            try recorder.start()
        } catch {
            engine.cancel()
            self.engine = nil
            throw error
        }
    }

    func finish() {
        recorder.stop()
        engine?.endAudio()
    }

    func cancel() {
        recorder.stop()
        engine?.cancel()
        engine = nil
    }

    private func ensureMicrophonePermission() async -> Bool {
        switch AudioRecorder.checkPermission() {
        case .granted:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await AudioRecorder.requestPermission()
        }
    }

    private func ensureSpeechRecognitionPermission() async -> Bool {
        switch SpeechRecognizer.checkPermission() {
        case .granted:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await SpeechRecognizer.requestPermission() == .authorized
        }
    }
}

extension NotesRecordingService: AudioRecorder.Delegate {
    func audioRecorder(_ recorder: AudioRecorder, didReceiveBuffer buffer: AVAudioPCMBuffer) {
        engine?.appendAudioBuffer(buffer)
    }

    func audioRecorder(_ recorder: AudioRecorder, didUpdateRMS rms: Float) {}
}

enum NotesRecordingError: LocalizedError {
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "未获得麦克风权限，请在系统设置中允许随声写使用麦克风。"
        case .speechRecognitionPermissionDenied:
            return "未获得语音识别权限，请在系统设置中允许随声写使用语音识别。"
        }
    }
}
