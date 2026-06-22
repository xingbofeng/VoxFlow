import Foundation
import VoxFlowVoiceCorrection

enum HomeHistoryDetailPresentation {
    static let missingTraceMessage = "这条记录没有模型纠错信息。可能是当时没有开启文本纠错，或者它是在追踪功能上线前生成的。点击右上角“重新处理”，即可查看是否调用模型、发送内容和返回结果。"

    static func missingTraceMessage(for taskMode: VoiceTaskMode?) -> String {
        if taskMode == .agentDispatch {
            return "这条AI 编程记录不会调用文本纠错模型；语音原文和生成结果已单独保留。"
        }
        guard taskMode == .agentCompose else {
            return missingTraceMessage
        }
        return "这条“任务助手”记录没有保存模型调用过程，但识别原文和生成结果仍已保留。可以使用右上角“复制结果”。"
    }

    static func languageName(for identifier: String) -> String {
        switch identifier {
        case "zh-CN":
            return "中文（简体）"
        case "zh-TW":
            return "中文（繁体）"
        case "en-US":
            return "英语（美国）"
        default:
            return identifier
        }
    }

    static func recognitionProviderName(for identifier: String?) -> String {
        switch identifier {
        case ASRProviderID.appleSpeech:
            return "系统语音识别"
        case ASRProviderID.funASR:
            return "FunASR 本地识别"
        case ASRProviderID.whisper:
            return "Whisper 本地识别"
        case ASRProviderID.qwen3:
            return "Qwen3 本地识别"
        case ASRProviderID.paraformer:
            return "Paraformer 本地识别"
        case ASRProviderID.senseVoice:
            return "SenseVoice 本地识别"
        case ASRProviderID.nvidiaNemotron:
            return "NVIDIA Nemotron 本地识别"
        case ASRProviderID.parakeetStreaming:
            return "Parakeet 本地识别"
        case ASRProviderID.omnilingualASR:
            return "Omnilingual 本地识别"
        case ASRProviderID.groqWhisper:
            return "Groq 云端识别"
        case ASRProviderID.tencentCloudASR:
            return "腾讯云语音识别"
        case ASRProviderID.qwenCloudASR:
            return "阿里云语音识别"
        case ASRProviderID.mistralVoxtral:
            return "Mistral Voxtral 语音识别"
        case ASRProviderID.assemblyAI:
            return "AssemblyAI 语音识别"
        case ASRProviderID.volcengineDoubao:
            return "火山云语音识别"
        case ASRProviderID.elevenLabsScribe:
            return "ElevenLabs Scribe 语音识别"
        case nil, "":
            return "未记录"
        default:
            return identifier ?? "未记录"
        }
    }

    static func textCorrectionName(
        providerID: String?,
        traceProviderName: String?
    ) -> String {
        if let traceProviderName, !traceProviderName.isEmpty {
            return traceProviderName
        }
        switch providerID {
        case "legacy-openai-compatible":
            return "智能模型纠错服务"
        case nil, "":
            return "未启用"
        default:
            return providerID ?? "未启用"
        }
    }

    static func styleName(for identifier: String?) -> String {
        switch identifier {
        case "builtin.original":
            return "原文风格"
        case "builtin.formal":
            return "正式风格"
        case "builtin.casual":
            return "日常风格"
        case "builtin.energetic":
            return "元气风格"
        case "builtin.coding":
            return "编程风格"
        case "builtin.email":
            return "邮件风格"
        case nil, "":
            return "未选择"
        default:
            return identifier ?? "未选择"
        }
    }

    static func durationText(milliseconds: Int?) -> String {
        guard let milliseconds else { return "未记录" }
        let seconds = Double(max(milliseconds, 0)) / 1_000
        return String(format: "%.1f 秒", seconds)
    }

    static func contextBoostStatusText(appliedToPrompt: Bool) -> String {
        appliedToPrompt ? "已加入提示词" : "未应用"
    }

    static func contextBoostSourceName(for source: String) -> String {
        switch source {
        case "current_window_ocr":
            return "当前窗口识别文字"
        case "screenshot_ocr":
            return "截图识别文字"
        default:
            return source
        }
    }

    static func contextBoostHotwordsText(_ hotwords: [String]) -> String {
        guard !hotwords.isEmpty else { return "未提取到可用热词" }
        return hotwords.joined(separator: "、")
    }

    static func contextBoostFailureReasonText(_ reason: String) -> String {
        switch reason {
        case "no_ocr_context":
            return "未在当前窗口识别到可用关键词"
        case "context_boost_timeout":
            return "图片文字识别上下文采集超时，已继续纠错"
        default:
            return reason
        }
    }

    static func voiceCorrectionStatusText(
        candidateCount: Int,
        appliedCount: Int,
        failed: Bool
    ) -> String {
        if failed {
            return "处理失败"
        }
        if appliedCount > 0 {
            return "已替换 \(appliedCount) 处"
        }
        if candidateCount > 0 {
            return "命中 \(candidateCount) 条，未改写"
        }
        return "已检查，未命中"
    }

    static func voiceCorrectionScopeText(_ scope: RuleScope) -> String {
        switch scope {
        case .global:
            return "全局"
        case .application(let bundleIdentifier):
            return "应用：\(bundleIdentifier)"
        }
    }

    static func warningMessage(for code: String, taskMode: VoiceTaskMode?) -> String {
        switch code {
        case "vision_not_supported":
            return taskMode == .agentCompose
                ? "当前模型配置暂不支持截图视觉上下文，已仅根据口述和可读取文本生成。"
                : "当前模型配置暂不支持视觉上下文。"
        case "visual_fallback_timeout":
            return "截图视觉上下文读取超时，已继续处理。"
        case "screen_recording_not_authorized":
            return "未获得屏幕录制权限，无法读取截图视觉上下文；已仅根据口述和可读取文本生成。"
        case "agent_llm_failed":
            return "生成模型调用失败；原始口述已保留，可在详情中重试或复制。"
        case "llm_refinement_failed":
            return "模型调用失败，已保留原始识别文本。"
        case "llm_refinement_cancelled_by_user":
            return "已取消文本纠错，直接使用原始识别文本。"
        case "context_collection_timeout":
            return "读取当前窗口上下文超时，已仅根据口述继续。"
        case "secure_text_field_detected":
            return "检测到安全输入区域，已跳过窗口内容读取。"
        default:
            return code
        }
    }

    static func requestBodyPreview(
        from requestBodyJSON: String,
        taskMode: VoiceTaskMode?
    ) -> String {
        guard let data = requestBodyJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else {
            return requestBodyJSON
        }

        guard let userMessage = messages.first(where: { ($0["role"] as? String) == "user" }),
              let content = userMessage["content"] as? String else {
            return requestBodyJSON
        }
        if content.hasPrefix("[redacted:") {
            return "默认隐私模式未保存完整请求正文。"
        }
        return content
    }
}
