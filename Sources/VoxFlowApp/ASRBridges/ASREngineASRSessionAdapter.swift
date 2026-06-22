import Foundation
import VoxFlowASRCore
import VoxFlowAudio

enum ASREngineASRProviderError: Error, Equatable, LocalizedError {
    case modelNotInstalled
    case modelCorrupt
    case runtimeUnsupported(String)
    case hardwareUnsupported(String)
    case preparationFailed(String)
    case lifecycleManagedElsewhere

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            return "ASR model is not installed."
        case .modelCorrupt:
            return "ASR model is corrupt."
        case .runtimeUnsupported(let reason):
            return reason
        case .hardwareUnsupported(let reason):
            return reason
        case .preparationFailed(let message):
            return message
        case .lifecycleManagedElsewhere:
            return "ASR engine lifecycle is managed by the existing app runtime."
        }
    }
}

final class ASREngineASRProvider: VoxFlowASRCore.ASRProvider, @unchecked Sendable {
    let descriptor: VoxFlowASRCore.ASRProviderDescriptor

    private let makeEngine: @Sendable () -> any ASREngine

    init(
        descriptor: VoxFlowASRCore.ASRProviderDescriptor,
        makeEngine: @escaping @Sendable () -> any ASREngine
    ) {
        self.descriptor = descriptor
        self.makeEngine = makeEngine
    }

    func install() async throws {
        throw ASREngineASRProviderError.lifecycleManagedElsewhere
    }

    func delete() async throws {
        throw ASREngineASRProviderError.lifecycleManagedElsewhere
    }

    func prepare() async throws {
        try Self.throwIfUnavailable(descriptor.modelInstallationState)
    }

    func healthCheck() async -> VoxFlowASRCore.ASRProviderHealth {
        do {
            try Self.throwIfUnavailable(descriptor.modelInstallationState)
        } catch {
            return .unhealthy(Self.asrError(for: error))
        }
        return .healthy
    }

    func makeSession(language: VoxFlowASRCore.ASRLanguageCapability) async throws -> any VoxFlowASRCore.ASRSession {
        try await prepare()
        let engine = makeEngine()
        engine.configure(locale: Locale(identifier: language.bcp47Tag))
        guard engine.isAvailable else {
            throw ASREngineASRProviderError.preparationFailed("ASR engine is not available.")
        }
        return ASREngineASRSessionAdapter(
            sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "\(descriptor.id.rawValue)-\(UUID().uuidString)"),
            engine: engine
        )
    }

    private static func throwIfUnavailable(_ state: VoxFlowASRCore.ASRModelInstallationState) throws {
        switch state {
        case .ready:
            return
        case .notInstalled, .downloading, .verifying, .compiling, .prewarming:
            throw ASREngineASRProviderError.modelNotInstalled
        case .corrupt:
            throw ASREngineASRProviderError.modelCorrupt
        case .runtimeUnsupported(let reason):
            throw ASREngineASRProviderError.runtimeUnsupported(reason)
        case .hardwareUnsupported(let reason):
            throw ASREngineASRProviderError.hardwareUnsupported(reason)
        case .failed(let message):
            throw ASREngineASRProviderError.preparationFailed(message)
        }
    }

    private static func asrError(for error: Error) -> VoxFlowASRCore.ASRError {
        if let providerError = error as? ASREngineASRProviderError {
            switch providerError {
            case .modelNotInstalled, .lifecycleManagedElsewhere:
                return VoxFlowASRCore.ASRError(category: .modelNotInstalled, message: providerError.localizedDescription)
            case .modelCorrupt:
                return VoxFlowASRCore.ASRError(category: .modelCorrupt, message: providerError.localizedDescription)
            case .runtimeUnsupported:
                return VoxFlowASRCore.ASRError(category: .runtimeUnsupported, message: providerError.localizedDescription)
            case .hardwareUnsupported:
                return VoxFlowASRCore.ASRError(category: .hardwareUnsupported, message: providerError.localizedDescription)
            case .preparationFailed:
                return VoxFlowASRCore.ASRError(category: .preparationFailed, message: providerError.localizedDescription)
            }
        }
        return VoxFlowASRCore.ASRError(category: .preparationFailed, message: error.localizedDescription)
    }
}

