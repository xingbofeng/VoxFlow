import Foundation
import VoxFlowASRCore

public enum NVIDIANemotronRuntimeRoute: String, CaseIterable, Equatable, Sendable {
    case macOSLocal
    case externalWorker
    case remoteService
}

public struct NVIDIANemotronModelMetadata: Equatable, Sendable {
    public static let current = NVIDIANemotronModelMetadata(
        modelID: "nvidia/nemotron-3.5-asr-streaming-0.6b",
        sourceURL: URL(string: "https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b")!,
        licenseID: "openmdw-1.1",
        parameterCount: "600M",
        libraryName: "nemo",
        runtimeEngine: "NeMo 26.06",
        modelArtifactFileName: "nemotron-3.5-asr-streaming-0.6b.nemo",
        approximateRepositoryStorageBytes: 4_740_254_495,
        requiredRuntimeDependencies: ["Python >= 3.11", "Cython", "PyTorch", "NVIDIA NeMo"],
        streamingInferenceScript: "examples/asr/asr_cache_aware_streaming/speech_to_text_cache_aware_streaming_infer.py",
        streamingParameters: ["model_path", "dataset_manifest", "batch_size", "target_lang", "att_context_size", "strip_lang_tags", "output_path"],
        languagePromptModes: ["target_lang=<lang_id>", "target_lang=auto"],
        streamingChunkDurationsMilliseconds: [80, 160, 320, 560, 1120],
        inputFormats: ["wav", "string"],
        requiresMonoAudio: true,
        inputSampleRateHertz: nil,
        runtimeRoutesUnderEvaluation: NVIDIANemotronRuntimeRoute.allCases,
        allowsModelDownload: false,
        canAdvertiseReady: false
    )

    public let modelID: String
    public let sourceURL: URL
    public let licenseID: String
    public let parameterCount: String
    public let libraryName: String
    public let runtimeEngine: String
    public let modelArtifactFileName: String
    public let approximateRepositoryStorageBytes: Int
    public let requiredRuntimeDependencies: [String]
    public let streamingInferenceScript: String
    public let streamingParameters: [String]
    public let languagePromptModes: [String]
    public let streamingChunkDurationsMilliseconds: [Int]
    public let inputFormats: [String]
    public let requiresMonoAudio: Bool
    public let inputSampleRateHertz: Int?
    public let runtimeRoutesUnderEvaluation: [NVIDIANemotronRuntimeRoute]
    public let allowsModelDownload: Bool
    public let canAdvertiseReady: Bool
}

public enum NVIDIANemotronProviderDescriptor {
    public static let runtimeUnsupportedReason =
        "NVIDIA Nemotron ASR CoreML streaming runtime requires Apple Silicon."

    public static func descriptor(
        modelInstallationState: ASRModelInstallationState
    ) -> ASRProviderDescriptor {
        ASRProviderDescriptor(
            id: ASRProviderID(rawValue: "nvidia_nemotron_3_5_asr_streaming_0_6b"),
            displayName: "NVIDIA Nemotron ASR 0.6B",
            modelInstallationState: modelInstallationState,
            supportedLanguages: [
                ASRLanguageCapability(bcp47Tag: "zh-CN"),
                ASRLanguageCapability(bcp47Tag: "zh-TW"),
                ASRLanguageCapability(bcp47Tag: "en-US"),
                ASRLanguageCapability(bcp47Tag: "ja-JP"),
                ASRLanguageCapability(bcp47Tag: "ko-KR"),
            ],
            streamingSemantics: .nativeStreaming
        )
    }

    public static let current = descriptor(
        modelInstallationState: .runtimeUnsupported(reason: runtimeUnsupportedReason)
    )
}
