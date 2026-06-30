import XCTest
import VoxFlowPromptKit
import VoxFlowVoiceCorrection
@testable import VoxFlowApp

final class HomeHistoryDetailPresentationTests: XCTestCase {
    func testInternalIdentifiersArePresentedAsReadableChinese() {
        XCTAssertEqual(
            HomeHistoryDetailPresentation.recognitionProviderName(for: "qwen3_asr"),
            "Qwen3 本地识别"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.recognitionProviderName(
                for: "nvidia_nemotron_3_5_asr_streaming_0_6b"
            ),
            "NVIDIA Nemotron 本地识别"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.textCorrectionName(
                providerID: "legacy-openai-compatible",
                traceProviderName: nil
            ),
            "智能模型纠错服务"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.styleName(for: "builtin.coding"),
            "编程风格"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.languageName(for: "zh-CN"),
            "中文（简体）"
        )
    }

    func testProviderInitialBadgeUsesFirstVisibleCharacter() {
        XCTAssertEqual(ProviderInitialBadge.initial(from: "Qwen3 本地识别"), "Q")
        XCTAssertEqual(ProviderInitialBadge.initial(from: " Tencent"), "T")
        XCTAssertEqual(ProviderInitialBadge.initial(from: nil), "?")
    }

    func testMissingTraceMessageExplainsWhatUserCanDo() {
        XCTAssertEqual(
            HomeHistoryDetailPresentation.missingTraceMessage,
            "这条记录没有模型纠错信息。可能是当时没有开启文本纠错，或者它是在追踪功能上线前生成的。点击右上角“重新处理”，即可查看是否调用模型、发送内容和返回结果。"
        )
    }

    func testAgentComposeMissingTraceMessageDoesNotOfferReprocessing() {
        XCTAssertEqual(
            HomeHistoryDetailPresentation.missingTraceMessage(for: .agentCompose),
            "这条“任务助手”记录没有保存模型调用过程，但识别原文和生成结果仍已保留。可以使用右上角“复制结果”。"
        )
    }

    func testAgentDispatchMissingTraceMessagePointsToSavedDispatchResult() {
        XCTAssertEqual(
            HomeHistoryDetailPresentation.missingTraceMessage(for: .agentDispatch),
            "这条 AI 编程记录不会调用文本纠错模型；语音原文和生成结果已单独保留。"
        )
    }

    func testDictationRequestBodyPreviewExtractsOnlyUserMessageContent() {
        let requestBody = """
        {
          "model": "gpt-4.1-mini",
          "temperature": 0.2,
          "messages": [
            {
              "role": "system",
              "content": "Do not show this prompt in the preview."
            },
            {
              "role": "user",
              "content": "这是用户真正说的话。"
            }
          ]
        }
        """

        XCTAssertEqual(
            HomeHistoryDetailPresentation.requestBodyPreview(
                from: requestBody,
                taskMode: nil
            ),
            "这是用户真正说的话。"
        )
    }

    func testAgentComposeRequestBodyPreviewShowsOnlyUserDictationIntent() {
        let requestBody = """
        {
          "messages": [
            {
              "role": "system",
              "content": "Target application: 微信\\n\\nContext (use as reference, do not fabricate from it):\\nWindow title: 和 Alice 的聊天\\n\\nVisible text in window:\\nAlice: 六点前可以发我吗？\\n\\nUser's dictation intent:\\n帮我回复可以"
            },
            {
              "role": "user",
              "content": "帮我回复可以"
            }
          ]
        }
        """

        let preview = HomeHistoryDetailPresentation.requestBodyPreview(
            from: requestBody,
            taskMode: .agentCompose
        )

        XCTAssertEqual(preview, "帮我回复可以")
        XCTAssertFalse(preview.contains("Target application: 微信"))
        XCTAssertFalse(preview.contains("Visible text in window:"))
    }

