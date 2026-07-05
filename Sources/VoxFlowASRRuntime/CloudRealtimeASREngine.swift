import Foundation
import VoxFlowAudio
import VoxFlowProviderCloudCore

/// AsyncStream 音频缓冲上限，三家云 provider 共用。
private let cloudRealtimeAudioChunkBufferLimit = 96

/// 跨平台云实时 ASR engine 基类，泛型化 `Configuration` 与 `Message`。
///
/// 承载三家云 provider 共享的运行期逻辑：
/// - generation 跟踪与取消
/// - AsyncStream<Data> 音频 continuation 与缓冲
/// - PCM16 编码、采样率校验
/// - dropped frame 计数、runtime metadata
/// - 主线程回调派发、错误传播
///
/// provider 差异点（配置完整性、错误类型、消息拼接、transcribe 驱动）通过闭包注入，
/// 因此可以接受 `any *StreamingClient` existential 而不要求具体 client 类型满足泛型约束。
public final class CloudRealtimeASREngine<Configuration: Sendable, Message: Sendable>: ASREngine, ASRRuntimeMetadataProviding, @unchecked Sendable {
    public typealias Transcribe = @Sendable (Configuration, AsyncStream<Data>, @escaping @Sendable (Message) -> Void) async throws -> Void
    public typealias ConfigurationProvider = @Sendable () throws -> Configuration
    public typealias ConfigurationCompleteCheck = @Sendable (Configuration) -> Bool
    public typealias MessageInterpreter = @Sendable (Message, inout CloudRealtimeASRTranscriptState) -> CloudRealtimeASREmission?
    public typealias ErrorBuilder = @Sendable () -> Error
    public typealias SampleRateErrorBuilder = @Sendable (Int) -> Error

    public var onTranscription: ((String, Bool) -> Void)?
    public var onError: ((Error) -> Void)?

    private let lock = NSLock()
    private let transcribe: Transcribe
    private let logger: any ASRSessionLogger
    private let logLabel: String
    private let sessionIDPrefix: String
    private let supportedSampleRate: Int
    private let configurationProvider: ConfigurationProvider
    private let isConfigurationComplete: ConfigurationCompleteCheck
    private let missingConfigurationError: ErrorBuilder
    private let inconsistentSampleRateError: SampleRateErrorBuilder
    private let unsupportedSampleRateError: SampleRateErrorBuilder
    private let interpretMessage: MessageInterpreter

    private var generation: UUID?
    private var audioContinuation: AsyncStream<Data>.Continuation?
    private var streamingTask: Task<Void, Never>?
    private var sampleRate: Int?
    private var transcriptState = CloudRealtimeASRTranscriptState()
    private var runtimeMetadata = ASRRuntimeMetadataSnapshot()

    public init(
        transcribe: @escaping Transcribe,
        logger: any ASRSessionLogger,
        logLabel: String,
        sessionIDPrefix: String,
        supportedSampleRate: Int = 16_000,
        configurationProvider: @escaping ConfigurationProvider,
        isConfigurationComplete: @escaping ConfigurationCompleteCheck,
        missingConfigurationError: @escaping ErrorBuilder,
        inconsistentSampleRateError: @escaping SampleRateErrorBuilder,
        unsupportedSampleRateError: @escaping SampleRateErrorBuilder,
        interpretMessage: @escaping MessageInterpreter
    ) {
        self.transcribe = transcribe
        self.logger = logger
        self.logLabel = logLabel
        self.sessionIDPrefix = sessionIDPrefix
        self.supportedSampleRate = supportedSampleRate
        self.configurationProvider = configurationProvider
        self.isConfigurationComplete = isConfigurationComplete
        self.missingConfigurationError = missingConfigurationError
        self.inconsistentSampleRateError = inconsistentSampleRateError
        self.unsupportedSampleRateError = unsupportedSampleRateError
        self.interpretMessage = interpretMessage
    }

    /// 便利构造器：直接接收 `CloudASRStreamingClient` 具体 client。
    public convenience init<Client: CloudASRStreamingClient>(
        client: Client,
        logger: any ASRSessionLogger,
        logLabel: String,
        sessionIDPrefix: String,
        supportedSampleRate: Int = 16_000,
        configurationProvider: @escaping ConfigurationProvider,
        isConfigurationComplete: @escaping ConfigurationCompleteCheck,
        missingConfigurationError: @escaping ErrorBuilder,
        inconsistentSampleRateError: @escaping SampleRateErrorBuilder,
        unsupportedSampleRateError: @escaping SampleRateErrorBuilder,
        interpretMessage: @escaping MessageInterpreter
    ) where Configuration == Client.Configuration, Message == Client.Message {
        self.init(
            transcribe: { configuration, audioChunks, onMessage in
                try await client.transcribe(configuration: configuration, audioChunks: audioChunks, onMessage: onMessage)
            },
            logger: logger,
            logLabel: logLabel,
            sessionIDPrefix: sessionIDPrefix,
            supportedSampleRate: supportedSampleRate,
            configurationProvider: configurationProvider,
            isConfigurationComplete: isConfigurationComplete,
            missingConfigurationError: missingConfigurationError,
            inconsistentSampleRateError: inconsistentSampleRateError,
            unsupportedSampleRateError: unsupportedSampleRateError,
            interpretMessage: interpretMessage
        )
    }

