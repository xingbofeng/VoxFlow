import Foundation
import VoxFlowASRCore

public enum NVIDIANemotronRuntimeRoute: String, CaseIterable, Equatable, Sendable {
    case speechSwiftCoreML
}

public struct NVIDIANemotronModelMetadata: Equatable, Sendable {
    public static let current = NVIDIANemotronModelMetadata(
        modelID: "aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-CoreML-INT8",
        sourceURL: URL(string: "https://huggingface.co/aufklarer/Nemotron-3.5-ASR-Streaming-0.6B-CoreML-INT8")!,
        licenseID: "openmdw-1.1",
        parameterCount: "600M",
        libraryName: "speech-swift",
        runtimeEngine: "NemotronStreamingASR",
        modelArtifactFileName: "encoder.mlmodelc + decoder.mlmodelc + joint.mlmodelc",
        approximateRepositoryStorageBytes: 0,
        requiredRuntimeDependencies: ["speech-swift", "CoreML"],
        streamingInferenceScript: nil,
        streamingParameters: ["audio", "sampleRate", "language"],
        languagePromptModes: ["language=<bcp47>", "language=auto"],
        streamingChunkDurationsMilliseconds: [320],
        inputFormats: ["Float PCM"],
        requiresMonoAudio: true,
        inputSampleRateHertz: 16_000,
        runtimeRoutesUnderEvaluation: [.speechSwiftCoreML],
        allowsModelDownload: true,
        canAdvertiseReady: true
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
    public let streamingInferenceScript: String?
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
