import VoxFlowASRCore

/// 把 VoxFlow 的语言能力映射为 R2T2 的语言提示。
///
/// 上游 `Qwen3ASRModel.canonicalLanguage` 接受 ISO 639 / BCP-47 / 语言名并做规范化，同时会在
/// checkpoint 的 `support_languages` 中校验。首期只承诺中文和英文；其余返回 nil 表示交给上游
/// auto-detect（代价是首个已确认文本会更晚出现，见上游 `canonicalLanguageName` 的说明）。
public enum R2T2LanguageMapper {
    public static func languageHint(for language: VoxFlowASRCore.ASRLanguageCapability) -> String? {
        let tag = language.bcp47Tag.lowercased()
        if tag.hasPrefix("zh") { return "zh" }
        if tag.hasPrefix("en") { return "en" }
        return nil
    }
}
