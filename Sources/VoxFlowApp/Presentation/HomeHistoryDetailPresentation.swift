import Foundation
import VoxFlowVoiceCorrection

enum HomeHistoryDetailPresentation {
    static let missingTraceMessage = L10n.localize("home.detail.trace.missing_dictation", comment: "Missing dictation trace message")

    static func missingTraceMessage(for taskMode: VoiceTaskMode?) -> String {
        if taskMode == .agentDispatch {
            return L10n.localize("home.detail.trace.missing_agent_dispatch", comment: "Missing agent dispatch trace message")
        }
        guard taskMode == .agentCompose else {
            return missingTraceMessage
        }
        return L10n.localize("home.detail.trace.missing_agent_compose", comment: "Missing agent compose trace message")
    }

    static func languageName(for identifier: String) -> String {
        switch identifier {
        case "zh-CN":
            return L10n.localize("home.detail.language.zh_cn", comment: "Simplified Chinese")
        case "zh-TW":
            return L10n.localize("home.detail.language.zh_tw", comment: "Traditional Chinese")
        case "en-US":
            return L10n.localize("home.detail.language.en_us", comment: "US English")
        default:
            return identifier
        }
    }

    static func recognitionProviderName(for identifier: String?) -> String {
        switch identifier {
        case ASRProviderID.appleSpeech:
            return L10n.localize("home.detail.asr.apple_speech", comment: "Apple Speech provider")
        case ASRProviderID.funASR:
            return L10n.localize("home.detail.asr.funasr", comment: "FunASR provider")
        case ASRProviderID.whisper:
            return L10n.localize("home.detail.asr.whisper", comment: "Whisper provider")
        case ASRProviderID.qwen3:
            return L10n.localize("home.detail.asr.qwen3", comment: "Qwen3 provider")
        case ASRProviderID.paraformer:
            return L10n.localize("home.detail.asr.paraformer", comment: "Paraformer provider")
        case ASRProviderID.senseVoice:
            return L10n.localize("home.detail.asr.sense_voice", comment: "SenseVoice provider")
        case ASRProviderID.nvidiaNemotron:
            return L10n.localize("home.detail.asr.nvidia_nemotron", comment: "NVIDIA Nemotron provider")
        case ASRProviderID.parakeetStreaming:
            return L10n.localize("home.detail.asr.parakeet", comment: "Parakeet provider")
        case ASRProviderID.omnilingualASR:
            return L10n.localize("home.detail.asr.omnilingual", comment: "Omnilingual provider")
        case ASRProviderID.groqWhisper:
            return L10n.localize("home.detail.asr.groq", comment: "Groq provider")
        case ASRProviderID.tencentCloudASR:
            return L10n.localize("home.detail.asr.tencent", comment: "Tencent Cloud ASR provider")
        case ASRProviderID.qwenCloudASR:
            return L10n.localize("home.detail.asr.aliyun", comment: "Aliyun ASR provider")
        case ASRProviderID.mistralVoxtral:
            return L10n.localize("home.detail.asr.mistral_voxtral", comment: "Mistral Voxtral provider")
        case ASRProviderID.assemblyAI:
            return L10n.localize("home.detail.asr.assemblyai", comment: "AssemblyAI provider")
        case ASRProviderID.volcengineDoubao:
            return L10n.localize("home.detail.asr.volcengine", comment: "Volcengine ASR provider")
        case ASRProviderID.elevenLabsScribe:
            return L10n.localize("home.detail.asr.elevenlabs", comment: "ElevenLabs provider")
        case nil, "":
            return L10n.localize("home.detail.meta.not_recorded", comment: "Not recorded")
        default:
            return identifier ?? L10n.localize("home.detail.meta.not_recorded", comment: "Not recorded")
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
            return L10n.localize("home.detail.correction.legacy_openai", comment: "Legacy OpenAI compatible correction service")
        case nil, "":
            return L10n.localize("home.detail.correction.disabled", comment: "Correction disabled")
        default:
            return providerID ?? L10n.localize("home.detail.correction.disabled", comment: "Correction disabled")
        }
    }

    static func styleName(for identifier: String?) -> String {
        switch identifier {
        case "builtin.original":
            return L10n.localize("home.detail.style.original", comment: "Original style")
        case "builtin.formal":
            return L10n.localize("home.detail.style.formal", comment: "Formal style")
        case "builtin.casual":
            return L10n.localize("home.detail.style.casual", comment: "Casual style")
        case "builtin.energetic":
            return L10n.localize("home.detail.style.energetic", comment: "Energetic style")
        case "builtin.coding":
            return L10n.localize("home.detail.style.coding", comment: "Coding style")
        case "builtin.email":
            return L10n.localize("home.detail.style.email", comment: "Email style")
        case nil, "":
            return L10n.localize("home.detail.style.not_selected", comment: "No style selected")
        default:
            return identifier ?? L10n.localize("home.detail.style.not_selected", comment: "No style selected")
        }
    }

    static func durationText(milliseconds: Int?) -> String {
        guard let milliseconds else { return L10n.localize("home.detail.meta.not_recorded", comment: "Not recorded") }
        let seconds = Double(max(milliseconds, 0)) / 1_000
        return String(format: L10n.localize("home.detail.duration_seconds_format", comment: "Duration in seconds"), seconds)
    }