final class ASREngineASRSessionAdapter: VoxFlowASRCore.ASRSession, @unchecked Sendable {
    let sessionID: VoxFlowASRCore.ASRSessionID
    var events: AsyncStream<VoxFlowASRCore.ASREvent> { eventStream.stream }

    private let engine: any ASREngine
    private let eventStream = VoxFlowASRCore.ASREventStream()
    private let lock = NSLock()
    private var currentRevision: UInt64 = 0
    private var processedFrameCount: UInt64 = 0
    private var processedSampleCount: UInt64 = 0
    private var sampleRate: Int = 16_000
    private var hasStartedSpeech = false
    private var isClosed = false

    var revision: UInt64 {
        lock.withLock { currentRevision }
    }

    init(
        sessionID: VoxFlowASRCore.ASRSessionID,
        engine: any ASREngine
    ) {
        self.sessionID = sessionID
        self.engine = engine
    }

    func start() async throws {
        AppLogger.audio.debug("ASREngineASRSessionAdapter start session=\(sessionID.rawValue)")
        engine.onTranscription = { [weak self] text, isFinal in
            self?.emitTranscript(text, isFinal: isFinal)
        }
        engine.onError = { [weak self] error in
            self?.emitFailure(error)
        }

        eventStream.yield(.preparing(sessionID: sessionID, revision: revision))
        do {
            try engine.start()
            AppLogger.audio.debug("ASREngineASRSessionAdapter ready session=\(sessionID.rawValue)")
            eventStream.yield(.ready(sessionID: sessionID, revision: nextRevision()))
        } catch {
            AppLogger.audio.warning("ASREngineASRSessionAdapter start failed session=\(sessionID.rawValue) reason=\(error.localizedDescription)")
            emitFailure(error)
            throw error
        }
    }

    func accept(_ frame: AudioFrame) async throws {
        let shouldEmitSpeechStarted = lock.withLock { () -> Bool in
            guard !isClosed else { return false }
            processedFrameCount += 1
            processedSampleCount += UInt64(frame.samples.count)
            sampleRate = frame.sampleRate
            guard !hasStartedSpeech else { return false }
            hasStartedSpeech = true
            return true
        }
        guard !isClosedForCallback else { return }

        if shouldEmitSpeechStarted {
            eventStream.yield(
                .speechStarted(
                    sessionID: sessionID,
                    revision: nextRevision(),
                    sequenceNumber: frame.sequenceNumber
                )
            )
        }
        engine.appendAudioFrame(frame)
    }

    func finish() async throws {
        guard !isClosedForCallback else { return }
        AppLogger.audio.debug(
            "ASREngineASRSessionAdapter finish session=\(sessionID.rawValue) processedFrames=\(lock.withLock { processedFrameCount })"
        )
        engine.endAudio()
    }

    func cancel() async {
        let shouldEmit = close()
        AppLogger.audio.debug("ASREngineASRSessionAdapter cancel session=\(sessionID.rawValue)")
        engine.cancel()
        guard shouldEmit else { return }

        eventStream.yield(
            .failure(
                sessionID: sessionID,
                revision: nextRevision(),
                error: VoxFlowASRCore.ASRError(
                    category: .cancelled,
                    message: "ASR engine session was cancelled."
                )
            )
        )
        eventStream.finish()
    }

    private var isClosedForCallback: Bool {
        lock.withLock { isClosed }
    }

    private func emitTranscript(_ text: String, isFinal: Bool) {
        guard !isClosedForCallback else { return }
        let revision = nextRevision()
        if isFinal {
            guard close() else { return }
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

    private func emitFailure(_ error: Error) {
        guard close() else { return }
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

    private func close() -> Bool {
        lock.withLock {
            guard !isClosed else { return false }
            isClosed = true
            return true
        }
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
