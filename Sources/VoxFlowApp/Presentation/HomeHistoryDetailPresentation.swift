import Foundation
import SwiftUI
import VoxFlowVoiceCorrection
import VoxFlowPromptKit

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
        case "llm_structured_parse_failed":
            return L10n.localize("home.detail.warning.llm_structured_parse_failed", comment: "LLM structured response parse failed")
        case "llm_refinement_rejected":
            return L10n.localize("home.detail.warning.llm_refinement_rejected", comment: "LLM refinement rejected by safety guard")
        case "llm_refinement_cancelled_by_user":
            return L10n.localize("home.detail.warning.llm_refinement_cancelled", comment: "LLM refinement cancelled")
        case "context_collection_timeout":
            return L10n.localize("home.detail.warning.context_collection_timeout", comment: "Context collection timeout")
        case "secure_text_field_detected":
            return L10n.localize("home.detail.warning.secure_text_field_detected", comment: "Secure text field detected")
        case "voice_correction_failed":
            return L10n.localize("home.detail.warning.voice_correction_failed", comment: "Voice correction failed")
        case "prompt_context_failed":
            return L10n.localize("home.detail.warning.prompt_context_failed", comment: "Prompt context failed")
        case "snapshotUnavailable":
            return L10n.localize("home.detail.warning.voice_correction_snapshot_unavailable", comment: "Voice correction snapshot unavailable")
        case "processingFailed":
            return L10n.localize("home.detail.warning.voice_correction_processing_failed", comment: "Voice correction processing failed")
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

    // MARK: - Pipeline step model

    /// The pipeline phases shown in the transcription detail timeline.
    /// Order matters — it reflects the processing order from ASR to output.
    enum PipelineStepKind: CaseIterable {
        case asr
        case deterministic
        case textReplacement
        case styleRoute
        case context
        case llm
        case output

        var title: String {
            switch self {
            case .asr:
                return L10n.localize("home.detail.pipeline.step.asr", comment: "ASR step title")
            case .deterministic:
                return L10n.localize("home.detail.pipeline.step.deterministic", comment: "Deterministic step title")
            case .textReplacement:
                return L10n.localize("home.detail.pipeline.step.text_replacement", comment: "Text replacement step title")
            case .styleRoute:
                return L10n.localize("home.detail.pipeline.step.style_route", comment: "Style route step title")
            case .context:
                return L10n.localize("home.detail.pipeline.step.context", comment: "Context step title")
            case .llm:
                return L10n.localize("home.detail.pipeline.step.llm", comment: "LLM step title")
            case .output:
                return L10n.localize("home.detail.pipeline.step.output", comment: "Output step title")
            }
        }

        var systemImage: String {
            switch self {
            case .asr: return "waveform"
            case .deterministic: return "wand.and.stars"
            case .textReplacement: return "arrow.left.arrow.right"
            case .styleRoute: return "shuffle"
            case .context: return "text.viewfinder"
            case .llm: return "sparkles"
            case .output: return "checkmark.circle"
            }
        }

        /// Whether this step is applicable to the given task mode.
        /// Agent compose/dispatch don't go through deterministic processing
        /// or text replacement — those steps are hidden rather than shown
        /// as "skipped" to avoid clutter.
        func isApplicable(for taskMode: VoiceTaskMode?) -> Bool {
            switch self {
            case .deterministic, .textReplacement:
                return taskMode == nil || taskMode == .dictation
            case .styleRoute:
                return taskMode == nil || taskMode == .dictation
            case .asr, .context, .llm, .output:
                return true
            }
        }
    }

    /// Status of a single pipeline step in the timeline.
    enum PipelineStepStatus: Equatable {
        case success
        case skipped
        case hit
        case modified
        case missed
        case failed
        case executed

        var title: String {
            switch self {
            case .success:
                return L10n.localize("home.detail.pipeline.status.success", comment: "Pipeline step success")
            case .skipped:
                return L10n.localize("home.detail.pipeline.status.skipped", comment: "Pipeline step skipped")
            case .hit:
                return L10n.localize("home.detail.pipeline.status.hit", comment: "Pipeline step hit")
            case .modified:
                return L10n.localize("home.detail.pipeline.status.modified", comment: "Pipeline step modified")
            case .missed:
                return L10n.localize("home.detail.pipeline.status.missed", comment: "Pipeline step missed")
            case .failed:
                return L10n.localize("home.detail.pipeline.status.failed", comment: "Pipeline step failed")
            case .executed:
                return L10n.localize("home.detail.pipeline.status.executed", comment: "Pipeline step executed")
            }
        }
    }

    struct PipelineStepInfo: Equatable, Identifiable {
        let kind: PipelineStepKind
        let status: PipelineStepStatus
        var id: PipelineStepKind { kind }
    }

    /// Maps a `HomeHistoryDetail`'s trace data to the 6 pipeline steps with
    /// their statuses. Steps that are not applicable to the task mode are
    /// excluded from the returned array.
    static func pipelineSteps(for detail: HomeHistoryDetail) -> [PipelineStepInfo] {
        PipelineStepKind.allCases.compactMap { kind in
            guard kind.isApplicable(for: detail.taskMode) else { return nil }
            return PipelineStepInfo(kind: kind, status: stepStatus(for: kind, detail: detail))
        }
    }

    private static func stepStatus(for kind: PipelineStepKind, detail: HomeHistoryDetail) -> PipelineStepStatus {
        switch kind {
        case .asr:
            // ASR always ran if we have raw text.
            return .success
        case .deterministic:
            guard let deterministic = detail.trace?.deterministic else { return .skipped }
            guard deterministic.enabled else { return .skipped }
            return deterministic.changed ? .modified : .executed
        case .textReplacement:
            guard let vc = detail.trace?.voiceCorrection else { return .skipped }
            if vc.failureReason != nil { return .failed }
            if vc.appliedEvents.isEmpty {
                return vc.candidateEvents.isEmpty ? .missed : .missed
            }
            return .hit
        case .styleRoute:
            guard let route = detail.trace?.styleRoute else { return .skipped }
            if route.selectedStyleID == nil && route.fallbackReason != nil {
                return .failed
            }
            return .success
        case .context:
            guard let context = detail.trace?.contextBoost else {
                return detail.contextPreview == nil ? .skipped : .executed
            }
            if context.failureReason != nil { return .failed }
            if context.appliedToLLMPrompt { return .hit }
            return (context.hotwords.isEmpty && detail.contextPreview == nil) ? .missed : .executed
        case .llm:
            guard let llm = detail.trace?.llm else { return .skipped }
            return llm.succeeded ? .success : .failed
        case .output:
            // Output always completed if we have final text.
            return .success
        }
    }

    /// Returns the overall pipeline status text shown next to the timeline
    /// header. Example: "成功 · 4.1 秒 · 200" or "本地处理完成".
    static func pipelineStatusText(for detail: HomeHistoryDetail) -> String {
        if let llm = detail.trace?.llm {
            let duration = durationText(milliseconds: llm.durationMS)
            let code = llm.statusCode.map { "\($0)" } ?? L10n.localize("home.detail.meta.not_recorded", comment: "Not recorded")
            let status = llm.succeeded
                ? L10n.localize("home.detail.status.success", comment: "Success status")
                : L10n.localize("home.detail.status.failed", comment: "Failed status")
            return "\(status) · \(duration) · \(code)"
        }
        if detail.trace?.voiceCorrection != nil || detail.trace?.contextBoost != nil {
            return L10n.localize("home.detail.pipeline.status.local", comment: "Local processing complete")
        }
        return L10n.localize("home.detail.pipeline.status.local", comment: "Local processing complete")
    }

    /// The color used for the pipeline status pill.
    static func pipelineStatusColor(for detail: HomeHistoryDetail) -> Color {
        if let llm = detail.trace?.llm {
            return llm.succeeded ? AppTheme.ColorToken.accent : Color.orange
        }
        if detail.trace?.voiceCorrection?.failureReason != nil {
            return Color.orange
        }
        return AppTheme.ColorToken.accent
    }

    /// Diff status text shown in the result comparison section.
    /// Returns nil if there's no meaningful diff to show.
    static func diffStatusText(for detail: HomeHistoryDetail) -> String? {
        // If LLM failed, show "处理失败".
        if let llm = detail.trace?.llm, !llm.succeeded {
            return L10n.localize("home.detail.diff.failed", comment: "Diff failed status")
        }
        // If voice correction applied replacements, show "已修正 · N 处".
        if let vc = detail.trace?.voiceCorrection, !vc.appliedEvents.isEmpty {
            return String(
                format: L10n.localize("home.detail.diff.modified_format", comment: "Diff modified format"),
                vc.appliedEvents.count
            )
        }
        // If raw == final and no corrections, show "未修改".
        let raw = detail.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = detail.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw == final {
            return L10n.localize("home.detail.diff.unmodified", comment: "Diff unmodified status")
        }
        // Texts differ but no voice correction — LLM or deterministic changed it.
        return L10n.localize("home.detail.diff.modified_format_one", comment: "Diff modified one")
    }

    /// Returns the step that should be selected by default when the modal
    /// opens. Keep the default stable and predictable: always start from the
    /// first visible pipeline step (ASR for dictation records).
    static func defaultSelectedStep(for detail: HomeHistoryDetail) -> PipelineStepKind {
        let steps = pipelineSteps(for: detail)
        return steps.first?.kind ?? .asr
    }

    /// Returns the diff preview text shown in the diff pill, e.g.
    /// "QW3A。 → Qwen3.". Returns nil if there's no meaningful change.
    static func diffPreviewText(for detail: HomeHistoryDetail) -> String? {
        if let event = detail.trace?.voiceCorrection?.appliedEvents.first {
            return "\(event.original) → \(event.replacement)"
        }
        let raw = detail.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = detail.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !final.isEmpty, raw != final else { return nil }
        // Truncate long texts for the pill.
        let maxLen = 40
        let truncatedRaw = raw.count > maxLen ? String(raw.prefix(maxLen)) + "…" : raw
        let truncatedFinal = final.count > maxLen ? String(final.prefix(maxLen)) + "…" : final
        return "\(truncatedRaw) → \(truncatedFinal)"
    }
}
