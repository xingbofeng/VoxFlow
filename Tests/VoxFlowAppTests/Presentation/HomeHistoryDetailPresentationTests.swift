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
            "OpenAI 兼容纠错服务"
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

    func testMissingTraceMessageExplainsWhatUserCanDo() {
        XCTAssertEqual(
            HomeHistoryDetailPresentation.missingTraceMessage,
            "这条记录没有模型纠错信息。可能是当时没有开启文本纠错，或者它是在追踪功能上线前生成的。点击右上角“重新处理”，即可查看是否调用模型、发送内容和返回结果。"
        )
    }

    func testAgentComposeMissingTraceMessageDoesNotOfferReprocessing() {
        XCTAssertEqual(
            HomeHistoryDetailPresentation.missingTraceMessage(for: .agentCompose),
            "这条“帮我说”记录没有保存模型调用过程，但识别原文和生成结果仍已保留。可以使用右上角“复制结果”。"
        )
    }

    func testAgentDispatchMissingTraceMessagePointsToSavedDispatchResult() {
        XCTAssertEqual(
            HomeHistoryDetailPresentation.missingTraceMessage(for: .agentDispatch),
            "这条 Vibe Coding 指挥记录不调用文本纠错模型；语音原文和调度结果已单独保留。"
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
            "LLM 模型调用失败，已保留原始识别文本。"
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
