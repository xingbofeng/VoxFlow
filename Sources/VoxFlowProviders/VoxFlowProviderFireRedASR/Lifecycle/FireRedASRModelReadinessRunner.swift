import Foundation
import VoxFlowModelStore

/// 把 FireRedASR2-AED 的识别器接到 ModelStore 的预热 / canary 流程上。
///
/// 安装完 1.24 GB 权重后立刻跑一次「加载 → 解码 → finish」，把 ORT session 创建与 800 MB
/// encoder 的加载成本从首次听写挪到安装时；canary 失败就不标记为 ready，让用户走 repair。
///
/// 与 R2T2 的对应实现同构，复用 `VoxFlowModelStore` 既有的 `ModelPrewarmCanaryRunner`。
public actor FireRedASRRuntimePreparer: ModelRuntimePreparing {
    private let transcriberFactory: any FireRedASRTranscriberMaking
    private var transcriber: (any FireRedASRTranscribing)?

    public init(transcriberFactory: any FireRedASRTranscriberMaking = FireRedASRTranscriberFactory()) {
        self.transcriberFactory = transcriberFactory
    }

    public func load(installation: ModelInstallation) async throws {
        transcriber = try await transcriberFactory.makeTranscriber(
            directoryURL: installation.installedRoot
        )
    }

    public func compile(installation: ModelInstallation) async throws {
        guard transcriber != nil else {
            throw FireRedASRProviderError.preparationFailed(
                "FireRedASR2-AED prewarm recognizer is not loaded."
            )
        }
    }

    public func transcribeCanary(
        installation: ModelInstallation,
        audio: ModelCanaryAudio
    ) async throws -> String {
        guard let transcriber else {
            throw FireRedASRProviderError.preparationFailed(
                "FireRedASR2-AED prewarm recognizer is not loaded."
            )
        }
        defer { self.transcriber = nil }
        return try await transcriber.transcribe(audio: audio.samples)
    }
}

public struct FireRedASRModelReadinessRunner: Sendable {
    /// 一段 1 kHz 探针音，只用来走通「加载 → 解码」这段路径，不校验识别准确率。
    ///
    /// 本机实测：1 kHz / 0.08 幅值的 1 秒音频在 AED int8 上输出 `<sil>`（1 个 token），
    /// 非空，因此能通过 `ModelPrewarmReport.isReady` 的判据。
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
    private let runtimeFactory: @Sendable (URL) -> any ModelRuntimePreparing
    private let canaryAudio: ModelCanaryAudio

    public init(
        runner: ModelPrewarmCanaryRunner = ModelPrewarmCanaryRunner(),
        runtimeFactory: @escaping @Sendable (URL) -> any ModelRuntimePreparing = { _ in
            FireRedASRRuntimePreparer()
        },
        canaryAudio: ModelCanaryAudio = FireRedASRModelReadinessRunner.canaryAudio
    ) {
        self.runner = runner
        self.runtimeFactory = runtimeFactory
        self.canaryAudio = canaryAudio
    }

    @discardableResult
    public func prepare(modelURL: URL) async throws -> ModelPrewarmReport {
        let installation = ModelInstallation(
            modelID: ModelID(rawValue: FireRedASRModel.directoryName),
            version: FireRedASRModel.directoryName,
            installedRoot: modelURL
        )
        let report = try await runner.prepare(
            installation: installation,
            canaryAudio: canaryAudio,
            runtime: runtimeFactory(modelURL)
        )
        // canary 没有 expectedTokens，所以「解码返回空」不会让 runner 抛错。权重能加载但解不出
        // 任何 token 说明模型或 tokens 文件有问题，这里必须自己把它判为失败，否则用户会拿到一个
        // 标记成 ready、实际不可用的模型。
        guard report.isReady else {
            throw ModelPrewarmError.emptyCanaryOutput
        }
        return report
    }
}
