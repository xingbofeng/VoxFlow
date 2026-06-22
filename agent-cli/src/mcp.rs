use crate::router::Router;
use crate::session::{
    ensure_private_directory, secure_private_file, ProviderReference, SystemProcessInspector,
};
use serde_json::{json, Value};
use std::fs::OpenOptions;
use std::io::{BufRead, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

pub struct McpServer {
    router: Router,
    agent_id: String,
}

impl McpServer {
    pub fn new(router: Router, agent_id: impl Into<String>) -> Self {
        Self {
            router,
            agent_id: agent_id.into(),
        }
    }

    pub fn handle_value(&self, request: Value) -> Value {
        let request_label = Self::request_label(&request);
        let id = request.get("id").cloned().unwrap_or(Value::Null);
        let result = match request["method"].as_str() {
            Some("initialize") => Ok(json!({
                "protocolVersion": "2025-03-26",
                "capabilities": {"tools": {}, "prompts": {}},
                "serverInfo": {"name": "voxflow-agent-identity", "version": env!("CARGO_PKG_VERSION")},
                "instructions": identity_hint()
            })),
            Some("notifications/initialized") => Ok(Value::Null),
            Some("tools/list") => Ok(json!({"tools": tool_definitions()})),
            Some("prompts/list") => Ok(json!({"prompts": []})),
            Some("tools/call") => self.call_tool(
                request["params"]["name"].as_str().unwrap_or_default(),
                request["params"]
                    .get("arguments")
                    .cloned()
                    .unwrap_or_else(|| json!({})),
            ),
            Some(method) => Err(anyhow::anyhow!("method not found: {method}")),
            None => Err(anyhow::anyhow!("missing method")),
        };
        let error_message = result.as_ref().err().map(|error| error.to_string());
        self.record_mcp_activity(
            &request_label,
            error_message.as_deref(),
            Self::is_reporting_request(&request_label),
        );
        match result {
            Ok(result) => json!({"jsonrpc":"2.0", "id":id, "result":result}),
            Err(error) => json!({
                "jsonrpc":"2.0", "id":id,
                "error":{"code":-32601, "message":error.to_string()}
            }),
        }
    }

    pub fn run_stdio(&self) -> anyhow::Result<()> {
        self.append_log("INFO", "MCP stdio server started");
        let stdin = std::io::stdin();
        let mut stdout = std::io::stdout();
        for line in stdin.lock().lines() {
            let line = line?;
            if line.trim().is_empty() {
                continue;
            }
            let request: Value = match serde_json::from_str(&line) {
                Ok(request) => request,
                Err(error) => {
                    self.record_mcp_activity("invalid_json", Some(&error.to_string()), false);
                    return Err(error.into());
                }
            };
            if request.get("id").is_none() {
                self.append_log(
                    "INFO",
                    &format!("notification method={}", Self::request_label(&request)),
                );
                continue;
            }
            serde_json::to_writer(&mut stdout, &self.handle_value(request))?;
            stdout.write_all(b"\n")?;
            stdout.flush()?;
        }
        self.append_log("INFO", "MCP stdio server stopped");
        Ok(())
    }

    fn call_tool(&self, name: &str, arguments: Value) -> anyhow::Result<Value> {
        let result = match name {
            "get_self_agent" => self.self_agent().map(|agent| json!({"agent":agent})),
            "update_self_summary" => (|| {
                self.router.update_summary(
                    &self.agent_id,
                    required(&arguments, "label")?,
                    required(&arguments, "summary")?,
                    string_array(&arguments, "topics")?,
                    required(&arguments, "phase")?,
                    arguments["ttl_seconds"].as_u64().unwrap_or(3600),
                )?;
                Ok(json!({"updated":true}))
            })(),
            "attach_self_reference" => (|| {
                self.router.attach_reference(
                    &self.agent_id,
                    ProviderReference {
                        provider: required(&arguments, "provider")?.to_owned(),
                        kind: required(&arguments, "kind")?.to_owned(),
                        value: required(&arguments, "value")?.to_owned(),
                        description: arguments["description"].as_str().map(str::to_owned),
                    },
                )?;
                Ok(json!({"attached":true}))
            })(),
            "get_self_dispatch_log" => self
                .router
                .dispatch_logs(
                    Some(&self.agent_id),
                    arguments["limit"].as_u64().unwrap_or(20).clamp(1, 100) as usize,
                )
                .map(|entries| json!({"entries":entries})),
            _ => Err(anyhow::anyhow!("unknown tool: {name}")),
        };
        match result {
            Ok(structured) => Ok(json!({
                "content":[{"type":"text", "text":serde_json::to_string(&structured)?}],
                "structuredContent":structured,
                "isError":false
            })),
            Err(error) => Ok(json!({
                "content":[{"type":"text", "text":error.to_string()}],
                "isError":true
            })),
        }
    }

    fn self_agent(&self) -> anyhow::Result<Value> {
        let card = self
            .router
            .registry()
            .list(true, &SystemProcessInspector)?
            .into_iter()
            .find(|card| card.agent_id == self.agent_id)
            .ok_or_else(|| anyhow::anyhow!("bound agent session not found"))?;
        Ok(serde_json::to_value(card)?)
    }

    fn record_mcp_activity(&self, method: &str, error: Option<&str>, reported: bool) {
        let _ = self.router.registry().update(&self.agent_id, |card| {
            card.mark_mcp_request(method, error, reported);
            Ok(())
        });
        match error {
            Some(error) => self.append_log(
                "ERROR",
                &format!(
                    "request method={} error={}",
                    sanitize(method),
                    sanitize(error)
                ),
            ),
            None => self.append_log("INFO", &format!("request method={}", sanitize(method))),
        }
    }

    fn append_log(&self, level: &str, message: &str) {
        let path = self.log_path();
        let Some(parent) = path.parent() else { return };
        if ensure_private_directory(parent).is_err() {
            return;
        }
        let Ok(mut file) = OpenOptions::new()
            .create(true)
            .append(true)
            .mode(0o600)
            .open(&path)
        else {
            return;
        };
        let _ = secure_private_file(&path);
        let _ = writeln!(
            file,
            "{} [{}] {}",
            timestamp_seconds(),
            level,
            sanitize(message)
        );
    }

    fn log_path(&self) -> PathBuf {
        self.router
            .registry()
            .home()
            .join("logs")
            .join("mcp")
            .join(format!("{}.log", self.agent_id))
    }

    fn request_label(request: &Value) -> String {
        let method = request["method"].as_str().unwrap_or("missing_method");
        if method == "tools/call" {
            if let Some(name) = request["params"]["name"].as_str() {
                return format!("{method}:{name}");
            }
        }
        method.to_owned()
    }

    fn is_reporting_request(label: &str) -> bool {
        matches!(
            label,
            "tools/call:update_self_summary" | "tools/call:attach_self_reference"
        )
    }
}

pub fn identity_hint() -> &'static str {
    "如果可用，可调用 get_self_agent 确认当前 VoxFlow 任务助手身份；如果能判断当前任务或阶段，可调用 update_self_summary 上报简短语义状态。之后仅在工作阶段明显变化时低频更新。不要修改用户任务，不要自动批准权限，不要向其他 Agent 派发任务。"
}

