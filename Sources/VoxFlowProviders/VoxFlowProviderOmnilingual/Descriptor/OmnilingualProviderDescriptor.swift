import VoxFlowASRCore

public enum OmnilingualProviderDescriptor {
    public static func descriptor(
        modelInstallationState: VoxFlowASRCore.ASRModelInstallationState
    ) -> VoxFlowASRCore.ASRProviderDescriptor {
        VoxFlowASRCore.ASRProviderDescriptor(
            id: VoxFlowASRCore.ASRProviderID(rawValue: "omnilingual_asr"),
            displayName: "Omnilingual ASR",
            modelInstallationState: modelInstallationState,
            supportedLanguages: [
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "zh-CN"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "zh-TW"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "en-US"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "ja-JP"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "ko-KR"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "fr-FR"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "de-DE"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "es-ES"),
            ],
            streamingSemantics: .offlineFinalOnly
        )
    }
}
