import Foundation
import VoxFlowModelStore

/// 把 R2T2 的流式 runtime 接到 ModelStore 的预热/canary 流程上。
///
/// 这里只做「加载 → 编译确认 → 跑一段 canary」的桥接：原子安装、断点续传、完整性校验、
/// repair 和删除全部复用 `VoxFlowModelStore` 既有实现，不在这里重造。
public actor R2T2ModelRuntimePreparer: ModelRuntimePreparing {
    private let streamFactory: any R2T2StreamMaking
    private let languageHint: String?
    private var stream: (any R2T2StreamingEngine)?

    public init(
        streamFactory: any R2T2StreamMaking = VendoredR2T2StreamFactory(),
        languageHint: String? = "zh"
    ) {
        self.streamFactory = streamFactory
        self.languageHint = languageHint
    }

    public func load(installation: ModelInstallation) async throws {
        stream = try await streamFactory.makeStream(
            modelURL: installation.installedRoot,
            languageHint: languageHint,
            contextPrompt: nil
        )
    }

    public func compile(installation: ModelInstallation) async throws {
        guard stream != nil else {
            throw R2T2ProviderError.preparationFailed("R2T2 prewarm stream is not loaded.")
        }
    }

    public func transcribeCanary(
        installation: ModelInstallation,
        audio: ModelCanaryAudio
    ) async throws -> String {
        guard let stream else {
            throw R2T2ProviderError.preparationFailed("R2T2 prewarm stream is not loaded.")
        }
        defer { self.stream = nil }
        if !audio.samples.isEmpty {
            _ = stream.push(audio.samples)
        }
        _ = stream.finish()
        // canary 报告需要的是已确认全文；finish 只返回尾部增量。
        return stream.committedText
    }
}

/// 预检否决时替代真实 runtime：每一步都以结构化 blocker 失败，而不是等模型加载到一半才炸。
public actor R2T2UnsupportedRuntimePreparer: ModelRuntimePreparing {
    private let blocker: R2T2PreflightBlocker

    public init(blocker: R2T2PreflightBlocker) {
        self.blocker = blocker
    }

    public func load(installation: ModelInstallation) async throws {
        throw R2T2ProviderError.preflightBlocked(blocker)
    }

    public func compile(installation: ModelInstallation) async throws {
        throw R2T2ProviderError.preflightBlocked(blocker)
    }

    public func transcribeCanary(
        installation: ModelInstallation,
        audio: ModelCanaryAudio
    ) async throws -> String {
        throw R2T2ProviderError.preflightBlocked(blocker)
    }
}

public struct R2T2ModelReadinessRunner: Sendable {
    /// 一段 1 kHz 探针音，只用来走通「加载 → 解码 → finish」这段路径；不校验识别准确率。
    public static var canaryAudio: ModelCanaryAudio {
        ModelCanaryAudio(
            samples: (0..<16_000).map { index in
                let time = Double(index) / 16_000
                return Float(0.08 * sin(2 * Double.pi * 1_000 * time))
            },
            sampleRate: 16_000,
            expectedTokens: []
        )
    }

    private let runner: ModelPrewarmCanaryRunner
    private let metadataProvider: @Sendable () -> R2T2ModelStoreMetadata
    private let runtimeFactory: @Sendable (URL) -> any ModelRuntimePreparing
    private let canaryAudio: ModelCanaryAudio

    public init(
        runner: ModelPrewarmCanaryRunner = ModelPrewarmCanaryRunner(),
        metadataProvider: @escaping @Sendable () -> R2T2ModelStoreMetadata = {
            R2T2ManifestCatalog.metadata
        },
        runtimeFactory: @escaping @Sendable (URL) -> any ModelRuntimePreparing = { _ in
            switch R2T2RuntimePreflight.evaluate() {
            case .usable, .usableWithCaution:
                return R2T2ModelRuntimePreparer()
            case .blocked(let blocker):
                return R2T2UnsupportedRuntimePreparer(blocker: blocker)
            }
        },
        canaryAudio: ModelCanaryAudio = R2T2ModelReadinessRunner.canaryAudio
    ) {
        self.runner = runner
        self.metadataProvider = metadataProvider
        self.runtimeFactory = runtimeFactory
        self.canaryAudio = canaryAudio
    }

    @discardableResult
    public func prepare(modelURL: URL) async throws -> ModelPrewarmReport {
        let metadata = metadataProvider()
        let installation = ModelInstallation(
            modelID: metadata.modelID,
            version: metadata.version,
            installedRoot: modelURL
        )
        return try await runner.prepare(
            installation: installation,
            canaryAudio: canaryAudio,
            runtime: runtimeFactory(modelURL)
        )
    }
}
