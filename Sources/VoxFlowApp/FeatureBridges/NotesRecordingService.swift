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
    private static let coldLocalModelFinalTimeoutNanoseconds: UInt64 = 120_000_000_000

    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?

    private let recorder: any NotesAudioRecording
    private nonisolated let audioBufferForwarder: any ASREngineAudioFrameForwarding
    private let currentLanguage: () -> RecognitionLanguage
    private let selectedEngineType: () -> ASREngineType
    private let makeEngine: (ASREngineType) -> ASREngine
    private let microphonePermission: () async -> Bool
    private let speechRecognitionPermission: () async -> Bool
    private let clock: any AppClock
    private let finalTimeoutNanoseconds: UInt64
    private var engine: ASREngine?
    private var latestPartialText: String?
    private var awaitingFinalResult = false
    private var timeoutTask: Task<Void, Never>?
    private var currentEngineType: ASREngineType?

    init(
        asrManager: ASRManager = ASRManager(),
        recorder: any NotesAudioRecording = AudioRecorder(),
        audioBufferForwarder: any ASREngineAudioFrameForwarding = ASREngineAudioFrameForwarder(),
        currentLanguage: @escaping () -> RecognitionLanguage = { LanguageManager.shared.currentLanguage },
        selectedEngineType: (() -> ASREngineType)? = nil,
        makeEngine: ((ASREngineType) -> ASREngine)? = nil,
        microphonePermission: @escaping () async -> Bool = { await NotesRecordingService.liveMicrophonePermission() },
        speechRecognitionPermission: @escaping () async -> Bool = { await NotesRecordingService.liveSpeechRecognitionPermission() },
        clock: any AppClock = SystemClock(),
        finalTimeoutNanoseconds: UInt64 = 15_000_000_000
    ) {
        self.recorder = recorder
        self.audioBufferForwarder = audioBufferForwarder
        self.currentLanguage = currentLanguage
        self.selectedEngineType = selectedEngineType ?? { asrManager.effectiveSelectedEngineType }
        self.makeEngine = makeEngine ?? { asrManager.makeEngine(type: $0) }
        self.microphonePermission = microphonePermission
        self.speechRecognitionPermission = speechRecognitionPermission
        self.clock = clock
        self.finalTimeoutNanoseconds = finalTimeoutNanoseconds
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
        latestPartialText = nil
        awaitingFinalResult = false
        timeoutTask?.cancel()
        timeoutTask = nil
        currentEngineType = engineType
        if engineType == .apple {
            guard await speechRecognitionPermission() else {
                throw NotesRecordingError.speechRecognitionPermissionDenied
            }
        }

        let engine = makeEngine(engineType)
        engine.configure(locale: language.locale)
        engine.onTranscription = { [weak self] text, isFinal in
            Task { @MainActor [weak self] in
                self?.handleTranscription(text: text, isFinal: isFinal)
            }
        }
        engine.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleRecognitionError(error)
            }
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
        awaitingFinalResult = true
        scheduleFinalTimeout()
    }

    func cancel() {
        timeoutTask?.cancel()
        timeoutTask = nil
        awaitingFinalResult = false
        recorder.stop()
        engine?.cancel()
        audioBufferForwarder.detach()
        engine = nil
        currentEngineType = nil
        latestPartialText = nil
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

    private func handleTranscription(text: String, isFinal: Bool) {
        if isFinal {
            complete(with: text, isFinal: true)
            return
        }

        latestPartialText = text
        onTranscription?(text, false)
    }

    private func handleRecognitionError(_ error: Error) {
        if awaitingFinalResult,
           let latestPartialText,
           !latestPartialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            complete(with: latestPartialText, isFinal: true)
            return
        }

        fail(with: error)
    }

    private func scheduleFinalTimeout() {
        timeoutTask?.cancel()
        let timeoutNanoseconds = activeFinalTimeoutNanoseconds()
        timeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await clock.sleep(nanoseconds: timeoutNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.handleFinalTimeout()
        }
    }

    private func handleFinalTimeout() {
        if let latestPartialText,
           !latestPartialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            complete(with: latestPartialText, isFinal: true)
            return
        }

        fail(with: NotesRecordingError.finalResultTimedOut)
    }

    private func complete(with text: String, isFinal: Bool) {
        timeoutTask?.cancel()
        timeoutTask = nil
        awaitingFinalResult = false
        latestPartialText = isFinal ? nil : text
        audioBufferForwarder.detach()
        engine = nil
        currentEngineType = nil
        onTranscription?(text, isFinal)
    }

    private func fail(with error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        awaitingFinalResult = false
        recorder.stop()
        engine?.cancel()
        audioBufferForwarder.detach()
        engine = nil
        currentEngineType = nil
        latestPartialText = nil
        onError?(error)
    }

    private func activeFinalTimeoutNanoseconds() -> UInt64 {
        guard let currentEngineType else {
            return finalTimeoutNanoseconds
        }
        switch currentEngineType {
        case .funASR, .senseVoice, .paraformer, .groqWhisper,
             .parakeetStreaming, .omnilingualASR:
            return max(finalTimeoutNanoseconds, Self.coldLocalModelFinalTimeoutNanoseconds)
        case .apple, .whisper, .qwen3, .nvidiaNemotron, .tencentCloud,
             .aliyunDashScope:
            return finalTimeoutNanoseconds
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
    case finalResultTimedOut

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "未获得麦克风权限，请在系统设置中允许随声写使用麦克风。"
        case .speechRecognitionPermissionDenied:
            return "未获得语音识别权限，请在系统设置中允许随声写使用语音识别。"
        case .unsupportedLanguage(let identifier):
            return "当前笔记录音语言不受支持：\(identifier)。"
        case .finalResultTimedOut:
            return "没有识别到可保存的内容，请重试。"
        }
    }
}