    public var isAvailable: Bool {
        guard let configuration = try? configurationProvider() else { return false }
        return isConfigurationComplete(configuration)
    }

    public var asrRuntimeMetadataSnapshot: ASRRuntimeMetadataSnapshot {
        lock.withLock { runtimeMetadata }
    }

    public func configure(locale: Locale) {}

    public func start() throws {
        let configuration = try configurationProvider()
        let complete = isConfigurationComplete(configuration)
        logger.debug("\(logLabel) start attempt sessionID=\(UUID().uuidString) complete=\(complete)")
        guard complete else {
            logger.warning("\(logLabel) start blocked: configuration incomplete")
            throw missingConfigurationError()
        }
        let generation = UUID()
        logger.debug("\(logLabel) start generation=\(generation.uuidString)")
        let stream = AsyncStream<Data>(bufferingPolicy: .bufferingNewest(cloudRealtimeAudioChunkBufferLimit)) { continuation in
            lock.withLock {
                audioContinuation = continuation
            }
        }
        lock.withLock {
            streamingTask?.cancel()
            transcriptState = CloudRealtimeASRTranscriptState()
            sampleRate = nil
            self.generation = generation
            runtimeMetadata = ASRRuntimeMetadataSnapshot(sessionID: "\(sessionIDPrefix)-\(generation.uuidString)")
        }
        streamingTask = Task { [weak self] in
            guard let self else { return }
            let startedAt = Date()
            do {
                try await self.transcribe(configuration, stream) { [weak self] message in
                    self?.handle(message, generation: generation)
                }
                guard self.isCurrent(generation), !Task.isCancelled else { return }
                self.logger.info("\(self.logLabel) completed generation=\(generation.uuidString)")
                self.lock.withLock {
                    self.runtimeMetadata.finalLatencyMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
                }
            } catch {
                self.logger.warning(
                    "\(self.logLabel) transcribe failed generation=\(generation.uuidString) reason=\(error.localizedDescription)"
                )
                guard self.isCurrent(generation), !Task.isCancelled else { return }
                self.lock.withLock {
                    self.runtimeMetadata.errorCode = String(describing: type(of: error))
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isCurrent(generation) else { return }
                    self.logger.warning("\(self.logLabel) onError generation=\(generation.uuidString)")
                    self.onError?(error)
                }
            }
        }
    }

    public func appendAudioFrame(_ frame: AudioFrame) {
        let encoded: Data
        do {
            encoded = try encode(frame)
        } catch {
            logger.warning("\(logLabel) encode failed: \(error.localizedDescription)")
            let currentGeneration = lock.withLock { generation }
            guard let currentGeneration else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrent(currentGeneration) else { return }
                self.onError?(error)
            }
            return
        }
        let yieldResult = lock.withLock { audioContinuation }?.yield(encoded)
        if let yieldResult, case .dropped = yieldResult {
            lock.withLock {
                runtimeMetadata.droppedFrameCount = (runtimeMetadata.droppedFrameCount ?? 0) + 1
            }
            logger.debug("\(logLabel) dropped frame")
        }
        if lock.withLock({ audioContinuation == nil }) {
            logger.debug("\(logLabel) append ignored: stream not started")
            return
        }
        logger.debug("\(logLabel) appended frame sampleRate=\(frame.sampleRate)")
    }

    public func endAudio() {
        logger.debug(
            "\(logLabel) endAudio generation=\(lock.withLock { generation?.uuidString ?? "nil" })"
        )
        lock.withLock {
            audioContinuation?.finish()
            audioContinuation = nil
        }
    }

    public func stop() {
        logger.debug("\(logLabel) stop generation=\(lock.withLock { generation?.uuidString ?? "nil" })")
        cancel()
    }

    public func cancel() {
        lock.withLock {
            generation = nil
            audioContinuation?.finish()
            audioContinuation = nil
            streamingTask?.cancel()
            streamingTask = nil
            transcriptState = CloudRealtimeASRTranscriptState()
            sampleRate = nil
        }
    }

    private func encode(_ frame: AudioFrame) throws -> Data {
        try lock.withLock {
            if let sampleRate, sampleRate != frame.sampleRate {
                throw inconsistentSampleRateError(frame.sampleRate)
            }
            sampleRate = frame.sampleRate
            guard frame.sampleRate == supportedSampleRate else {
                throw unsupportedSampleRateError(frame.sampleRate)
            }
            runtimeMetadata.audioDurationMs = Int(
                Double(frame.startSample + UInt64(frame.samples.count)) / Double(frame.sampleRate) * 1_000
            )
            return PCM16Encoding.pcm16Data(samples: frame.samples)
        }
    }

    private func handle(_ message: Message, generation: UUID) {
        let emission = lock.withLock { () -> CloudRealtimeASREmission? in
            guard self.generation == generation else { return nil }
            return interpretMessage(message, &transcriptState)
        }
        guard let emission else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(generation) else { return }
            self.logger.debug(
                "\(self.logLabel) emit textLen=\(emission.text.count) final=\(emission.isFinal) generation=\(generation.uuidString)"
            )
            self.onTranscription?(emission.text, emission.isFinal)
        }
    }

    private func isCurrent(_ generation: UUID) -> Bool {
        lock.withLock { self.generation == generation }
    }
}
