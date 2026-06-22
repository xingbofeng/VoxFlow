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
    private let audioCaptureCoordinator: any AudioCaptureCoordinating
    private let clock: any AppClock
    private let finalTimeoutNanoseconds: UInt64
    private var engine: ASREngine?
    private var latestPartialText: String?
    private var awaitingFinalResult = false
    private var timeoutTask: Task<Void, Never>?
    private var currentEngineType: ASREngineType?
    private var sessionGeneration: UUID?
    private var audioCaptureLease: AudioCaptureLease?

    init(
        asrManager: ASRManager = ASRManager(),
        recorder: any NotesAudioRecording = AudioRecorder(),
        audioBufferForwarder: any ASREngineAudioFrameForwarding = ASREngineAudioFrameForwarder(),
        currentLanguage: @escaping () -> RecognitionLanguage = { LanguageManager.shared.currentLanguage },
        selectedEngineType: (() -> ASREngineType)? = nil,
        makeEngine: ((ASREngineType) -> ASREngine)? = nil,
        microphonePermission: @escaping () async -> Bool = { await NotesRecordingService.liveMicrophonePermission() },
        speechRecognitionPermission: @escaping () async -> Bool = { await NotesRecordingService.liveSpeechRecognitionPermission() },
        audioCaptureCoordinator: any AudioCaptureCoordinating = AudioCaptureCoordinator(),
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
        self.audioCaptureCoordinator = audioCaptureCoordinator
        self.clock = clock
        self.finalTimeoutNanoseconds = finalTimeoutNanoseconds
        super.init()
        self.recorder.delegate = self
    }

    func start() async throws {
        let language = currentLanguage()
        AppLogger.audio.debug("笔记录制开始：language=\(language.rawValue)")
        guard RecognitionLanguage.supportsIdentifier(language.rawValue),
              RecognitionLanguage.supportsIdentifier(language.locale.identifier) else {
            AppLogger.audio.warning("笔记录制失败：不支持语言 \(language.rawValue)")
            throw NotesRecordingError.unsupportedLanguage(language.rawValue)
        }

        guard await microphonePermission() else {
            AppLogger.audio.warning("笔记录制失败：麦克风权限缺失")
            throw NotesRecordingError.microphonePermissionDenied
        }

        let engineType = selectedEngineType()
        AppLogger.audio.debug("笔记录制引擎：\(engineType.rawValue)")
        latestPartialText = nil
        awaitingFinalResult = false
        timeoutTask?.cancel()
        timeoutTask = nil
        currentEngineType = engineType
        if engineType == .apple {
            guard await speechRecognitionPermission() else {
                AppLogger.audio.warning("笔记录制失败：语音识别权限缺失（Apple 引擎）")
                throw NotesRecordingError.speechRecognitionPermissionDenied
            }
        }

        let lease = try audioCaptureCoordinator.begin(kind: .notes)
        audioCaptureLease = lease
        let generation = UUID()
        sessionGeneration = generation
        let engine = makeEngine(engineType)
        engine.configure(locale: language.locale)
        engine.onTranscription = { [weak self] text, isFinal in
            Task { @MainActor [weak self] in
                self?.handleTranscription(text: text, isFinal: isFinal, generation: generation)
            }
        }
        engine.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleRecognitionError(error, generation: generation)
            }
        }

        do {
            try engine.start()
            self.engine = engine
            audioBufferForwarder.attach(engine)
            try recorder.start()
        } catch {
            AppLogger.audio.error("笔记录制启动失败：\(error.localizedDescription)")
            audioCaptureCoordinator.end(lease)
            audioCaptureLease = nil
            engine.cancel()
            audioBufferForwarder.detach()
            self.engine = nil
            sessionGeneration = nil
            currentEngineType = nil
            throw error
        }
    }

    func finish() {
        AppLogger.audio.debug("笔记录制结束：触发 finalization")
        recorder.stop()
        recorder.drain()
        endCurrentAudioCapture()
        audioBufferForwarder.finish()
        engine?.endAudio()
        awaitingFinalResult = true
        guard let generation = sessionGeneration else { return }
        scheduleFinalTimeout(generation: generation)
    }

    func cancel() {
        AppLogger.audio.debug("笔记录制取消")
        timeoutTask?.cancel()
        timeoutTask = nil
        sessionGeneration = nil
        awaitingFinalResult = false
        recorder.stop()
        endCurrentAudioCapture()
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

    private func handleTranscription(text: String, isFinal: Bool, generation: UUID) {
        guard generation == sessionGeneration else { return }
        AppLogger.audio.debug("笔记转写回调：isFinal=\(isFinal), length=\(text.count)")
        if isFinal {
            complete(with: text, isFinal: true)
            return
        }

        latestPartialText = text
        onTranscription?(text, false)
    }

    private func handleRecognitionError(_ error: Error, generation: UUID) {
        guard generation == sessionGeneration else { return }
        AppLogger.audio.warning("笔记识别错误：\(error.localizedDescription)")
        if awaitingFinalResult,
           let latestPartialText,
           !latestPartialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            complete(with: latestPartialText, isFinal: true)
            return
        }

        fail(with: error)
    }

    private func scheduleFinalTimeout(generation: UUID) {
        timeoutTask?.cancel()
        let timeoutNanoseconds = activeFinalTimeoutNanoseconds()
        AppLogger.audio.debug("安排笔记 final 超时：\(timeoutNanoseconds) ns")
        timeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await clock.sleep(nanoseconds: timeoutNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.handleFinalTimeout(generation: generation)
        }
    }

    private func handleFinalTimeout(generation: UUID) {
        guard generation == sessionGeneration else { return }
        AppLogger.audio.warning("笔记 final 超时：generation=\(generation)")
        if let latestPartialText,
           !latestPartialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            complete(with: latestPartialText, isFinal: true)
            return
        }

        fail(with: NotesRecordingError.finalResultTimedOut)
    }

    private func complete(with text: String, isFinal: Bool) {
        AppLogger.audio.info("笔记录制完成：isFinal=\(isFinal), length=\(text.count)")
        timeoutTask?.cancel()
        timeoutTask = nil
        sessionGeneration = nil
        awaitingFinalResult = false
        latestPartialText = isFinal ? nil : text
        endCurrentAudioCapture()
        audioBufferForwarder.detach()
        engine = nil
        currentEngineType = nil
        onTranscription?(text, isFinal)
    }

    private func fail(with error: Error) {
        AppLogger.audio.error("笔记录制失败：\(error.localizedDescription)")
        timeoutTask?.cancel()
        timeoutTask = nil
        sessionGeneration = nil
        awaitingFinalResult = false
        recorder.stop()
        endCurrentAudioCapture()
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

    private func endCurrentAudioCapture() {
        guard let audioCaptureLease else { return }
        audioCaptureCoordinator.end(audioCaptureLease)
        self.audioCaptureLease = nil
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
            return "未获得麦克风权限，请在系统设置中允许码上写使用麦克风。"
        case .speechRecognitionPermissionDenied:
            return "未获得语音识别权限，请在系统设置中允许码上写使用语音识别。"
        case .unsupportedLanguage(let identifier):
            return "当前笔记录音语言不受支持：\(identifier)。"
        case .finalResultTimedOut:
            return "没有识别到可保存的内容，请重试。"
        }
    }
}
