use std::io::{Cursor, Read, Write};
use std::net::TcpListener;
use voxflow::builtin_agent::{
    builtin_agent_system_prompt, AgentContentPart, AgentLoopDecision, AgentLoopEngine,
    AgentLoopGuard, AgentLoopLimits, AgentModel, AgentResponse, AgentToolHost, BuiltinAgentEvent,
    BuiltinAgentRunRequest, BuiltinAgentSecret, ImageContext, ImagePayload, ProviderConfig,
    ToolCall, ToolResult, BUILTIN_AGENT_PROTOCOL_SCHEMA_VERSION,
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
fn loop_guard_allows_the_configured_step_and_tool_limits_then_stops() {
    let mut guard = AgentLoopGuard::new(AgentLoopLimits::default());
    for _ in 0..12 {
        assert_eq!(guard.record_step(), AgentLoopDecision::Continue);
    }
    assert_eq!(
        guard.record_step(),
        AgentLoopDecision::StopWithFailure {
            reason: "max_steps_exceeded".into()
        }
    );

    let mut guard = AgentLoopGuard::new(AgentLoopLimits::default());
    for index in 0..10 {
        let call = ToolCall {
            id: format!("call-{index}"),
            name: "read_file".into(),
            arguments: serde_json::json!({"file_path": format!("note-{index}.txt")}),
        };
        assert_eq!(guard.record_tool_call(&call), AgentLoopDecision::Continue);
    }
    assert_eq!(
        guard.record_tool_call(&ToolCall {
            id: "call-11".into(),
            name: "read_file".into(),
            arguments: serde_json::json!({"file_path":"note-11.txt"}),
        }),
        AgentLoopDecision::StopWithFailure {
            reason: "max_tool_calls_exceeded".into()
        }
    );
}

#[test]
fn empty_completion_finishes_without_inventing_output() {
    let model = ScriptedModel::new(vec![AgentResponse {
        text: None,
        tool_calls: vec![],
    }]);
    let host = RecordingToolHost::new(vec![]);
    let mut engine = AgentLoopEngine::new(model, host);

    let result = engine.run(builtin_request("do not make anything up")).unwrap();

    assert_eq!(result.final_text, None);
    assert!(result.tool_results.is_empty());
    assert!(matches!(result.events.last(), Some(BuiltinAgentEvent::TurnCompleted { summary }) if summary.is_empty()));
}

#[test]
fn safe_event_payload_redacts_api_key_and_image_payload() {
    let request = BuiltinAgentRunRequest {
        schema_version: BUILTIN_AGENT_PROTOCOL_SCHEMA_VERSION,
        task_id: "task-1".into(),
        instruction: "帮我总结这个截图".into(),
        workspace_directory: None,
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
fn debug_serialization_and_event_payloads_do_not_leak_secrets() {
    let secret = BuiltinAgentSecret::new("sk-debug-secret");
    assert!(!format!("{secret:?}").contains("sk-debug-secret"));

    let event = BuiltinAgentEvent::ToolRequested {
        tool_call: ToolCall {
            id: "call-1".into(),
            name: "http_request".into(),
            arguments: serde_json::json!({
                "apiKey": "sk-event-secret",
                "headers": { "Authorization": "Bearer another-secret" },
                "body": "safe body"
            }),
        },
    };
    let safe = serde_json::to_string(&event.safe_for_trace()).unwrap();

    assert!(!safe.contains("sk-event-secret"));
    assert!(!safe.contains("another-secret"));
    assert!(safe.contains("[redacted]"));
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
fn runtime_events_emit_an_explicit_current_schema_version() {
    let event = BuiltinAgentEvent::ModelDelta {
        text: "partial".into(),
    };

    let encoded = event.safe_for_trace();

    assert_eq!(
        encoded["schemaVersion"],
        serde_json::json!(BUILTIN_AGENT_PROTOCOL_SCHEMA_VERSION)
    );
    assert_eq!(encoded["event"], "modelDelta");

    let run_started = BuiltinAgentEvent::RunStarted {
        request: builtin_request("test"),
    };
    assert_eq!(run_started.safe_for_trace()["event"], "runStarted");
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

#[test]
fn platform_neutral_system_prompt_preserves_agent_permission_semantics_and_workspace() {
    let prompt =
        builtin_agent_system_prompt(Some(r"C:\Users\me\AppData\Local\VoxFlow\sessions\task-1"));

    assert!(prompt.contains("built-in Agent Compose runtime"));
    assert!(prompt.contains("trusted user intent"));
    assert!(prompt.contains("untrusted context"));
    assert!(prompt.contains("Do not press Enter or submit forms"));
    assert!(prompt.contains("C:\\Users\\me\\AppData\\Local\\VoxFlow\\sessions\\task-1"));
    assert!(!prompt.contains("macOS"));
    assert!(!prompt.contains("Swift tool host"));
}

#[test]
fn unsupported_or_truncated_run_requests_fail_without_echoing_secret_input() {
    let unsupported = r#"{"schemaVersion":2,"taskId":"task-1","instruction":"hello","provider":{"providerId":"p","baseUrl":"https://example.test/v1","model":"m","apiKey":"sk-do-not-log"},"content":[{"type":"text","text":"intent"}],"limits":{"maxSteps":12,"maxToolCalls":10,"maxRepeatedToolCalls":2}}"#;
    let parsed: BuiltinAgentRunRequest = serde_json::from_str(unsupported).unwrap();
    assert_eq!(parsed.schema_version, 2);
    let mut stdout = Vec::new();
    let error =
        voxflow::builtin_agent::run_builtin_agent_stdio(Cursor::new(unsupported), &mut stdout)
            .unwrap_err()
            .to_string();

    assert_eq!(error, "unsupported_schema_version");
    assert!(stdout.is_empty());
    assert!(!error.contains("sk-do-not-log"));

    let mut stdout = Vec::new();
    let error = voxflow::builtin_agent::run_builtin_agent_stdio(
        Cursor::new("{\"provider\":{\"apiKey\":\"sk-truncated-secret\"}"),
        &mut stdout,
    )
    .unwrap_err()
    .to_string();

    assert_eq!(error, "invalid_run_request");
    assert!(stdout.is_empty());
    assert!(!error.contains("sk-truncated-secret"));
}

#[test]
fn stdio_protocol_reports_model_http_failure_without_echoing_credentials() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let endpoint = format!("http://{}", listener.local_addr().unwrap());
    let server = std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        stream
            .set_read_timeout(Some(std::time::Duration::from_secs(2)))
            .unwrap();
        let mut request = Vec::new();
        loop {
            let mut chunk = [0_u8; 1024];
            let read = stream.read(&mut chunk).unwrap();
            request.extend_from_slice(&chunk[..read]);
            let Some(headers_end) = request.windows(4).position(|window| window == b"\r\n\r\n") else {
                continue;
            };
            let headers = String::from_utf8_lossy(&request[..headers_end]);
            let content_length = headers
                .lines()
                .find_map(|line| {
                    line.split_once(':').and_then(|(name, value)| {
                        name.eq_ignore_ascii_case("content-length")
                            .then(|| value.trim().parse::<usize>().ok())
                            .flatten()
                    })
                });
            let Some(content_length) = content_length else {
                continue;
            };
            if request.len() >= headers_end + 4 + content_length {
                break;
            }
        }
        stream
            .write_all(
                b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 13\r\nConnection: close\r\n\r\nupstream down",
            )
            .unwrap();
    });
    let request = format!(
        r#"{{"schemaVersion":1,"taskId":"task-http","instruction":"summarize","provider":{{"providerId":"test","baseUrl":"{endpoint}","model":"test-model","apiKey":"sk-never-echo","timeoutSeconds":1}},"content":[{{"type":"text","text":"untrusted context"}}],"limits":{{"maxSteps":12,"maxToolCalls":10,"maxRepeatedToolCalls":2}}}}"#
    );
    let mut stdout = Vec::new();

    let exit_code = voxflow::builtin_agent::run_builtin_agent_stdio(Cursor::new(request), &mut stdout)
        .unwrap();

    server.join().unwrap();
    let output = String::from_utf8(stdout).unwrap();
    assert_eq!(exit_code, 1);
    assert!(output.contains("runStarted"));
    assert!(output.contains("error"));
    assert!(output.contains("HTTP 502"), "{output}");
    assert!(!output.contains("sk-never-echo"));
}

fn builtin_request(instruction: &str) -> BuiltinAgentRunRequest {
    BuiltinAgentRunRequest {
        schema_version: BUILTIN_AGENT_PROTOCOL_SCHEMA_VERSION,
        task_id: "task-mail-reply".into(),
        instruction: instruction.into(),
        workspace_directory: None,
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
