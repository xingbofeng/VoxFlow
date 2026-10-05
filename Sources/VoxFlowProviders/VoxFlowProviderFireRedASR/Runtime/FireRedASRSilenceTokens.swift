import Foundation

/// AED 词表里的功能性 token，以及「模型其实没听到语音」的判定。
///
/// 这些字符串来自随权重分发的 `tokens.txt`（`<blank>` 0、`<unk>` 1、`<pad>` 2、`<sos>` 3、
/// `<eos>` 4、`<sil>` 8632），它们**不是**转写内容。其中 `<unk>` 和 `<sil>` 会出现在解码结果里，
/// 其余由运行时消费。
///
/// 为什么需要单独判定：模型对「整段没有可识别语音」的输入会输出 `<sil>`——一个长度为 5 的
/// **非空**字符串，而且它在词表里就是一个普通 token。所以 `!text.isEmpty` 不足以判定识别成功，
/// 否则 `<sil>` 会被当成正文一路注入到用户光标处。
///
/// 实测（M5 Pro，int8 AED，官方 `test_wavs/3.wav`）：语音衰减到 -40 dB（峰值 0.0027 满量程）
/// 仍能识别；衰减到 -50 dB（峰值 0.00085）整段退化为 `<sil>`。前后补 2 s 纯静音**不会**让
/// 正常语音旁边冒出 `<sil>`——它只在整段都无可识别语音时出现。
enum FireRedASRSilenceTokens {
    /// 词表里全部功能性 token。判定与清理都以这个集合为唯一来源。
    static let functional: Set<String> = ["<blank>", "<unk>", "<pad>", "<sos>", "<eos>", "<sil>"]

    /// 去掉所有功能性 token 后的文本。
    ///
    /// 既用于「整段没有语音」的判定，也用于清掉夹在正常文本里的零星 token——它们是模型的
    /// 内部标记，任何时候都不该出现在用户可见的转写里。
    static func strippingFunctionalTokens(_ text: String) -> String {
        var remainder = text
        for token in functional where remainder.contains(token) {
            remainder = remainder.replacingOccurrences(of: token, with: "")
        }
        return remainder.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
