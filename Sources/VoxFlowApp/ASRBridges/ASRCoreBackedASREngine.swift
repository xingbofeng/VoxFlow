import Foundation
import VoxFlowASRCore
import VoxFlowAudio

private final class ASRCoreBackedCallbackBox: @unchecked Sendable {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?
}

final class ASRCoreBackedASREngine: ASREngine, ASRRuntimeMetadataProviding, @unchecked Sendable {
    var onTranscription: ((String, Bool) -> Void)? {
        get { callbacks.onTranscription }
        set { callbacks.onTranscription = newValue }
    }

    var onError: ((Error) -> Void)? {
        get { callbacks.onError }
        set { callbacks.onError = newValue }
    }

    var isAvailable: Bool {
        provider.descriptor.modelInstallationState.isReady
    }

    var asrRuntimeMetadataSnapshot: ASRRuntimeMetadataSnapshot {
        metadataLock.withLock { runtimeMetadata }
    }

    private let provider: any ASRProvider
    private let defaultLanguage: ASRLanguageCapability
    private let callbacks = ASRCoreBackedCallbackBox()
    private let lifecycleLock = NSLock()
    private let metadataLock = NSLock()
    private var configuredLanguage: ASRLanguageCapability?
    private var sessionTask: Task<any ASRSession, Error>?
    private var eventTask: Task<Void, Never>?
    private var frameConsumerTask: Task<Void, Never>?
    private var frameContinuation: AsyncStream<AudioFrame>.Continuation?
    private var isFinishing = false
    private var hasAcceptedAudioFrame = false
    private var generation: UInt64 = 0
    private var runtimeMetadata = ASRRuntimeMetadataSnapshot()
    private var startedAt: ContinuousClock.Instant?

    init(
        provider: any ASRProvider,
        defaultLanguage: ASRLanguageCapability
    ) {
        self.provider = provider
        self.defaultLanguage = defaultLanguage
    }

    func configure(locale: Locale) {
        let language = ASRLanguageCapability(
            bcp47Tag: locale.identifier.replacingOccurrences(of: "_", with: "-")
        )
        lifecycleLock.withLock {
            configuredLanguage = language
        }
    }

    func start() throws {
        AppLogger.audio.debug(
            "ASRCoreBackedASREngine start requested available=\(isAvailable) configuredLanguage=\(configuredLanguage?.bcp47Tag ?? defaultLanguage.bcp47Tag)"
        )
        guard isAvailable else {
            AppLogger.audio.warning("ASRCoreBackedASREngine start blocked model not loaded")
            throw ASREngineError.modelNotLoaded
        }

        let provider = provider
        let language = lifecycleLock.withLock { configuredLanguage ?? defaultLanguage }
        let callbacks = callbacks
        metadataLock.withLock {
            runtimeMetadata = ASRRuntimeMetadataSnapshot()
        }
        let generation = lifecycleLock.withLock {
            self.generation &+= 1
            isFinishing = false
            hasAcceptedAudioFrame = false
            startedAt = ContinuousClock.now
            return self.generation
        }
        AppLogger.audio.debug("ASRCoreBackedASREngine start generation=\(generation)")
        var frameContinuation: AsyncStream<AudioFrame>.Continuation?
        let frameStream = AsyncStream<AudioFrame>(bufferingPolicy: .bufferingNewest(96)) { continuation in
            frameContinuation = continuation
        }
        let sessionTask = Task<any ASRSession, Error> {
            let session = try await provider.makeSession(language: language)
            try await session.start()
            return session
        }
        lifecycleLock.withLock {
            self.sessionTask = sessionTask
            self.frameContinuation = frameContinuation
        }
        let frameConsumerTask = Task {
            do {
                let session = try await sessionTask.value
                for await frame in frameStream {
                    guard self.isCurrentGeneration(generation) else { break }
                    try await session.accept(frame)
                }
            } catch is CancellationError {
            } catch {
                AppLogger.audio.warning(
                    "ASRCoreBackedASREngine frame consumer failed generation=\(generation) reason=\(error.localizedDescription)"
                )
                guard self.isCurrentGeneration(generation) else { return }
                await MainActor.run {
                    callbacks.onError?(error)
                }
            }
        }
        let eventTask = Task {
            do {
                let session = try await sessionTask.value
                for await event in session.events {
                    guard self.isCurrentGeneration(generation) else { break }
                    self.record(event)
                    await Self.deliver(event, callbacks: callbacks)
                }
            } catch is CancellationError {
            } catch {
                AppLogger.audio.warning(
                    "ASRCoreBackedASREngine event loop failed generation=\(generation) reason=\(error.localizedDescription)"
                )
                guard self.isCurrentGeneration(generation) else { return }
                await MainActor.run {
                    callbacks.onError?(error)
                }
            }
        }
        lifecycleLock.withLock {
            if self.generation == generation {
                self.frameConsumerTask = frameConsumerTask
                self.eventTask = eventTask
            } else {
                frameConsumerTask.cancel()
                eventTask.cancel()
            }
        }
    }

