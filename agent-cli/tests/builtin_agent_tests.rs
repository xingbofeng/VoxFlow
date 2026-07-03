use voxflow::builtin_agent::{
    AgentContentPart, AgentLoopDecision, AgentLoopEngine, AgentLoopGuard, AgentLoopLimits,
    AgentModel, AgentResponse, AgentToolHost, BuiltinAgentEvent, BuiltinAgentRunRequest,
    BuiltinAgentSecret, ImageContext, ImagePayload, ProviderConfig, ToolCall, ToolResult,
};

#[test]
fn response_without_tool_calls_finishes_the_loop() {
    let guard = AgentLoopGuard::new(AgentLoopLimits::default());
    let response = AgentResponse {
        text: Some("已整理好回复。".into()),
        tool_calls: vec![],
    };

    assert_eq!(
        guard.decide_after_response(&response),
        AgentLoopDecision::Finish
    );
}

#[test]
fn repeated_equivalent_tool_calls_are_stopped() {
    let mut guard = AgentLoopGuard::new(AgentLoopLimits {
        max_steps: 12,
        max_tool_calls: 10,
        max_repeated_tool_calls: 2,
    });
    let call = ToolCall {
        id: "call-1".into(),
        name: "read_frontmost_context".into(),
        arguments: serde_json::json!({"scope":"frontmost"}),
    };

    assert_eq!(guard.record_tool_call(&call), AgentLoopDecision::Continue);
    assert_eq!(guard.record_tool_call(&call), AgentLoopDecision::Continue);
    assert_eq!(
        guard.record_tool_call(&call),
        AgentLoopDecision::StopWithFailure {
            reason: "repeated_tool_call".into()
        }
    );
}

#[test]
fn safe_event_payload_redacts_api_key_and_image_payload() {
    let request = BuiltinAgentRunRequest {
        task_id: "task-1".into(),
        instruction: "帮我总结这个截图".into(),
        provider: ProviderConfig {
            provider_id: "openrouter".into(),
            base_url: "https://openrouter.ai/api/v1".into(),
            model: "openai/gpt-oss-120b".into(),
            api_key: BuiltinAgentSecret::new("sk-live-secret"),
            timeout_seconds: Some(45),
        },
        image_context: Some(ImageContext {
            payload: ImagePayload::DataURL("data:image/jpeg;base64,VERY-LONG-PAYLOAD".into()),
            metadata: serde_json::json!({
                "compressedBytes": 98000,
                "mimeType": "image/jpeg"
            }),
        }),
        content: vec![AgentContentPart::Text {
            text: "visible OCR".into(),
        }],
        limits: AgentLoopLimits::default(),
    };

    let event = BuiltinAgentEvent::RunStarted { request };
    let safe = event.safe_for_trace();
    let encoded = serde_json::to_string(&safe).unwrap();

    assert!(encoded.contains("openrouter"));
    assert!(encoded.contains("imagePayloadRedacted"));
    assert!(!encoded.contains("sk-live-secret"));
    assert!(!encoded.contains("VERY-LONG-PAYLOAD"));
}

#[test]
fn tool_result_failure_is_structured_for_the_next_model_turn() {
    let result = ToolResult::failure("replace_selection", "missing_selection");
    let encoded = serde_json::to_value(result).unwrap();

    assert_eq!(encoded["ok"], false);
    assert_eq!(encoded["toolName"], "replace_selection");
    assert_eq!(encoded["error"]["code"], "missing_selection");
}

#[test]
fn runtime_events_serialize_with_swift_contract_keys() {
    let event = BuiltinAgentEvent::ToolRequested {
        tool_call: ToolCall {
            id: "replace-1".into(),
            name: "replace_selection".into(),
            arguments: serde_json::json!({"text":"正式版本"}),
        },
    };

    let encoded = serde_json::to_value(event).unwrap();

    assert_eq!(encoded["event"], "toolRequested");
    assert!(encoded.get("toolCall").is_some());
    assert!(encoded.get("tool_call").is_none());
}

#[test]
fn mail_reply_scenario_streams_tool_events_and_stops_on_final() {
    let request = builtin_request("帮我回复这封邮件，礼貌一点，直接替换选区");
    let model = ScriptedModel::new(vec![
        AgentResponse {
            text: None,
            tool_calls: vec![ToolCall {
                id: "read-1".into(),
                name: "read_selection_or_input_text".into(),
                arguments: serde_json::json!({}),
            }],
        },
        AgentResponse {
            text: Some("我会把选区改成一封简短礼貌的回复。".into()),
            tool_calls: vec![ToolCall {
                id: "replace-1".into(),
                name: "replace_selection".into(),
                arguments: serde_json::json!({
                    "text": "收到，谢谢提醒。我会尽快处理并在完成后同步进展。"
                }),
            }],
        },
        AgentResponse {
            text: Some("已替换选区。".into()),
            tool_calls: vec![],
        },
    ]);
    let host = RecordingToolHost::new(vec![
        ToolResult::success(
            "read_selection_or_input_text",
            serde_json::json!({
                "selectedText": "能不能今天下午前给我？",
                "source": "selection"
            }),
        ),
        ToolResult::success(
            "replace_selection",
            serde_json::json!({
                "kind": "replaced"
            }),
        ),
    ]);
    let mut engine = AgentLoopEngine::new(model, host);

    let result = engine.run(request).unwrap();

    assert_eq!(result.final_text.as_deref(), Some("已替换选区。"));
    assert_eq!(result.tool_results.len(), 2);
    assert_eq!(
        result
            .events
            .iter()
            .map(BuiltinAgentEvent::kind)
            .collect::<Vec<_>>(),
        vec![
            "runStarted",
            "turnStarted",
            "toolRequested",
            "toolResolved",
            "turnStarted",
            "modelDelta",
            "toolRequested",
            "toolResolved",
            "turnStarted",
            "turnCompleted"
        ]
    );
}

