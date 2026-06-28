@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech
import VoxFlowASRCore
import VoxFlowAudio

public enum AppleSpeechAuthorizationStatus: Equatable, Sendable {
    case authorized
    case denied
    case notDetermined
}

public enum AppleSpeechProviderError: Error, Equatable, Sendable {
    case authorizationDenied
    case recognizerUnavailable
}

public enum AppleSpeechProviderDescriptor {
    public static let current = VoxFlowASRCore.ASRProviderDescriptor(
        id: VoxFlowASRCore.ASRProviderID(rawValue: "apple_speech"),
        displayName: "系统自带",
        modelInstallationState: .ready,
        supportedLanguages: [
            VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "zh-CN"),
            VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "zh-TW"),
            VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "en-US"),
            VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "ja-JP"),
            VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "ko-KR"),
        ],
        streamingSemantics: .systemStreaming
    )
}

protocol AppleSpeechRecognitionEngine: AnyObject, Sendable {
    var onTranscription: (@Sendable (String, Bool) -> Void)? { get set }
    var onError: (@Sendable (Error) -> Void)? { get set }
    var isAvailable: Bool { get }

    func configureContextualStrings(_ strings: [String])
    func start() throws
    func accept(_ frame: AudioFrame)
    func finish()
    func cancel()
}

public struct AppleSpeechASRProvider: VoxFlowASRCore.ASRProvider {
    public let descriptor: VoxFlowASRCore.ASRProviderDescriptor

    private let authorizationStatus: @Sendable () -> AppleSpeechAuthorizationStatus
    private let makeEngine: @Sendable (Locale) -> any AppleSpeechRecognitionEngine

    public init() {
        self.init(
            authorizationStatus: Self.currentAuthorizationStatus,
            makeEngine: { locale in
                SystemAppleSpeechRecognitionEngine(locale: locale)
            }
        )
    }

    init(
        descriptor: VoxFlowASRCore.ASRProviderDescriptor = AppleSpeechProviderDescriptor.current,
        authorizationStatus: @escaping @Sendable () -> AppleSpeechAuthorizationStatus,
        makeEngine: @escaping @Sendable (Locale) -> any AppleSpeechRecognitionEngine
    ) {
        self.descriptor = descriptor
        self.authorizationStatus = authorizationStatus
        self.makeEngine = makeEngine
    }

    public func install() async throws {}

    public func delete() async throws {}

    public func prepare() async throws {
        guard authorizationStatus() == .authorized else {
            throw AppleSpeechProviderError.authorizationDenied
        }
    }

    public func healthCheck() async -> VoxFlowASRCore.ASRProviderHealth {
        switch authorizationStatus() {
        case .authorized:
            return .healthy
        case .denied:
            return .unhealthy(Self.authorizationError(message: "Apple Speech authorization is denied."))
        case .notDetermined:
            return .unhealthy(Self.authorizationError(message: "Apple Speech authorization has not been determined."))
        }
    }

    public func makeSession(
        language: VoxFlowASRCore.ASRLanguageCapability
    ) async throws -> any VoxFlowASRCore.ASRSession {
        try await prepare()
        let engine = makeEngine(Locale(identifier: language.bcp47Tag))
        guard engine.isAvailable else {
            throw AppleSpeechProviderError.recognizerUnavailable
        }
        return AppleSpeechASRSession(
            sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "apple-speech-\(UUID().uuidString)"),
            engine: engine
        )
    }

    private static func authorizationError(message: String) -> VoxFlowASRCore.ASRError {
        VoxFlowASRCore.ASRError(
            category: .preparationFailed,
            message: message
        )
    }

    private static func currentAuthorizationStatus() -> AppleSpeechAuthorizationStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
}

final class AppleSpeechASRSession: VoxFlowASRCore.ASRSession, @unchecked Sendable {
    let sessionID: VoxFlowASRCore.ASRSessionID
    var events: AsyncStream<VoxFlowASRCore.ASREvent> { eventStream.stream }

    private let engine: any AppleSpeechRecognitionEngine
    private let eventStream = VoxFlowASRCore.ASREventStream()
    private let lock = NSLock()
    private var currentRevision: UInt64 = 0
    private var processedFrameCount: UInt64 = 0
    private var processedSampleCount: UInt64 = 0
    private var sampleRate: Int = 16_000
    private var hasStartedSpeech = false
    private var contextualStrings: [String] = []

    var revision: UInt64 {
        lock.withLock { currentRevision }
    }

    init(
        sessionID: VoxFlowASRCore.ASRSessionID,
        engine: any AppleSpeechRecognitionEngine
    ) {
        self.sessionID = sessionID
        self.engine = engine
    }

    func start() async throws {
        engine.onTranscription = { [weak self] text, isFinal in
            self?.emitTranscript(text, isFinal: isFinal)
        }
        engine.onError = { [weak self] error in
            self?.emitFailure(error)
        }

        eventStream.yield(.preparing(sessionID: sessionID, revision: revision))
        do {
            try engine.start()
            eventStream.yield(.ready(sessionID: sessionID, revision: nextRevision()))
        } catch {
            emitFailure(error)
            throw error
        }
    }

