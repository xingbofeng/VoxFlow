import VoxFlowASRCore

enum ASRProviderExpansionStatus: Equatable {
    case planned
    case inProgress
    case implemented
}

struct ASRProviderExpansionEntry: Equatable {
    let providerID: String
    let variantID: String
    let displayName: String
    let providerTargetName: String
    let modelStoreID: String
    let runtimeRoute: String
    let streamingSemantics: ASRStreamingSemantics
    let status: ASRProviderExpansionStatus
    let requiresModelStoreLifecycle: Bool
    let requiresRuntimePrewarmCanary: Bool
    let requiresProviderLiveSmoke: Bool
    let requiresAppForegroundInputSmoke: Bool
}

enum ASRProviderExpansionMatrix {
    static let documentationPath = "docs/asr-provider-expansion-matrix.md"

    static let task11Entries: [ASRProviderExpansionEntry] = [
        ASRProviderExpansionEntry(
            providerID: ASRProviderID.qwen3,
            variantID: "qwen3-asr-1.7b",
            displayName: "Qwen3-ASR 1.7B",
            providerTargetName: "VoxFlowProviderQwen3",
            modelStoreID: "qwen3-asr-1.7b-mlx-4bit",
            runtimeRoute: "MLX quantized local worker route with bundled worker entrypoint, health probe, managed runtime, and throttled preview/final inference; do not reuse the 0.6B CoreML manifest.",
            streamingSemantics: .companionPartialFinal,
            status: .implemented,
            requiresModelStoreLifecycle: true,
            requiresRuntimePrewarmCanary: true,
            requiresProviderLiveSmoke: true,
            requiresAppForegroundInputSmoke: true
        ),
        ASRProviderExpansionEntry(
            providerID: ASRProviderID.whisper,
            variantID: "whisper-large-v3",
            displayName: "Whisper Large V3",
            providerTargetName: "VoxFlowProviderWhisper",
            modelStoreID: "whisper-large-v3",
            runtimeRoute: "WhisperKit local offline runtime that decodes the complete recording after capture ends; the session always requests transcription instead of translation.",
            streamingSemantics: .offlineFinalOnly,
            status: .implemented,
            requiresModelStoreLifecycle: true,
            requiresRuntimePrewarmCanary: true,
            requiresProviderLiveSmoke: true,
            requiresAppForegroundInputSmoke: true
        ),
        ASRProviderExpansionEntry(
            providerID: ASRProviderID.nvidiaNemotron,
            variantID: "nvidia-nemotron-asr-0.6b",
            displayName: "NVIDIA Nemotron ASR 0.6B",
            providerTargetName: "VoxFlowProviderNVIDIA",
            modelStoreID: "nvidia-nemotron-asr-0.6b-coreml-1120ms",
            runtimeRoute: "FluidAudio CoreML StreamingNemotronMultilingualAsrManager route with native partial callback and final finish; Apple Silicon only.",
            streamingSemantics: .nativeStreaming,
            status: .implemented,
            requiresModelStoreLifecycle: true,
            requiresRuntimePrewarmCanary: true,
            requiresProviderLiveSmoke: true,
            requiresAppForegroundInputSmoke: true
        ),
        ASRProviderExpansionEntry(
            providerID: ASRProviderID.funASR,
            variantID: "funasr-fp32",
            displayName: "FunASR Nano FP32",
            providerTargetName: "VoxFlowProviderFunASR",
            modelStoreID: "funasr-nano-fp32",
            runtimeRoute: "Sherpa-ONNX FP32 variant sharing the FunASR provider target with rolling cumulative partial transcription.",
            streamingSemantics: .rollingWindowConfirmedSegments,
            status: .implemented,
            requiresModelStoreLifecycle: true,
            requiresRuntimePrewarmCanary: true,
            requiresProviderLiveSmoke: true,
            requiresAppForegroundInputSmoke: true
        ),
        ASRProviderExpansionEntry(
            providerID: ASRProviderID.paraformer,
            variantID: "paraformer",
            displayName: "Paraformer",
            providerTargetName: "VoxFlowProviderParaformer",
            modelStoreID: "paraformer-large-zh-coreml-int8",
            runtimeRoute: "New provider target using FluidAudio Paraformer CoreML; legacy App runtime and old Paraformer selection paths stay removed.",
            streamingSemantics: .rollingWindowConfirmedSegments,
            status: .implemented,
            requiresModelStoreLifecycle: true,
            requiresRuntimePrewarmCanary: true,
            requiresProviderLiveSmoke: true,
            requiresAppForegroundInputSmoke: true
        ),
    ]
}
