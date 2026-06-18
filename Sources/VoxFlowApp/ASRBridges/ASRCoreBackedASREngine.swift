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
    private let metadataLock = NSLock()
    private var configuredLanguage: ASRLanguageCapability?
    private var sessionTask: Task<any ASRSession, Error>?
    private var eventTask: Task<Void, Never>?
    private var frameTask: Task<Void, Never>?
    private var isFinishing = false
    private var hasAcceptedAudioFrame = false
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
        configuredLanguage = ASRLanguageCapability(
            bcp47Tag: locale.identifier.replacingOccurrences(of: "_", with: "-")
        )
    }

    func start() throws {
        guard isAvailable else {
            throw ASREngineError.modelNotLoaded
        }

        let provider = provider
        let language = configuredLanguage ?? defaultLanguage
        let callbacks = callbacks
        isFinishing = false
        hasAcceptedAudioFrame = false
        startedAt = ContinuousClock.now
        metadataLock.withLock {
            runtimeMetadata = ASRRuntimeMetadataSnapshot()
        }
        let sessionTask = Task<any ASRSession, Error> {
            let session = try await provider.makeSession(language: language)
            try await session.start()
            return session
        }
        self.sessionTask = sessionTask
        eventTask = Task {
            do {
                let session = try await sessionTask.value
                for await event in session.events {
                    self.record(event)
                    await Self.deliver(event, callbacks: callbacks)
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    callbacks.onError?(error)
                }
            }
        }
    }

    func appendAudioFrame(_ frame: AudioFrame) {
        guard let sessionTask, !isFinishing else { return }
        if !frame.samples.isEmpty {
            hasAcceptedAudioFrame = true
        }
        let callbacks = callbacks
        let previousTask = frameTask
        frameTask = Task { [previousTask] in
            await previousTask?.value
            guard !Task.isCancelled else { return }
            do {
                let session = try await sessionTask.value
                try await session.accept(frame)
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    callbacks.onError?(error)
                }
            }
        }
    }

    func endAudio() {
        guard let sessionTask else { return }
        isFinishing = true
        let callbacks = callbacks
        guard hasAcceptedAudioFrame else {
            frameTask = nil
            eventTask?.cancel()
            callbacks.onTranscription?("", true)
            Task {
                if let session = try? await sessionTask.value {
                    await session.cancel()
                }
            }
            return
        }
        let pendingFrameTask = frameTask
        Task {
            do {
                await pendingFrameTask?.value
                let session = try await sessionTask.value
                try await session.finish()
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    callbacks.onError?(error)
                }
            }
        }
    }

    func stop() {
        isFinishing = true
        frameTask = nil
    }

    func cancel() {
        frameTask?.cancel()
        eventTask?.cancel()
        let task = sessionTask
        sessionTask?.cancel()
        frameTask = nil
        eventTask = nil
        sessionTask = nil
        isFinishing = false
        hasAcceptedAudioFrame = false
        startedAt = nil
        Task {
            if let session = try? await task?.value {
                await session.cancel()
            }
        }
    }

    private func record(_ event: ASREvent) {
        let finalLatencyMs: Int?
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
            return error.message
        }
    }
}