    func configurePrompt(_ prompt: String?) async throws {
        let terms = Self.terms(from: prompt)
        lock.withLock {
            contextualStrings = terms
        }
        engine.configureContextualStrings(terms)
    }

    func accept(_ frame: AudioFrame) async throws {
        let shouldEmitSpeechStarted = lock.withLock { () -> Bool in
            processedFrameCount += 1
            processedSampleCount += UInt64(frame.samples.count)
            sampleRate = frame.sampleRate
            guard !hasStartedSpeech else { return false }
            hasStartedSpeech = true
            return true
        }

        if shouldEmitSpeechStarted {
            eventStream.yield(
                .speechStarted(
                    sessionID: sessionID,
                    revision: nextRevision(),
                    sequenceNumber: frame.sequenceNumber
                )
            )
        }
        engine.accept(frame)
    }

    func finish() async throws {
        engine.finish()
    }

    func cancel() async {
        engine.cancel()
        eventStream.yield(
            .failure(
                sessionID: sessionID,
                revision: nextRevision(),
                error: VoxFlowASRCore.ASRError(
                    category: .cancelled,
                    message: "Apple Speech session was cancelled."
                )
            )
        )
        eventStream.finish()
    }

    private func emitTranscript(_ text: String, isFinal: Bool) {
        let revision = nextRevision()
        if isFinal {
            eventStream.yield(.final(sessionID: sessionID, revision: revision, text: text))
            eventStream.yield(
                .metrics(
                    sessionID: sessionID,
                    revision: nextRevision(),
                    metrics: metrics()
                )
            )
            eventStream.finish()
            return
        }

        eventStream.yield(
            .partial(
                sessionID: sessionID,
                transcript: VoxFlowASRCore.PartialTranscript(
                    stablePrefix: "",
                    unstableSuffix: text,
                    revision: revision,
                    audioDuration: audioDuration()
                )
            )
        )
    }

    private static func terms(from prompt: String?) -> [String] {
        guard let prompt else { return [] }
        var seen = Set<String>()
        return prompt
            .components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .compactMap { raw -> String? in
                let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !term.isEmpty else { return nil }
                let key = term.lowercased()
                guard seen.insert(key).inserted else { return nil }
                return term
            }
    }

    private func emitFailure(_ error: Error) {
        eventStream.yield(
            .failure(
                sessionID: sessionID,
                revision: nextRevision(),
                error: VoxFlowASRCore.ASRError(
                    category: .preparationFailed,
                    message: error.localizedDescription
                )
            )
        )
        eventStream.finish()
    }

    private func nextRevision() -> UInt64 {
        lock.withLock {
            currentRevision += 1
            return currentRevision
        }
    }

    private func audioDuration() -> Duration {
        lock.withLock {
            guard sampleRate > 0 else { return .zero }
            return .milliseconds(Int64((processedSampleCount * 1_000) / UInt64(sampleRate)))
        }
    }

    private func metrics() -> VoxFlowASRCore.ASRMetrics {
        lock.withLock {
            VoxFlowASRCore.ASRMetrics(
                audioDuration: sampleRate > 0
                    ? .milliseconds(Int64((processedSampleCount * 1_000) / UInt64(sampleRate)))
                    : .zero,
                processedFrameCount: processedFrameCount,
                droppedFrameCount: 0
            )
        }
    }
}

private final class SystemAppleSpeechRecognitionEngine: NSObject, AppleSpeechRecognitionEngine, @unchecked Sendable {
    var onTranscription: (@Sendable (String, Bool) -> Void)?
    var onError: (@Sendable (Error) -> Void)?

    var isAvailable: Bool {
        recognizer?.isAvailable ?? false
    }

    private let recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let lock = NSLock()
    private var contextualStrings: [String] = []

    init(locale: Locale) {
        recognizer = SFSpeechRecognizer(locale: locale)
        super.init()
    }

    func start() throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw AppleSpeechProviderError.authorizationDenied
        }
        guard let recognizer,
              recognizer.isAvailable else {
            throw AppleSpeechProviderError.recognizerUnavailable
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        request.taskHint = .dictation
        request.contextualStrings = lock.withLock { contextualStrings }
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let error {
                guard !Self.isCancellation(error) else { return }
                onError?(error)
                return
            }

            guard let result else { return }
            onTranscription?(result.bestTranscription.formattedString, result.isFinal)
        }
    }

    func configureContextualStrings(_ strings: [String]) {
        lock.withLock {
            contextualStrings = strings
        }
    }

    func accept(_ frame: AudioFrame) {
        guard let buffer = Self.makeAudioBuffer(from: frame) else { return }
        recognitionRequest?.append(buffer)
    }

    func finish() {
        recognitionRequest?.endAudio()
    }

    func cancel() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    private static func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return (nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216)
            || (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
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
