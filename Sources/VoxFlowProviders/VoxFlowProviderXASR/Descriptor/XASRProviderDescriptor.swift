import VoxFlowASRCore

public enum XASRProviderDescriptor {
    public static let providerID = ASRProviderID(rawValue: "xasr")
    public static let displayName = "X-ASR-zh-en"

    public static func descriptor(modelInstallationState: ASRModelInstallationState) -> ASRProviderDescriptor {
        ASRProviderDescriptor(
            id: providerID,
            displayName: displayName,
            modelInstallationState: modelInstallationState,
            supportedLanguages: [
                ASRLanguageCapability(bcp47Tag: "zh-CN"),
                ASRLanguageCapability(bcp47Tag: "en-US"),
            ],
            streamingSemantics: .nativeStreaming
        )
    }
}
