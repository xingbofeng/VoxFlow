import VoxFlowASRCore

public enum ParakeetProviderDescriptor {
    public static func descriptor(
        modelInstallationState: VoxFlowASRCore.ASRModelInstallationState
    ) -> VoxFlowASRCore.ASRProviderDescriptor {
        VoxFlowASRCore.ASRProviderDescriptor(
            id: VoxFlowASRCore.ASRProviderID(rawValue: "parakeet_streaming"),
            displayName: "Parakeet Streaming",
            modelInstallationState: modelInstallationState,
            supportedLanguages: [
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "en-US"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "de-DE"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "fr-FR"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "es-ES"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "it-IT"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "pt-PT"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "nl-NL"),
            ],
            streamingSemantics: .nativeStreaming
        )
    }
}
