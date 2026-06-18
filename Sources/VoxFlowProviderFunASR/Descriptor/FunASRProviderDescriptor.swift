import VoxFlowASRCore

public enum FunASRProviderDescriptor {
    public static func descriptor(
        precision: FunASRModelVariant,
        modelInstallationState: VoxFlowASRCore.ASRModelInstallationState
    ) -> VoxFlowASRCore.ASRProviderDescriptor {
        VoxFlowASRCore.ASRProviderDescriptor(
            id: VoxFlowASRCore.ASRProviderID(rawValue: "funasr"),
            displayName: "FunASR Nano",
            modelInstallationState: modelInstallationState,
            supportedLanguages: [
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "zh-CN"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "zh-TW"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "en-US"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "ja-JP"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "ko-KR"),
            ],
            streamingSemantics: .rollingWindowConfirmedSegments
        )
    }
}
