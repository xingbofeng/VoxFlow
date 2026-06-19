import Foundation
import VoxFlowModelStore

public struct Qwen3ModelReadinessRunner: Sendable {
    private let runner: ModelPrewarmCanaryRunner
    private let metadataProvider: @Sendable (Qwen3ModelManifest) throws -> Qwen3ModelStoreMetadata
    private let runtimeFactory: @Sendable (URL, Qwen3ModelVariant) -> any ModelRuntimePreparing
    private let canaryAudioFactory: @Sendable (Qwen3ModelVariant) -> ModelCanaryAudio

    public init(
        runner: ModelPrewarmCanaryRunner = ModelPrewarmCanaryRunner(),
        metadataProvider: @escaping @Sendable (Qwen3ModelManifest) throws -> Qwen3ModelStoreMetadata = Qwen3ManifestCatalog.metadata(for:),
        runtimeFactory: @escaping @Sendable (URL, Qwen3ModelVariant) -> any ModelRuntimePreparing = { _, variant in
            let preflight = Qwen3RuntimePreflight.evaluate(variant: variant)
            guard preflight.isSupported else {
                return Qwen3UnsupportedRuntimePreparer(
                    reason: preflight.reason ?? "Qwen3-ASR \(variant.displayModelSize) runtime is unavailable."
                )
            }
            return Qwen3ModelRuntimePreparer(
                sessionFactory: Qwen3StreamingSessionFactoryProvider.factory(for: variant),
                languageHint: "zh"
            )
        },
        canaryAudioFactory: @escaping @Sendable (Qwen3ModelVariant) -> ModelCanaryAudio = { variant in
            switch variant {
            case .qwen06SpeechSwift4Bit, .qwen17SpeechSwift8Bit:
                return Qwen3ModelCanaryAudio.speechSwiftRuntimeProbe
            }
        }
    ) {
        self.runner = runner
        self.metadataProvider = metadataProvider
        self.runtimeFactory = runtimeFactory
        self.canaryAudioFactory = canaryAudioFactory
    }

    @discardableResult
    public func prepare(
        modelURL: URL,
        variant: Qwen3ModelVariant
    ) async throws -> ModelPrewarmReport {
        let manifest = Qwen3ManifestCatalog.manifest(for: variant)
        let metadata = try metadataProvider(manifest)
        let installation = ModelInstallation(
            modelID: metadata.modelID,
            version: metadata.version,
            installedRoot: modelURL
        )
        return try await runner.prepare(
            installation: installation,
            canaryAudio: canaryAudioFactory(variant),
            runtime: runtimeFactory(modelURL, variant)
        )
    }
}

public actor Qwen3UnsupportedRuntimePreparer: ModelRuntimePreparing {
    private let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public func load(installation: ModelInstallation) async throws {
        throw Qwen3ProviderError.runtimeUnsupported(reason)
    }

    public func compile(installation: ModelInstallation) async throws {
        throw Qwen3ProviderError.runtimeUnsupported(reason)
    }

    public func transcribeCanary(
        installation: ModelInstallation,
        audio: ModelCanaryAudio
    ) async throws -> String {
        throw Qwen3ProviderError.runtimeUnsupported(reason)
    }
}
