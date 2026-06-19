import VoxFlowASRCore

public enum ParaformerProviderDescriptor {
    public static func descriptor(
        modelInstallationState: VoxFlowASRCore.ASRModelInstallationState
    ) -> VoxFlowASRCore.ASRProviderDescriptor {
        VoxFlowASRCore.ASRProviderDescriptor(
            id: VoxFlowASRCore.ASRProviderID(rawValue: "paraformer"),
            displayName: "Paraformer Large zh",
            modelInstallationState: modelInstallationState,
            supportedLanguages: [
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "zh-CN"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "zh-TW"),
            ],
            streamingSemantics: .rollingWindowConfirmedSegments
        )
    }
}
