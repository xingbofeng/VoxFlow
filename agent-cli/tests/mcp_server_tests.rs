use std::fs;

use tempfile::tempdir;
use voxflow::mcp::{identity_hint, McpServer};
use voxflow::router::Router;
use voxflow::session::{ProcessInspector, SessionCard, SessionStatus};

struct Alive;
impl ProcessInspector for Alive {
    fn is_alive(&self, _: u32) -> bool {
        true
    }
}

fn setup() -> (tempfile::TempDir, McpServer) {
    let temp = tempdir().unwrap();
    let input = temp.path().join("agent.stdin");
    fs::write(&input, "").unwrap();
    let router = Router::new(temp.path());
    let mut card = SessionCard::new(
        vec!["codex".into()],
        input,
        std::process::id(),
        std::process::id(),
    );
    card.agent_id = "self-agent".into();
    card.status = SessionStatus::Active;
    router.registry().upsert(&card).unwrap();
    let server = McpServer::new(router, "self-agent");
    (temp, server)
}

#[test]
fn initialize_and_list_tools_expose_only_four_self_reporting_tools() {
    let (_temp, server) = setup();
    let initialized = server.handle_value(serde_json::json!({
        "jsonrpc":"2.0", "id":1, "method":"initialize", "params":{}
    }));
    assert_eq!(
        initialized["result"]["serverInfo"]["name"],
        "voxflow-agent-identity"
    );

    let listed = server.handle_value(serde_json::json!({
        "jsonrpc":"2.0", "id":2, "method":"tools/list", "params":{}
    }));
    let names: Vec<_> = listed["result"]["tools"]
        .as_array()
        .unwrap()
        .iter()
        .map(|tool| tool["name"].as_str().unwrap())
        .collect();
    assert_eq!(
        names,
        vec![
            "get_self_agent",
            "update_self_summary",
            "attach_self_reference",
            "get_self_dispatch_log"
        ]
    );
    assert!(!names.contains(&"send_message"));
    assert!(!names.contains(&"learn_alias"));
}

#[test]
fn self_tools_update_only_the_bound_agent_and_read_its_dispatch_log() {
    let (temp, server) = setup();
    let updated = call(
        &server,
        "update_self_summary",
        serde_json::json!({
            "label":"前端", "summary":"处理设置页按钮", "topics":["SwiftUI"], "phase":"editing", "ttl_seconds":600
        }),
    );
    assert_eq!(updated["result"]["structuredContent"]["updated"], true);
    let attached = call(
        &server,
        "attach_self_reference",
        serde_json::json!({
            "provider":"codex", "kind":"session_id", "value":"session-9"
        }),
    );
    assert_eq!(attached["result"]["structuredContent"]["attached"], true);

    let router = Router::new(temp.path());
    router
        .append_dispatch("self-agent", "检查按钮", true, None, 100.0)
        .unwrap();
    let logs = call(
        &server,
        "get_self_dispatch_log",
        serde_json::json!({"limit":5}),
    );
    assert_eq!(
        logs["result"]["structuredContent"]["entries"][0]["message"],
        "检查按钮"
    );
    let self_agent = call(&server, "get_self_agent", serde_json::json!({}));
    assert_eq!(
        self_agent["result"]["structuredContent"]["agent"]["self_summary"]["label"],
        "前端"
    );
    assert_eq!(
        self_agent["result"]["structuredContent"]["agent"]["provider_session_refs"][0]["value"],
        "session-9"
    );
}

#[test]
fn summary_validation_and_expiry_prevent_invalid_identity_signals() {
    let (temp, server) = setup();
    let invalid = call(
        &server,
        "update_self_summary",
        serde_json::json!({
            "label":"这是一个超过二十个字符限制的非常非常非常长的任务助手名称",
            "summary":"短摘要", "topics":[], "phase":"editing"
        }),
    );
    assert!(invalid["result"]["isError"].as_bool().unwrap());

    call(
        &server,
        "update_self_summary",
        serde_json::json!({
            "label":"前端", "summary":"页面", "topics":[], "phase":"editing"
        }),
    );
    let router = Router::new(temp.path());
    router
        .registry()
        .update("self-agent", |card| {
            card.self_summary.as_mut().unwrap().expires_at = 0.0;
            Ok(())
        })
        .unwrap();
    assert_eq!(
        router.resolve_utterance("前端，继续", &Alive).unwrap(),
        voxflow::router::ResolveOutcome::NotFound
    );
}

#[test]
fn tool_execution_errors_are_mcp_results_but_protocol_errors_are_jsonrpc_errors() {
    let (_temp, server) = setup();

    let missing_argument = call(
        &server,
        "attach_self_reference",
        serde_json::json!({"provider":"codex", "kind":"session_id"}),
    );
    assert!(missing_argument.get("error").is_none());
    assert!(missing_argument["result"]["isError"].as_bool().unwrap());
    assert!(missing_argument["result"]["content"][0]["text"]
        .as_str()
        .unwrap()
        .contains("missing string argument: value"));

    let unknown_method = server.handle_value(serde_json::json!({
        "jsonrpc":"2.0", "id":11, "method":"unknown/method", "params":{}
    }));
    assert!(unknown_method.get("result").is_none());
    assert_eq!(unknown_method["error"]["code"], -32601);
}

#[test]
fn identity_hint_is_low_frequency_and_cannot_change_user_work() {
    let hint = identity_hint();
    assert!(hint.contains("低频"));
    assert!(hint.contains("不要修改用户任务"));
    assert!(hint.contains("不要自动批准权限"));
    assert!(hint.contains("不要向其他 Agent 派发任务"));
}

#[test]
fn initialize_declares_prompts_capability_and_list_returns_empty() {
    let (_temp, server) = setup();
    let initialized = server.handle_value(serde_json::json!({
        "jsonrpc":"2.0", "id":1, "method":"initialize", "params":{}
    }));
    assert_eq!(
        initialized["result"]["capabilities"]["prompts"],
        serde_json::json!({})
    );

    // CodeBuddy Code 的 MCP 客户端即便 capabilities 已声明，仍会周期性轮询
    // prompts/list。返回空列表（而非 method not found）以避免日志噪音。
    let listed = server.handle_value(serde_json::json!({
        "jsonrpc":"2.0", "id":2, "method":"prompts/list", "params":{}
    }));
    assert!(listed.get("error").is_none());
    assert_eq!(listed["result"]["prompts"], serde_json::json!([]));
}

fn call(server: &McpServer, name: &str, arguments: serde_json::Value) -> serde_json::Value {
    server.handle_value(serde_json::json!({
        "jsonrpc":"2.0", "id":10, "method":"tools/call",
        "params":{"name":name, "arguments":arguments}
    }))
}