    func testAgentComposeVisibleUserTextUsesRawTranscriptInsteadOfFullPromptRequestBody() {
        let requestBody = """
        {
          "messages": [
            {
              "role": "system",
              "content": "You are a context-aware writing assistant."
            },
            {
              "role": "user",
              "content": "Target application:\\n<target_application>\\nCodex\\n</target_application>\\n\\nStyle guidance:\\n<style_guidance>\\n## 编程风格\\n</style_guidance>\\n\\nUser's dictation intent:\\n<user_dictation_intent>\\n告诉他可以继续\\n</user_dictation_intent>"
            }
          ]
        }
        """

        let visibleText = HomeHistoryDetailPresentation.modelInputPreview(
            rawText: "告诉他可以继续",
            requestBodyJSON: requestBody,
            taskMode: .agentCompose
        )

        XCTAssertEqual(visibleText, "告诉他可以继续")
        XCTAssertFalse(visibleText.contains("Target application:"))
        XCTAssertFalse(visibleText.contains("Style guidance:"))
    }

    func testRequestBodyPreviewFallsBackToRawJSONWhenUserMessageIsMissing() {
        let requestBody = #"{"model":"gpt","messages":[{"role":"system","content":"prompt"}]}"#

        XCTAssertEqual(
            HomeHistoryDetailPresentation.requestBodyPreview(
                from: requestBody,
                taskMode: nil
            ),
            requestBody
        )
    }

    func testDurationPreviewUsesSecondsInsteadOfMilliseconds() {
        XCTAssertEqual(HomeHistoryDetailPresentation.durationText(milliseconds: 15_994), "16.0 秒")
        XCTAssertEqual(HomeHistoryDetailPresentation.durationText(milliseconds: 123), "0.1 秒")
        XCTAssertEqual(HomeHistoryDetailPresentation.durationText(milliseconds: nil), "未记录")
    }

