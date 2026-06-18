import VoxFlowASRCore

public enum Qwen3LanguageMapper {
    public static func languageHint(for language: VoxFlowASRCore.ASRLanguageCapability) -> String? {
        let tag = language.bcp47Tag.lowercased()
        if tag.hasPrefix("zh") { return "zh" }
        if tag.hasPrefix("en") { return "en" }
        return nil
    }
}
