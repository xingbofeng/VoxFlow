import XCTest
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
            "这条AI 编程记录不会调用文本纠错模型；语音原文和生成结果已单独保留。"
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
    }
}
