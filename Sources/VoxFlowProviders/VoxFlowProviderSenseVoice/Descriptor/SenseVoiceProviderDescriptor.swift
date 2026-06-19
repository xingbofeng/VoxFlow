import VoxFlowASRCore

public enum SenseVoiceProviderDescriptor {
    public static func descriptor(
        modelInstallationState: VoxFlowASRCore.ASRModelInstallationState
    ) -> VoxFlowASRCore.ASRProviderDescriptor {
        VoxFlowASRCore.ASRProviderDescriptor(
            id: VoxFlowASRCore.ASRProviderID(rawValue: "sense_voice"),
            displayName: "SenseVoice Small",
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
