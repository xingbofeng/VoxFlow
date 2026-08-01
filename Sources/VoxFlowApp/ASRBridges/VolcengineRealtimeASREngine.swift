import Foundation
import VoxFlowASRRuntime
import VoxFlowAudio
import VoxFlowProviderVolcengine

final class VolcengineRealtimeASREngine: ASREngine, ASRRuntimeMetadataProviding, @unchecked Sendable {
    private let base: CloudRealtimeASREngine<VolcengineRealtimeASRConfiguration, VolcengineRealtimeASRMessage>

    init(
        client: any VolcengineRealtimeASRStreamingClient = VolcengineRealtimeASRClient(),
        configurationProvider: @escaping @Sendable () throws -> VolcengineRealtimeASRConfiguration
    ) {
        let logger = AppLoggerASRSessionLogger()
        let strongClient = client
        let transcribe: @Sendable (VolcengineRealtimeASRConfiguration, AsyncStream<Data>, @escaping @Sendable (VolcengineRealtimeASRMessage) -> Void) async throws -> Void = { configuration, audioChunks, onMessage in
            try await strongClient.transcribe(configuration: configuration, audioChunks: audioChunks, onMessage: onMessage)
        }
        base = CloudRealtimeASREngine(
            transcribe: transcribe,
            logger: logger,
            logLabel: "VolcengineRealtimeASREngine",
            sessionIDPrefix: "volcengine-asr",
            configurationProvider: configurationProvider,
            isConfigurationComplete: { $0.isComplete },
            missingConfigurationError: { VolcengineRealtimeASRError.missingCredential },
            inconsistentSampleRateError: { _ in VolcengineRealtimeASRError.inconsistentSampleRate },
            unsupportedSampleRateError: { VolcengineRealtimeASRError.unsupportedSampleRate($0) },
            interpretMessage: { message, state in
                let text = message.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    state.latestText = text
                }
                if message.isFinal {
                    return state.latestText.isEmpty ? nil : CloudRealtimeASREmission(text: state.latestText, isFinal: true)
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