    func testFullDiagnosticSummaryIsUserReadableAndDoesNotExposeRawJSON() {
        let metadata = PromptTraceMetadata(
            promptKind: .voiceCorrection,
            promptVersion: .v1_0_0,
            renderedPromptHash: "prompt-hash",
            styleID: "builtin.chat"
        )
        let detail = makeDetail(
            trace: TextProcessingTrace(
                llm: LLMRefinementTrace(
                    providerID: "provider",
                    providerName: "Groq",
                    endpoint: "https://api.example.com/v1/chat/completions",
                    model: "gpt-oss-20b",
                    temperature: 0.4,
                    timeoutSeconds: 30,
                    requestBodyJSON: #"{"messages":[{"role":"system","content":"完整系统提示"},{"role":"user","content":"完整用户请求"}]}"#,
                    responseText: #"{"polished":"最终文本"}"#,
                    statusCode: 200,
                    durationMS: 900,
                    promptMetadata: metadata
                ),
                contextRounds: ContextRoundsTrace(
                    enabled: true,
                    requestedRounds: 3,
                    usedRounds: 2,
                    contextHistoryIDs: ["history-a", "history-b"],
                    excludedReasons: ["expired"],
                    wrapperVersion: "1.0.0"
                ),
                voiceCorrection: VoiceCorrectionTrace(),
                styleRoute: StyleRouteTrace(
                    candidateStyleIDs: ["builtin.chat", "builtin.coding"],
                    routerResponse: nil,
                    selectedStyleID: "builtin.chat",
                    fallbackReason: nil,
                    styleSelectionSource: "aiRouteCache",
                    routerVersion: "1.0.0",
                    renderedPromptHash: "route-hash",
                    durationMS: 88
                )
            ),
            warnings: ["llm_structured_parse_failed"]
        )

        let summary = HomeHistoryDetailPresentation.userVisibleDiagnosticSummary(for: detail)

        XCTAssertTrue(summary.contains("服务地址: https://api.example.com/v1/chat/completions"))
        XCTAssertTrue(summary.contains("路由来源: AI 路由缓存"))
        XCTAssertTrue(summary.contains("选中风格: 聊天风格"))
        XCTAssertTrue(summary.contains("引用轮数: 2 / 3 轮"))
        XCTAssertTrue(summary.contains("排除原因: 超过可引用时间"))
        XCTAssertFalse(summary.contains("expired"))
        XCTAssertTrue(summary.contains("模型: gpt-oss-20b"))
        XCTAssertTrue(summary.contains("提示词哈希: prompt-hash"))
        XCTAssertFalse(summary.contains("requestBodyJSON"))
        XCTAssertFalse(summary.contains("完整系统提示"))
        XCTAssertFalse(summary.contains("完整用户请求"))
        XCTAssertFalse(summary.contains(#""messages""#))
    }

    func testDiagnosticReasonCodesUseUserReadableLabels() {
        XCTAssertEqual(
            HomeHistoryDetailPresentation.styleRouteFallbackReasonText("router_unavailable"),
            "未能获得智能路由结果，已使用默认风格"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.contextRoundsExcludedReasonText("different_app"),
            "不同应用"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.contextRoundsExcludedReasonText("unknown_reason"),
            "unknown_reason"
        )
    }

    func testContextBoostTracePresentationUsesUserReadableLabels() {
        XCTAssertEqual(HomeHistoryDetailPresentation.contextBoostStatusText(appliedToPrompt: true), "已加入提示词")
        XCTAssertEqual(HomeHistoryDetailPresentation.contextBoostStatusText(appliedToPrompt: false), "未应用")
        XCTAssertEqual(
            HomeHistoryDetailPresentation.contextBoostSourceName(for: "current_window_ocr"),
            "当前窗口识别文字"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.contextBoostHotwordsText(["Qwen3-ASR", "WhisperKit"]),
            "Qwen3-ASR、WhisperKit"
        )
        XCTAssertEqual(HomeHistoryDetailPresentation.contextBoostHotwordsText([]), "未提取到可用热词")
        XCTAssertEqual(
            HomeHistoryDetailPresentation.contextBoostFailureReasonText("no_ocr_context"),
            "未在当前窗口识别到可用关键词"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.contextBoostFailureReasonText("context_boost_timeout"),
            "图片文字识别上下文采集超时，已继续纠错"
        )
    }

    func testVoiceCorrectionTracePresentationUsesUserReadableLabels() {
        XCTAssertEqual(
            HomeHistoryDetailPresentation.voiceCorrectionStatusText(
                candidateCount: 0,
                appliedCount: 0,
                failed: false
            ),
            "已检查，未命中"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.voiceCorrectionStatusText(
                candidateCount: 1,
                appliedCount: 0,
                failed: false
            ),
            "命中 1 条，未改写"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.voiceCorrectionStatusText(
                candidateCount: 2,
                appliedCount: 2,
                failed: false
            ),
            "已替换 2 处"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.voiceCorrectionStatusText(
                candidateCount: 0,
                appliedCount: 0,
                failed: true
            ),
            "处理失败"
        )
    }

    func testWarningCodesArePresentedAsReadableChinese() {
        XCTAssertEqual(
            HomeHistoryDetailPresentation.warningMessage(
                for: "vision_not_supported",
                taskMode: .agentCompose
            ),
            "当前模型配置暂不支持截图视觉上下文，已仅根据口述和可读取文本生成。"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.warningMessage(
                for: "agent_llm_failed",
                taskMode: .agentCompose
            ),
            "生成模型调用失败；原始口述已保留，可在详情中重试或复制。"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.warningMessage(
                for: "llm_refinement_failed",
                taskMode: .dictation
            ),
            "模型调用失败，已保留原始识别文本。"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.warningMessage(
                for: "llm_structured_parse_failed",
                taskMode: .dictation
            ),
            "模型返回格式不符合预期，已保留模型原文。"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.warningMessage(
                for: "llm_refinement_rejected",
                taskMode: .dictation
            ),
            "模型改写未通过安全检查，已保留原始识别文本。"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.warningMessage(
                for: "llm_refinement_cancelled_by_user",
                taskMode: .dictation
            ),
            "已取消文本纠错，直接使用原始识别文本。"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.warningMessage(
                for: "screen_recording_not_authorized",
                taskMode: .agentCompose
            ),
            "未获得屏幕录制权限，无法读取截图视觉上下文；已仅根据口述和可读取文本生成。"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.warningMessage(
                for: "visual_fallback_timeout",
                taskMode: .agentCompose
            ),
            "截图视觉上下文读取超时，已继续处理。"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.warningMessage(
                for: "context_collection_timeout",
                taskMode: .agentCompose
            ),
            "读取当前窗口上下文超时，已仅根据口述继续。"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.warningMessage(
                for: "secure_text_field_detected",
                taskMode: .agentCompose
            ),
            "检测到安全输入区域，已跳过窗口内容读取。"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.warningMessage(
                for: "voice_correction_failed",
                taskMode: .dictation
            ),
            "易错词纠错处理失败，已继续使用当前文本。"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.warningMessage(
                for: "prompt_context_failed",
                taskMode: .dictation
            ),
            "提示词上下文构建失败，已使用基础提示词继续纠错。"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.warningMessage(
                for: "snapshotUnavailable",
                taskMode: .dictation
            ),
            "易错词纠错缺少可用规则快照，已跳过本次规则匹配。"
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.warningMessage(
                for: "processingFailed",
                taskMode: .dictation
            ),
            "易错词规则执行失败，已跳过失败规则并继续处理。"
        )
    }

    func testKnownWarningCodesDoNotLeakInternalIdentifiers() {
        let knownWarningCodes = [
            "vision_not_supported",
            "visual_fallback_timeout",
            "screen_recording_not_authorized",
            "agent_llm_failed",
            "llm_refinement_failed",
            "llm_structured_parse_failed",
            "llm_refinement_rejected",
            "llm_refinement_cancelled_by_user",
            "context_collection_timeout",
            "secure_text_field_detected",
            "voice_correction_failed",
            "prompt_context_failed",
            "snapshotUnavailable",
            "processingFailed"
        ]

        for code in knownWarningCodes {
            let message = HomeHistoryDetailPresentation.warningMessage(for: code, taskMode: .dictation)
            XCTAssertNotEqual(message, code, "Warning code should have a user-readable message: \(code)")
            XCTAssertFalse(message.contains("_"), "Warning message should not expose snake_case code: \(code)")
        }
    }

    // MARK: - Pipeline step mapping tests

    private func makeDetail(
        rawText: String = "测试原文",
        finalText: String = "测试最终",
        trace: TextProcessingTrace? = nil,
        taskMode: VoiceTaskMode? = nil,
        contextPreview: String? = nil,
        warnings: [String] = []
    ) -> HomeHistoryDetail {
        HomeHistoryDetail(
            id: "test",
            rawText: rawText,
            finalText: finalText,
            language: "zh-CN",
            asrProviderID: "apple_speech",
            llmProviderID: nil,
            styleID: nil,
            appName: nil,
            appBundleID: nil,
            durationMS: 1000,
            charCount: finalText.count,
            cpm: 200,
            warnings: warnings,
            trace: trace,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            taskMode: taskMode,
            taskStatus: nil,
            windowTitle: nil,
            contextPreview: contextPreview,
            outputResultRaw: nil
        )
    }

    func testPipelineStepsWithNoTraceShowsSkippedForNonAlwaysPresentSteps() {
        let detail = makeDetail(trace: nil, taskMode: nil)
        let steps = HomeHistoryDetailPresentation.pipelineSteps(for: detail)

        // ASR and output are always success; deterministic/textReplacement/styleRoute/llm are skipped.
        let asrStep = steps.first { $0.kind == .asr }
        XCTAssertEqual(asrStep?.status, .success)

        let outputStep = steps.first { $0.kind == .output }
        XCTAssertEqual(outputStep?.status, .success)

        let llmStep = steps.first { $0.kind == .llm }
        XCTAssertEqual(llmStep?.status, .skipped)

        let textReplacementStep = steps.first { $0.kind == .textReplacement }
        XCTAssertEqual(textReplacementStep?.status, .skipped)
    }

    func testPipelineStepsWithSuccessfulLLMShowsSuccess() {
        let trace = TextProcessingTrace(
            llm: LLMRefinementTrace(
                providerID: "test",
                providerName: "Test",
                endpoint: "https://example.com",
                model: "gpt-4",
                temperature: 0.2,
                timeoutSeconds: 30,
                requestBodyJSON: "{}",
                responseText: "response",
                statusCode: 200,
                durationMS: 1500,
                errorMessage: nil,
                completedAt: Date()
            )
        )
        let detail = makeDetail(trace: trace, taskMode: nil)
        let steps = HomeHistoryDetailPresentation.pipelineSteps(for: detail)

        let llmStep = steps.first { $0.kind == .llm }
        XCTAssertEqual(llmStep?.status, .success)
    }

    func testPipelineStepsWithFailedLLMShowsFailed() {
        let trace = TextProcessingTrace(
            llm: LLMRefinementTrace(
                providerID: "test",
                providerName: "Test",
                endpoint: "https://example.com",
                model: "gpt-4",
                temperature: 0.2,
                timeoutSeconds: 30,
                requestBodyJSON: "{}",
                responseText: nil,
                statusCode: 500,
                durationMS: 1500,
                errorMessage: "server error",
                completedAt: Date()
            )
        )
        let detail = makeDetail(trace: trace, taskMode: nil)
        let steps = HomeHistoryDetailPresentation.pipelineSteps(for: detail)

        let llmStep = steps.first { $0.kind == .llm }
        XCTAssertEqual(llmStep?.status, .failed)
    }

    func testPipelineStepsWithVoiceCorrectionHitsShowsHit() {
        let trace = TextProcessingTrace(
            voiceCorrection: VoiceCorrectionTrace(
                candidateEvents: [],
                appliedEvents: [
                    CorrectionEvent(
                        ruleID: UUID(),
                        original: "QW3A",
                        replacement: "Qwen3",
                        range: CorrectionTextRange(location: 0, length: 4),
                        scope: .global,
                        source: .manual
                    )
                ]
            )
        )
        let detail = makeDetail(trace: trace, taskMode: nil)
        let steps = HomeHistoryDetailPresentation.pipelineSteps(for: detail)

        let textReplacementStep = steps.first { $0.kind == .textReplacement }
        XCTAssertEqual(textReplacementStep?.status, .hit)
    }

    func testPipelineStepsWithDeterministicChangesShowsModified() {
        let trace = TextProcessingTrace(
            deterministic: DeterministicProcessingTrace(
                enabled: true,
                isCodingContext: false,
                preLLM: DeterministicProcessingPhaseTrace(
                    phase: "pre_llm",
                    enabledProcessors: ["filler_word_filtering"],
                    inputCharacterCount: 4,
                    outputCharacterCount: 3,
                    inputHash: "before",
                    outputHash: "after"
                ),
                postLLM: DeterministicProcessingPhaseTrace(
                    phase: "post_llm",
                    enabledProcessors: ["punctuation_optimization"],
                    inputCharacterCount: 3,
                    outputCharacterCount: 4,
                    inputHash: "post_before",
                    outputHash: "post_after"
                )
            )
        )
        let detail = makeDetail(trace: trace, taskMode: nil)
        let steps = HomeHistoryDetailPresentation.pipelineSteps(for: detail)

        XCTAssertEqual(steps.first { $0.kind == .deterministic }?.status, .modified)
    }

    func testPipelineStepsExcludesDeterministicAndTextReplacementForAgentCompose() {
        let detail = makeDetail(trace: nil, taskMode: .agentCompose)
        let steps = HomeHistoryDetailPresentation.pipelineSteps(for: detail)

        // Agent compose should not show deterministic or text replacement steps.
        XCTAssertNil(steps.first { $0.kind == .deterministic })
        XCTAssertNil(steps.first { $0.kind == .textReplacement })
        // But ASR, context, LLM, and output should still be present.
        XCTAssertNotNil(steps.first { $0.kind == .asr })
        XCTAssertNotNil(steps.first { $0.kind == .context })
        XCTAssertNotNil(steps.first { $0.kind == .llm })
        XCTAssertNotNil(steps.first { $0.kind == .output })
    }

    func testPipelineStepsWithContextBoostShowsContextHit() {
        let trace = TextProcessingTrace(
            contextBoost: ContextBoostTrace(
                appName: "Codex",
                bundleID: "com.openai.codex",
                hotwords: ["Qwen3"],
                source: "current_window_ocr",
                ttlSeconds: 300,
                appliedToLLMPrompt: true,
                failureReason: nil
            )
        )
        let detail = makeDetail(trace: trace, contextPreview: "Qwen3 文档")
        let steps = HomeHistoryDetailPresentation.pipelineSteps(for: detail)

        XCTAssertEqual(steps.first { $0.kind == .context }?.status, .hit)
    }

    func testPipelineStepsWithContextPreviewOnlyShowsContextExecuted() {
        let detail = makeDetail(trace: nil, contextPreview: "当前窗口文本")
        let steps = HomeHistoryDetailPresentation.pipelineSteps(for: detail)

        XCTAssertEqual(steps.first { $0.kind == .context }?.status, .executed)
    }

    func testPipelineStepsWithContextFailureShowsContextFailed() {
        let trace = TextProcessingTrace(
            contextBoost: ContextBoostTrace(
                appName: "Codex",
                bundleID: "com.openai.codex",
                hotwords: [],
                source: "current_window_ocr",
                ttlSeconds: 300,
                appliedToLLMPrompt: false,
                failureReason: "context_boost_timeout"
            )
        )
        let detail = makeDetail(trace: trace)
        let steps = HomeHistoryDetailPresentation.pipelineSteps(for: detail)

        XCTAssertEqual(steps.first { $0.kind == .context }?.status, .failed)
    }

    func testDiffStatusTextShowsFailedWhenLLMFailed() {
        let trace = TextProcessingTrace(
            llm: LLMRefinementTrace(
                providerID: "test",
                providerName: "Test",
                endpoint: "https://example.com",
                model: "gpt-4",
                temperature: 0.2,
                timeoutSeconds: 30,
                requestBodyJSON: "{}",
                responseText: nil,
                statusCode: 500,
                durationMS: 1500,
                errorMessage: "server error",
                completedAt: Date()
            )
        )
        let detail = makeDetail(rawText: "原文", finalText: "原文", trace: trace)

        XCTAssertEqual(
            HomeHistoryDetailPresentation.diffStatusText(for: detail),
            L10n.localize("home.detail.diff.failed", comment: "Diff failed status")
        )
    }

    func testDiffStatusTextShowsUnmodifiedWhenRawEqualsFinal() {
        let detail = makeDetail(rawText: "相同文本", finalText: "相同文本", trace: nil)

        XCTAssertEqual(
            HomeHistoryDetailPresentation.diffStatusText(for: detail),
            L10n.localize("home.detail.diff.unmodified", comment: "Diff unmodified status")
        )
    }

    func testDiffStatusTextShowsModifiedWhenVoiceCorrectionApplied() {
        let trace = TextProcessingTrace(
            voiceCorrection: VoiceCorrectionTrace(
                candidateEvents: [],
                appliedEvents: [
                    CorrectionEvent(
                        ruleID: UUID(),
                        original: "QW3A",
                        replacement: "Qwen3",
                        range: CorrectionTextRange(location: 0, length: 4),
                        scope: .global,
                        source: .manual
                    )
                ]
            )
        )
        let detail = makeDetail(rawText: "QW3A", finalText: "Qwen3", trace: trace)

        let expected = String(
            format: L10n.localize("home.detail.diff.modified_format", comment: "Diff modified format"),
            1
        )
        XCTAssertEqual(
            HomeHistoryDetailPresentation.diffStatusText(for: detail),
            expected
        )
    }

    // MARK: - Deterministic phase comparison input

    private func makePhase(
        inputText: String? = nil,
        outputText: String? = nil,
        inputHash: String = "hash",
        outputHash: String = "hash"
    ) -> DeterministicProcessingPhaseTrace {
        DeterministicProcessingPhaseTrace(
            phase: "pre_llm",
            enabledProcessors: ["punctuation_optimization"],
            displayProcessorIDs: nil,
            changedProcessorIDs: [],
            inputCharacterCount: inputText?.count ?? 0,
            outputCharacterCount: outputText?.count ?? 0,
            inputText: inputText,
            outputText: outputText,
            inputHash: inputHash,
            outputHash: outputHash
        )
    }

    func testDeterministicComparisonInputUsesPhaseInputAndOutputNotTopLevelRawFinal() {
        let phase = makePhase(
            inputText: "处理前文本",
            outputText: "处理后文本",
            inputHash: "in",
            outputHash: "out"
        )
        // Top-level raw/final on the detail are deliberately different from
        // the phase's input/output to catch any accidental wiring.
        let detail = makeDetail(rawText: "顶层原文", finalText: "顶层最终", trace: nil)

        let input = HomeHistoryDetailPresentation.deterministicComparisonInput(for: phase)
        XCTAssertEqual(input?.sourceText, "处理前文本")
        XCTAssertEqual(input?.processedText, "处理后文本")
        XCTAssertNotEqual(input?.sourceText, detail.rawText)
        XCTAssertNotEqual(input?.processedText, detail.finalText)
    }

    func testDeterministicComparisonInputReturnsNilWhenPhaseMissingBeforeOrAfterText() {
        let noInput = makePhase(inputText: nil, outputText: "处理后")
        XCTAssertNil(HomeHistoryDetailPresentation.deterministicComparisonInput(for: noInput))

        let noOutput = makePhase(inputText: "处理前", outputText: nil)
        XCTAssertNil(HomeHistoryDetailPresentation.deterministicComparisonInput(for: noOutput))

        let bothNil = makePhase(inputText: nil, outputText: nil)
        XCTAssertNil(HomeHistoryDetailPresentation.deterministicComparisonInput(for: bothNil))
    }

    func testDeterministicComparisonInputUsesLocalizedSourceAndProcessedTitles() {
        let phase = makePhase(inputText: "a", outputText: "b", inputHash: "a", outputHash: "b")
        let input = HomeHistoryDetailPresentation.deterministicComparisonInput(for: phase)

        XCTAssertEqual(input?.sourceTitle, L10n.localize("home.detail.comparison.mode.source", comment: "Source mode label"))
        XCTAssertEqual(input?.processedTitle, L10n.localize("home.detail.comparison.mode.processed", comment: "Processed mode label"))
    }

    func testDeterministicComparisonInputPreAndPostLLMPhasesUseTheirOwnTexts() {
        let prePhase = DeterministicProcessingPhaseTrace(
            phase: "pre_llm",
            enabledProcessors: ["punctuation_optimization"],
            displayProcessorIDs: nil,
            changedProcessorIDs: [],
            inputCharacterCount: 4,
            outputCharacterCount: 4,
            inputText: "pre输入",
            outputText: "pre输出",
            inputHash: "pre-in",
            outputHash: "pre-out"
        )
        let postPhase = DeterministicProcessingPhaseTrace(
            phase: "post_llm",
            enabledProcessors: ["cjk_latin_spacing"],
            displayProcessorIDs: nil,
            changedProcessorIDs: [],
            inputCharacterCount: 5,
            outputCharacterCount: 5,
            inputText: "post输入",
            outputText: "post输出",
            inputHash: "post-in",
            outputHash: "post-out"
        )

        let preInput = HomeHistoryDetailPresentation.deterministicComparisonInput(for: prePhase)
        let postInput = HomeHistoryDetailPresentation.deterministicComparisonInput(for: postPhase)

        XCTAssertEqual(preInput?.sourceText, "pre输入")
        XCTAssertEqual(preInput?.processedText, "pre输出")
        XCTAssertEqual(postInput?.sourceText, "post输入")
        XCTAssertEqual(postInput?.processedText, "post输出")
        // Phases must not cross-reference each other's text.
        XCTAssertNotEqual(preInput?.sourceText, postInput?.sourceText)
        XCTAssertNotEqual(preInput?.processedText, postInput?.processedText)
    }

    func testDefaultSelectedStepStartsFromASRWhenLLMAvailable() {
        let trace = TextProcessingTrace(
            llm: LLMRefinementTrace(
                providerID: "test",
                providerName: "Test",
                endpoint: "https://example.com",
                model: "gpt-4",
                temperature: 0.2,
                timeoutSeconds: 30,
                requestBodyJSON: "{}",
                responseText: "response",
                statusCode: 200,
                durationMS: 1500,
                errorMessage: nil,
                completedAt: Date()
            )
        )
        let detail = makeDetail(trace: trace, taskMode: nil)

        XCTAssertEqual(
            HomeHistoryDetailPresentation.defaultSelectedStep(for: detail),
            .asr
        )
    }

    func testDefaultSelectedStepFallsBackToASRWhenNoLLM() {
        let detail = makeDetail(trace: nil, taskMode: nil)

        XCTAssertEqual(
            HomeHistoryDetailPresentation.defaultSelectedStep(for: detail),
            .asr
        )
    }

    func testDefaultSelectedStepStartsFromASRWhenContextExists() {
        let trace = TextProcessingTrace(
            contextBoost: ContextBoostTrace(
                appName: "Codex",
                bundleID: "com.openai.codex",
                hotwords: ["Qwen3"],
                source: "current_window_ocr",
                ttlSeconds: 300,
                appliedToLLMPrompt: true,
                failureReason: nil
            )
        )
        let detail = makeDetail(trace: trace)

        XCTAssertEqual(
            HomeHistoryDetailPresentation.defaultSelectedStep(for: detail),
            .asr
        )
    }

    func testPipelineStatusTextShowsLocalWhenNoLLM() {
        let detail = makeDetail(trace: nil, taskMode: nil)

        XCTAssertEqual(
            HomeHistoryDetailPresentation.pipelineStatusText(for: detail),
            L10n.localize("home.detail.pipeline.status.local", comment: "Local processing complete")
        )
    }
}