    func appendAudioFrame(_ frame: AudioFrame) {
        let continuation = lifecycleLock.withLock {
            guard sessionTask != nil, !isFinishing, let frameContinuation else {
                AppLogger.audio.warning("ASRCoreBackedASREngine appendAudioFrame skipped (not recording)")
                return Optional<AsyncStream<AudioFrame>.Continuation>.none
            }
            if !frame.samples.isEmpty {
                hasAcceptedAudioFrame = true
            }
            return frameContinuation
        }
        guard let continuation else { return }
        switch continuation.yield(frame) {
        case .dropped:
            recordDroppedFrame()
        case .enqueued, .terminated:
            break
        @unknown default:
            break
        }
    }

    func endAudio() {
        let snapshot = lifecycleLock.withLock {
            guard let sessionTask else {
                AppLogger.audio.warning("ASRCoreBackedASREngine endAudio skipped (no active session)")
                return Optional<(
                    sessionTask: Task<any ASRSession, Error>,
                    eventTask: Task<Void, Never>?,
                    frameConsumerTask: Task<Void, Never>?,
                    frameContinuation: AsyncStream<AudioFrame>.Continuation?,
                    generation: UInt64,
                    hasAcceptedAudioFrame: Bool
                )>.none
            }
            isFinishing = true
            let snapshot = (
                sessionTask: sessionTask,
                eventTask: eventTask,
                frameConsumerTask: frameConsumerTask,
                frameContinuation: frameContinuation,
                generation: generation,
                hasAcceptedAudioFrame: hasAcceptedAudioFrame
            )
            frameContinuation = nil
            return snapshot
        }
        guard let snapshot else { return }
        let callbacks = callbacks
        snapshot.frameContinuation?.finish()
        guard snapshot.hasAcceptedAudioFrame else {
            AppLogger.audio.debug("ASRCoreBackedASREngine endAudio with no accepted frames generation=\(snapshot.generation)")
            snapshot.frameConsumerTask?.cancel()
            snapshot.eventTask?.cancel()
            callbacks.onTranscription?("", true)
            Task {
                if let session = try? await snapshot.sessionTask.value {
                    await session.cancel()
                }
            }
            return
        }
        Task {
            do {
                await snapshot.frameConsumerTask?.value
                guard self.isCurrentGeneration(snapshot.generation) else { return }
                AppLogger.audio.debug("ASRCoreBackedASREngine finishing with frames generation=\(snapshot.generation)")
                let session = try await snapshot.sessionTask.value
                try await session.finish()
            } catch is CancellationError {
            } catch {
                AppLogger.audio.warning(
                    "ASRCoreBackedASREngine endAudio failed generation=\(snapshot.generation) reason=\(error.localizedDescription)"
                )
                guard self.isCurrentGeneration(snapshot.generation) else { return }
                await MainActor.run {
                    callbacks.onError?(error)
                }
            }
        }
    }

