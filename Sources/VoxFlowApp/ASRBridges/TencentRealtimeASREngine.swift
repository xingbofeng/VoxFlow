import Foundation
import VoxFlowASRRuntime
import VoxFlowAudio
import VoxFlowProviderTencentCloud

final class TencentRealtimeASREngine: ASREngine, ASRRuntimeMetadataProviding, ASRTermPromptConfiguring, @unchecked Sendable {
    private final class TermPromptHolder: @unchecked Sendable {
        private let lock = NSLock()
        private var value: String?
        func get() -> String? { lock.withLock { value } }
        func set(_ prompt: String?) { lock.withLock { value = prompt } }
    }

    private let holder: TermPromptHolder
    private let baseConfigurationProvider: @Sendable () throws -> TencentRealtimeASRConfiguration
    private let base: CloudRealtimeASREngine<TencentRealtimeASRConfiguration, TencentRealtimeASRMessage>

    init(
        client: any TencentRealtimeASRStreamingClient = TencentRealtimeASRClient(),
        configurationProvider: @escaping @Sendable () throws -> TencentRealtimeASRConfiguration
    ) {
        let logger = AppLoggerASRSessionLogger()
        let strongClient = client
        let strongProvider = configurationProvider
        let holder = TermPromptHolder()
        let mergedProvider: @Sendable () throws -> TencentRealtimeASRConfiguration = {
            let baseConfig = try strongProvider()
            return baseConfig.withHotwordList(holder.get())
        }
        let transcribe: @Sendable (TencentRealtimeASRConfiguration, AsyncStream<Data>, @escaping @Sendable (TencentRealtimeASRMessage) -> Void) async throws -> Void = { configuration, audioChunks, onMessage in
            try await strongClient.transcribe(configuration: configuration, audioChunks: audioChunks, onMessage: onMessage)
        }
        base = CloudRealtimeASREngine(
            transcribe: transcribe,
            logger: logger,
            logLabel: "TencentRealtimeASREngine",
            sessionIDPrefix: "tencent-asr",
            configurationProvider: mergedProvider,
            isConfigurationComplete: { $0.isComplete },
            missingConfigurationError: { TencentRealtimeASRError.missingCredential },
            inconsistentSampleRateError: { _ in TencentRealtimeASRError.inconsistentSampleRate },
            unsupportedSampleRateError: { TencentRealtimeASRError.unsupportedSampleRate($0) },
            interpretMessage: { [logger] message, state in
                logger.debug("TencentRealtimeASREngine handle message final=\(message.isFinal) stable=\(message.isStable)")
                let text = message.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    if message.isStable, let index = message.index {
                        state.stableSegments[index] = text
                        state.latestText = CloudRealtimeASRTranscriptAssembler.joinedStablePrefix(state.stableSegments)
                    } else {
                        state.latestText = CloudRealtimeASRTranscriptAssembler.combine(
                            stablePrefix: CloudRealtimeASRTranscriptAssembler.joinedStablePrefix(state.stableSegments),
                            liveText: text
                        )
                    }
                }
                if message.isFinal {
                    return state.latestText.isEmpty ? nil : CloudRealtimeASREmission(text: state.latestText, isFinal: true)
                }
                return text.isEmpty ? nil : CloudRealtimeASREmission(text: state.latestText, isFinal: false)
            }
        )
        self.holder = holder
        self.baseConfigurationProvider = strongProvider
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

    func configureTermPrompt(_ prompt: String?) {
        holder.set(Self.normalizedHotwordList(from: prompt))
    }

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

    private static func normalizedHotwordList(from prompt: String?) -> String? {
        let terms = prompt?
            .components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { term in
                term.contains("|") || ASRHotwordCapabilityMatrix.isValidTencentHotword(term)
            }
            .prefix(128) ?? []
        guard !terms.isEmpty else { return nil }
        return terms.enumerated().map { index, term in
            term.contains("|") ? term : "\(term)|\(ASRHotwordCapabilityMatrix.tencentWeight(forPriorityIndex: index))"
        }.joined(separator: ",")
    }
}

private extension TencentRealtimeASRConfiguration {
    func withHotwordList(_ hotwordList: String?) -> TencentRealtimeASRConfiguration {
        TencentRealtimeASRConfiguration(
            appID: appID,
            secretID: secretID,
            secretKey: secretKey,
            engineModelType: engineModelType,
            voiceFormat: voiceFormat,
            needVAD: needVAD,
            timeoutSeconds: timeoutSeconds,
            hotwordList: hotwordList
        )
    }
}
