import VoxFlowASRCore

public enum FireRedASRProviderDescriptor {
    public static func descriptor(
        modelInstallationState: VoxFlowASRCore.ASRModelInstallationState
    ) -> VoxFlowASRCore.ASRProviderDescriptor {
        VoxFlowASRCore.ASRProviderDescriptor(
            id: VoxFlowASRCore.ASRProviderID(rawValue: "fireredasr"),
            displayName: "FireRedASR2-AED",
            modelInstallationState: modelInstallationState,
            supportedLanguages: [
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "zh-CN"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "zh-TW"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "en-US"),
            ],
            // FireRedASR2-AED 是离线自回归模型，没有可增量推进的流式接口：实时预览靠
            // 「按 ≥1 秒新音频节流地重解已累积音频」得到，最终文本仍由整段重解产出。
            streamingSemantics: .rollingWindowConfirmedSegments,
            timeoutPolicy: .standard
        )
    }
}
