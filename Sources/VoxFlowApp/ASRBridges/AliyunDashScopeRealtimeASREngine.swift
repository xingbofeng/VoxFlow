import Foundation
import VoxFlowASRRuntime
import VoxFlowAudio
import VoxFlowProviderAliyunDashScope

final class AliyunDashScopeRealtimeASREngine: ASREngine, ASRRuntimeMetadataProviding, @unchecked Sendable {
    private let base: CloudRealtimeASREngine<AliyunDashScopeRealtimeASRConfiguration, AliyunDashScopeRealtimeASRMessage>

    init(
        client: any AliyunDashScopeRealtimeASRStreamingClient = AliyunDashScopeRealtimeASRClient(),
        configurationProvider: @escaping @Sendable () throws -> AliyunDashScopeRealtimeASRConfiguration
    ) {
        let logger = AppLoggerASRSessionLogger()
        let strongClient = client
        let transcribe: @Sendable (AliyunDashScopeRealtimeASRConfiguration, AsyncStream<Data>, @escaping @Sendable (AliyunDashScopeRealtimeASRMessage) -> Void) async throws -> Void = { configuration, audioChunks, onMessage in
            try await strongClient.transcribe(configuration: configuration, audioChunks: audioChunks, onMessage: onMessage)
        }
        base = CloudRealtimeASREngine(
            transcribe: transcribe,
            logger: logger,
            logLabel: "AliyunDashScopeRealtimeASREngine",
            sessionIDPrefix: "aliyun-dashscope-asr",
            configurationProvider: configurationProvider,
            isConfigurationComplete: { $0.isComplete },
            missingConfigurationError: { AliyunDashScopeRealtimeASRError.missingCredential },
            inconsistentSampleRateError: { _ in AliyunDashScopeRealtimeASRError.inconsistentSampleRate },
            unsupportedSampleRateError: { AliyunDashScopeRealtimeASRError.unsupportedSampleRate($0) },
            interpretMessage: { [logger] message, state in
                logger.debug("AliyunDashScopeRealtimeASREngine handle event=\(message.event.rawValue) final=\(message.isFinalResult)")
                if message.event == .taskFinished {
                    return state.latestText.isEmpty ? nil : CloudRealtimeASREmission(text: state.latestText, isFinal: true)
                }
                guard message.event == .resultGenerated, !message.isHeartbeat else { return nil }
                let text = message.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    state.latestText = CloudRealtimeASRTranscriptAssembler.combine(prefix: state.committedText, text: text)
                    if message.isFinalResult {
                        state.committedText = state.latestText
                    }
                }
                return text.isEmpty ? nil : CloudRealtimeASREmission(text: state.latestText, isFinal: false)
            }
        )
    }

    var onTranscription: ((String, Bool) -> Void)? {
        get { base.onTranscription }
        set { base.onTranscription = newValue }
    }

    var onError: ((Error) -> Void)? {
        get { base.onError }
        set { base.onError = newValue }
    }

    var isAvailable: Bool { base.isAvailable }

    var asrRuntimeMetadataSnapshot: ASRRuntimeMetadataSnapshot {
        base.asrRuntimeMetadataSnapshot
    }

    func configure(locale: Locale) {}

    func start() throws {
        try base.start()
    }

    func appendAudioFrame(_ frame: AudioFrame) {
        base.appendAudioFrame(frame)
    }

    func endAudio() {
        base.endAudio()
    }

    func stop() {
        base.stop()
    }

    func cancel() {
        base.cancel()
    }
}
