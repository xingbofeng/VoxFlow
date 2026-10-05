import VoxFlowASRCore

public enum R2T2ProviderDescriptor {
    /// 稳定 identifier；出现在持久化的 Provider 选择中，不要更改。
    public static let providerID = VoxFlowASRCore.ASRProviderID(rawValue: "confucius4_r2t2")
    public static let displayName = "Confucius4-R2T2"

    public static func descriptor(
        modelInstallationState: VoxFlowASRCore.ASRModelInstallationState
    ) -> VoxFlowASRCore.ASRProviderDescriptor {
        VoxFlowASRCore.ASRProviderDescriptor(
            id: providerID,
            displayName: displayName,
            modelInstallationState: modelInstallationState,
            supportedLanguages: [
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "zh-CN"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "zh-TW"),
                VoxFlowASRCore.ASRLanguageCapability(bcp47Tag: "en-US"),
            ],
            // R2T2 的产品契约：`stablePrefix` 只增长、不回滚；本步被回滚的待定尾巴走
            // `unstableSuffix` 仅作实时预览，可被后续步骤改写。
            streamingSemantics: .chunkedStablePrefix
        )
    }
}
