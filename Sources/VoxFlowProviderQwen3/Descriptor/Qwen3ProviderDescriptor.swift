import VoxFlowASRCore

public enum Qwen3ProviderDescriptor {
    public static func descriptor(
        modelInstallationState: VoxFlowASRCore.ASRModelInstallationState,
        variant: Qwen3ModelVariant = .qwen06CoreMLInt8
    ) -> VoxFlowASRCore.ASRProviderDescriptor {
        VoxFlowASRCore.ASRProviderDescriptor(
            id: VoxFlowASRCore.ASRProviderID(rawValue: "qwen3_asr"),
            displayName: "Qwen3-ASR",
            modelInstallationState: modelInstallationState,
            supportedLanguages: [
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "zh-CN"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "zh-TW"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "en-US"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "ja-JP"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "ko-KR"),
            ],
            streamingSemantics: streamingSemantics(for: variant)
        )
    }

    private static func streamingSemantics(
        for variant: Qwen3ModelVariant
    ) -> VoxFlowASRCore.ASRStreamingSemantics {
        switch variant {
        case .qwen06CoreMLInt8:
            return .nativeStreaming
        case .qwen17MLX4Bit:
            return .companionPartialFinal
        }
    }
}