#[test]
fn missing_selection_scenario_stops_repeated_failed_tool_results() {
    let request = builtin_request("把这里改得更正式一点");
    let model = ScriptedModel::new(vec![
        AgentResponse {
            text: None,
            tool_calls: vec![ToolCall {
                id: "replace-1".into(),
                name: "replace_selection".into(),
                arguments: serde_json::json!({"text": "第一版"}),
            }],
        },
        AgentResponse {
            text: None,
            tool_calls: vec![ToolCall {
                id: "replace-2".into(),
                name: "replace_selection".into(),
                arguments: serde_json::json!({"text": "第二版"}),
            }],
        },
        AgentResponse {
            text: None,
            tool_calls: vec![ToolCall {
                id: "replace-3".into(),
                name: "replace_selection".into(),
                arguments: serde_json::json!({"text": "第三版"}),
            }],
        },
        AgentResponse {
            text: Some("不应该走到这里".into()),
            tool_calls: vec![],
        },
    ]);
    let host = RecordingToolHost::new(vec![
        ToolResult::failure("replace_selection", "missing_selection"),
        ToolResult::failure("replace_selection", "missing_selection"),
        ToolResult::failure("replace_selection", "missing_selection"),
    ]);
    let mut engine = AgentLoopEngine::new(model, host);

    let result = engine.run(request).unwrap();

    assert_eq!(result.final_text, None);
    assert_eq!(result.tool_results.len(), 3);
    assert!(result.events.iter().any(|event| {
        matches!(
            event,
            BuiltinAgentEvent::Error { reason } if reason == "repeated_failed_tool_result"
        )
    }));
}

#[test]
fn provider_request_timeout_defaults_and_clamps() {
    let mut provider = ProviderConfig {
        provider_id: "openrouter".into(),
        base_url: "https://openrouter.ai/api/v1".into(),
        model: "openai/gpt-oss-120b".into(),
        api_key: BuiltinAgentSecret::new("sk-live-secret"),
        timeout_seconds: None,
    };

    assert_eq!(provider.request_timeout_seconds(), 300);
    provider.timeout_seconds = Some(0);
    assert_eq!(provider.request_timeout_seconds(), 1);
    provider.timeout_seconds = Some(1_000);
    assert_eq!(provider.request_timeout_seconds(), 600);
}

fn builtin_request(instruction: &str) -> BuiltinAgentRunRequest {
    BuiltinAgentRunRequest {
        task_id: "task-mail-reply".into(),
        instruction: instruction.into(),
        provider: ProviderConfig {
            provider_id: "openrouter".into(),
            base_url: "https://openrouter.ai/api/v1".into(),
            model: "openai/gpt-oss-120b".into(),
            api_key: BuiltinAgentSecret::new("sk-live-secret"),
            timeout_seconds: Some(45),
        },
        image_context: Some(ImageContext {
            payload: ImagePayload::DataURL("data:image/jpeg;base64,MAIL-SCREENSHOT".into()),
            metadata: serde_json::json!({
                "compressedBytes": 99000,
                "fallbackReason": null
            }),
        }),
        content: vec![AgentContentPart::Text {
            text: "App: Mail\nWindow: Inbox\nSelected text available".into(),
        }],
        limits: AgentLoopLimits::default(),
    }
}

struct ScriptedModel {
    responses: Vec<AgentResponse>,
}

impl ScriptedModel {
    fn new(responses: Vec<AgentResponse>) -> Self {
        Self {
            responses: responses.into_iter().rev().collect(),
        }
    }
}

impl AgentModel for ScriptedModel {
    fn next_response(&mut self) -> anyhow::Result<AgentResponse> {
        self.responses
            .pop()
            .ok_or_else(|| anyhow::anyhow!("script exhausted"))
    }
}

struct RecordingToolHost {
    results: Vec<ToolResult>,
}

impl RecordingToolHost {
    fn new(results: Vec<ToolResult>) -> Self {
        Self {
            results: results.into_iter().rev().collect(),
        }
    }
}

impl AgentToolHost for RecordingToolHost {
    fn call_tool(&mut self, _call: &ToolCall) -> ToolResult {
        self.results
            .pop()
            .unwrap_or_else(|| ToolResult::failure("unknown", "script_exhausted"))
    }
}
