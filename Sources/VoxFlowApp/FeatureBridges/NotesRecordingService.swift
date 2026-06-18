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
protocol NotesAudioRecording: AnyObject {
    var delegate: AudioRecorder.Delegate? { get set }

    func start() throws
    func stop()
    func drain()
}

extension AudioRecorder: NotesAudioRecording {}

@MainActor
final class NotesRecordingService: NSObject, NotesTranscribing {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?

    private let recorder: any NotesAudioRecording
    private nonisolated let audioBufferForwarder: any ASREngineAudioFrameForwarding
    private let currentLanguage: () -> RecognitionLanguage
    private let selectedEngineType: () -> ASREngineType
    private let makeEngine: (ASREngineType) -> ASREngine
    private let microphonePermission: () async -> Bool
    private let speechRecognitionPermission: () async -> Bool
    private var engine: ASREngine?

    init(
        asrManager: ASRManager = ASRManager(),
        recorder: any NotesAudioRecording = AudioRecorder(),
        audioBufferForwarder: any ASREngineAudioFrameForwarding = ASREngineAudioFrameForwarder(),
        currentLanguage: @escaping () -> RecognitionLanguage = { LanguageManager.shared.currentLanguage },
        selectedEngineType: (() -> ASREngineType)? = nil,
        makeEngine: ((ASREngineType) -> ASREngine)? = nil,
        microphonePermission: @escaping () async -> Bool = { await NotesRecordingService.liveMicrophonePermission() },
        speechRecognitionPermission: @escaping () async -> Bool = { await NotesRecordingService.liveSpeechRecognitionPermission() }
    ) {
        self.recorder = recorder
        self.audioBufferForwarder = audioBufferForwarder
        self.currentLanguage = currentLanguage
        self.selectedEngineType = selectedEngineType ?? { asrManager.effectiveSelectedEngineType }
        self.makeEngine = makeEngine ?? { asrManager.makeEngine(type: $0) }
        self.microphonePermission = microphonePermission
        self.speechRecognitionPermission = speechRecognitionPermission
        super.init()
        self.recorder.delegate = self
    }

    func start() async throws {
        let language = currentLanguage()
        guard RecognitionLanguage.supportsIdentifier(language.rawValue),
              RecognitionLanguage.supportsIdentifier(language.locale.identifier) else {
            throw NotesRecordingError.unsupportedLanguage(language.rawValue)
        }

        guard await microphonePermission() else {
            throw NotesRecordingError.microphonePermissionDenied
        }

        let engineType = selectedEngineType()
        if engineType == .apple {
            guard await speechRecognitionPermission() else {
                throw NotesRecordingError.speechRecognitionPermissionDenied
            }
        }

        let engine = makeEngine(engineType)
        engine.configure(locale: language.locale)
        engine.onTranscription = { [weak self] text, isFinal in
            self?.onTranscription?(text, isFinal)
        }
        engine.onError = { [weak self] error in
            guard let self else { return }
            self.recorder.stop()
            self.engine?.cancel()
            self.audioBufferForwarder.detach()
            self.engine = nil
            self.onError?(error)
        }

        do {
            try engine.start()
            self.engine = engine
            audioBufferForwarder.attach(engine)
            try recorder.start()
        } catch {
            engine.cancel()
            audioBufferForwarder.detach()
            self.engine = nil
            throw error
        }
    }

    func finish() {
        recorder.stop()
        recorder.drain()
        audioBufferForwarder.finish()
        engine?.endAudio()
    }

    func cancel() {
        recorder.stop()
        engine?.cancel()
        audioBufferForwarder.detach()
        engine = nil
    }

    private static func liveMicrophonePermission() async -> Bool {
        switch AudioRecorder.checkPermission() {
        case .granted:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await AudioRecorder.requestPermission()
        }
    }

    private static func liveSpeechRecognitionPermission() async -> Bool {
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
    nonisolated func audioRecorder(_ recorder: AudioRecorder, didReceiveBuffer buffer: AVAudioPCMBuffer) {
        audioBufferForwarder.appendAudioBuffer(buffer)
    }

    nonisolated func audioRecorder(_ recorder: AudioRecorder, didUpdateRMS rms: Float) {}
}

enum NotesRecordingError: LocalizedError, Equatable {
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case unsupportedLanguage(String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "未获得麦克风权限，请在系统设置中允许随声写使用麦克风。"
        case .speechRecognitionPermissionDenied:
            return "未获得语音识别权限，请在系统设置中允许随声写使用语音识别。"
        case .unsupportedLanguage(let identifier):
            return "当前笔记录音语言不受支持：\(identifier)。"
        }
    }
}