    static func contextBoostStatusText(appliedToPrompt: Bool) -> String {
        appliedToPrompt ? L10n.localize("home.detail.context.applied", comment: "Context applied") : L10n.localize("home.detail.context.not_applied", comment: "Context not applied")
    }

    static func contextBoostSourceName(for source: String) -> String {
        switch source {
        case "current_window_ocr":
            return L10n.localize("home.detail.context.source_current_window_ocr", comment: "Current window OCR source")
        case "screenshot_ocr":
            return L10n.localize("home.detail.context.source_screenshot_ocr", comment: "Screenshot OCR source")
        default:
            return source
        }
    }

    static func contextBoostHotwordsText(_ hotwords: [String]) -> String {
        guard !hotwords.isEmpty else { return L10n.localize("home.detail.context.no_hotwords", comment: "No hotwords extracted") }
        return hotwords.joined(separator: "、")
    }

    static func contextBoostFailureReasonText(_ reason: String) -> String {
        switch reason {
        case "no_ocr_context":
            return L10n.localize("home.detail.context.failure_no_ocr_context", comment: "No OCR context failure")
        case "context_boost_timeout":
            return L10n.localize("home.detail.context.failure_timeout", comment: "Context boost timeout")
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
            return L10n.localize("home.detail.voice_correction.status_failed", comment: "Voice correction failed")
        }
        if appliedCount > 0 {
            return String(format: L10n.localize("home.detail.voice_correction.status_applied_format", comment: "Applied replacements status"), appliedCount)
        }
        if candidateCount > 0 {
            return String(format: L10n.localize("home.detail.voice_correction.status_candidates_format", comment: "Candidate hits status"), candidateCount)
        }
        return L10n.localize("home.detail.voice_correction.status_no_hits", comment: "No voice correction hits status")
    }

    static func voiceCorrectionScopeText(_ scope: RuleScope) -> String {
        switch scope {
        case .global:
            return L10n.localize("home.detail.voice_correction.scope_global", comment: "Global scope")
        case .application(let bundleIdentifier):
            return String(format: L10n.localize("home.detail.voice_correction.scope_application_format", comment: "Application scope"), bundleIdentifier)
        }
    }

    static func warningMessage(for code: String, taskMode: VoiceTaskMode?) -> String {
        switch code {
        case "vision_not_supported":
            return taskMode == .agentCompose
                ? L10n.localize("home.detail.warning.vision_not_supported_agent", comment: "Vision not supported for agent compose")
                : L10n.localize("home.detail.warning.vision_not_supported", comment: "Vision not supported")
        case "visual_fallback_timeout":
            return L10n.localize("home.detail.warning.visual_fallback_timeout", comment: "Visual fallback timeout")
        case "screen_recording_not_authorized":
            return L10n.localize("home.detail.warning.screen_recording_not_authorized", comment: "Screen recording not authorized")
        case "agent_llm_failed":
            return L10n.localize("home.detail.warning.agent_llm_failed", comment: "Agent LLM failed")
        case "llm_refinement_failed":
            return L10n.localize("home.detail.warning.llm_refinement_failed", comment: "LLM refinement failed")
        case "llm_refinement_cancelled_by_user":
            return L10n.localize("home.detail.warning.llm_refinement_cancelled", comment: "LLM refinement cancelled")
        case "context_collection_timeout":
            return L10n.localize("home.detail.warning.context_collection_timeout", comment: "Context collection timeout")
        case "secure_text_field_detected":
            return L10n.localize("home.detail.warning.secure_text_field_detected", comment: "Secure text field detected")
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
            return L10n.localize("home.detail.request_json.redacted", comment: "Redacted request body")
        }
        return content
    }

    static func modelInputPreview(
        rawText: String,
        requestBodyJSON: String,
        taskMode: VoiceTaskMode?
    ) -> String {
        if taskMode == .agentCompose {
            let trimmedRawText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedRawText.isEmpty {
                return trimmedRawText
            }
        }
        return requestBodyPreview(from: requestBodyJSON, taskMode: taskMode)
    }

    static func modelOutputPreview(
        responseText: String?,
        errorMessage: String?
    ) -> String {
        if let errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        guard let responseText, !responseText.isEmpty else {
            return L10n.localize("home.detail.trace.empty_response", comment: "Empty model response")
        }
        guard let data = responseText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return responseText
        }
        if let polished = json["polished"] as? String, !polished.isEmpty {
            let correctionsCount = (json["corrections"] as? [Any])?.count ?? 0
            let keyTermsCount = (json["key_terms"] as? [Any])?.count ?? 0
            return [
                "\(L10n.localize("home.detail.llm.polished", comment: "Polished result label")) \(polished)",
                "\(L10n.localize("home.detail.llm.corrections", comment: "Corrections label")) \(correctionsCount)",
                "\(L10n.localize("home.detail.llm.key_terms", comment: "Key terms label")) \(keyTermsCount)"
            ].joined(separator: "\n")
        }
        return responseText
    }

    static func learningPair(
        originalText: String,
        editedText: String
    ) -> LearnedCorrectionPair? {
        HighConfidenceCorrectionExtractor()
            .extract(
                insertedText: originalText,
                baselineText: originalText,
                editedText: editedText,
                appliedCorrectionRanges: []
            )
            .first
    }
}