fn tool_definitions() -> Vec<Value> {
    vec![
        json!({
            "name":"get_self_agent",
            "description":"读取当前 VoxFlow 任务助手会话身份。无需周期性调用。",
            "inputSchema":{"type":"object","properties":{},"additionalProperties":false}
        }),
        json!({
            "name":"update_self_summary",
            "description":"低频更新当前任务助手正在处理的工作摘要；仅在任务或阶段明显变化时调用。",
            "inputSchema":{"type":"object","required":["label","summary","topics","phase"],"properties":{
                "label":{"type":"string","maxLength":20},
                "summary":{"type":"string","maxLength":80},
                "topics":{"type":"array","maxItems":8,"items":{"type":"string","maxLength":20}},
                "phase":{"type":"string","enum":["planning","editing","testing","waiting","done","blocked"]},
                "ttl_seconds":{"type":"integer","minimum":1,"default":3600}
            },"additionalProperties":false}
        }),
        json!({
            "name":"attach_self_reference",
            "description":"为当前任务助手附加 provider 会话、transcript 或日志引用，不上传日志正文。",
            "inputSchema":{"type":"object","required":["provider","kind","value"],"properties":{
                "provider":{"type":"string"},
                "kind":{"type":"string","enum":["session_id","transcript_path","log_path","conversation_id","other"]},
                "value":{"type":"string"},
                "description":{"type":"string"}
            },"additionalProperties":false}
        }),
        json!({
            "name":"get_self_dispatch_log",
            "description":"读取用户投喂给当前任务助手的最近指令记录，不读取 Agent 输出。",
            "inputSchema":{"type":"object","properties":{"limit":{"type":"integer","minimum":1,"maximum":100,"default":20}},"additionalProperties":false}
        }),
    ]
}

fn required<'a>(value: &'a Value, key: &str) -> anyhow::Result<&'a str> {
    value[key]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("missing string argument: {key}"))
}

fn string_array(value: &Value, key: &str) -> anyhow::Result<Vec<String>> {
    value[key]
        .as_array()
        .ok_or_else(|| anyhow::anyhow!("missing array argument: {key}"))?
        .iter()
        .map(|item| {
            item.as_str()
                .map(str::to_owned)
                .ok_or_else(|| anyhow::anyhow!("{key} must contain strings"))
        })
        .collect()
}

fn timestamp_seconds() -> String {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| format!("{:.3}", duration.as_secs_f64()))
        .unwrap_or_else(|_| "0.000".to_owned())
}

fn sanitize(value: &str) -> String {
    value.replace(['\r', '\n'], " ")
}