    func stop() {
        let snapshot = lifecycleLock.withLock {
            AppLogger.audio.debug("ASRCoreBackedASREngine stop generation=\(generation)")
            generation &+= 1
            isFinishing = true
            let snapshot = (
                frameContinuation: frameContinuation,
                frameConsumerTask: frameConsumerTask,
                eventTask: eventTask,
                sessionTask: sessionTask
            )
            frameContinuation = nil
            frameConsumerTask = nil
            eventTask = nil
            sessionTask = nil
            hasAcceptedAudioFrame = false
            startedAt = nil
            return snapshot
        }
        snapshot.frameContinuation?.finish()
        snapshot.frameConsumerTask?.cancel()
        snapshot.eventTask?.cancel()
        snapshot.sessionTask?.cancel()
        Task {
            if let session = try? await snapshot.sessionTask?.value {
                await session.cancel()
            }
        }
    }

    func cancel() {
        let snapshot = lifecycleLock.withLock {
            AppLogger.audio.debug("ASRCoreBackedASREngine cancel generation=\(generation)")
            generation &+= 1
            let snapshot = (
                frameContinuation: frameContinuation,
                frameConsumerTask: frameConsumerTask,
                eventTask: eventTask,
                sessionTask: sessionTask
            )
            frameConsumerTask = nil
            frameContinuation = nil
            eventTask = nil
            sessionTask = nil
            isFinishing = false
            hasAcceptedAudioFrame = false
            startedAt = nil
            return snapshot
        }
        snapshot.frameContinuation?.finish()
        snapshot.frameConsumerTask?.cancel()
        snapshot.eventTask?.cancel()
        snapshot.sessionTask?.cancel()
        Task {
            if let session = try? await snapshot.sessionTask?.value {
                await session.cancel()
            }
        }
    }

    private func record(_ event: ASREvent) {
        let finalLatencyMs: Int?
        let startedAt = lifecycleLock.withLock { self.startedAt }
        if case .final = event, let startedAt {
            finalLatencyMs = Self.milliseconds(from: startedAt.duration(to: ContinuousClock.now))
        } else {
            finalLatencyMs = nil
        }

        metadataLock.withLock {
            runtimeMetadata.sessionID = event.sessionID.rawValue

            switch event {
            case .partial(_, let transcript):
                runtimeMetadata.audioDurationMs = Self.milliseconds(from: transcript.audioDuration)
            case .metrics(_, _, let metrics):
                runtimeMetadata.audioDurationMs = Self.milliseconds(from: metrics.audioDuration)
                runtimeMetadata.droppedFrameCount = Int(clamping: metrics.droppedFrameCount)
            case .failure(_, _, let error):
                runtimeMetadata.errorCode = error.category.rawValue
            case .final:
                runtimeMetadata.finalLatencyMs = finalLatencyMs
            case .preparing, .ready, .speechStarted, .endpoint:
                break
            }
        }
    }

    private func recordDroppedFrame() {
        metadataLock.withLock {
            runtimeMetadata.droppedFrameCount = (runtimeMetadata.droppedFrameCount ?? 0) + 1
        }
    }

    private func isCurrentGeneration(_ expectedGeneration: UInt64) -> Bool {
        lifecycleLock.withLock {
            generation == expectedGeneration && sessionTask != nil
        }
    }

    private static func milliseconds(from duration: Duration) -> Int {
        let components = duration.components
        let milliseconds = components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000
        return Int(clamping: milliseconds)
    }

    @MainActor
    private static func deliver(
        _ event: ASREvent,
        callbacks: ASRCoreBackedCallbackBox
    ) {
        switch event {
        case .partial(_, let transcript):
            let text = transcript.stablePrefix + transcript.unstableSuffix
            guard !text.isEmpty else { return }
            callbacks.onTranscription?(text, false)
        case .final(_, _, let text):
            callbacks.onTranscription?(text, true)
        case .failure(_, _, let error):
            callbacks.onError?(ASRCoreBackedASREngineError.failure(error))
        case .preparing, .ready, .speechStarted, .endpoint, .metrics:
            break
        }
    }
}

enum ASRCoreBackedASREngineError: Error, LocalizedError {
    case failure(ASRError)

    var errorDescription: String? {
        switch self {
        case .failure(let error):
            return ASRErrorUserMessage.message(for: error)
        }
    }
}
