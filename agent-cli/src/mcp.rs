use crate::router::Router;
use crate::session::{ProviderReference, SystemProcessInspector};
use serde_json::{json, Value};
use std::io::{BufRead, Write};

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
        let id = request.get("id").cloned().unwrap_or(Value::Null);
        let result = match request["method"].as_str() {
            Some("initialize") => Ok(json!({
                "protocolVersion": "2025-03-26",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "voxflow-agent-identity", "version": env!("CARGO_PKG_VERSION")},
                "instructions": identity_hint()
            })),
            Some("notifications/initialized") => Ok(Value::Null),
            Some("tools/list") => Ok(json!({"tools": tool_definitions()})),
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
        match result {
            Ok(result) => json!({"jsonrpc":"2.0", "id":id, "result":result}),
            Err(error) => json!({
                "jsonrpc":"2.0", "id":id,
                "error":{"code":-32601, "message":error.to_string()}
            }),
        }
    }

    pub fn run_stdio(&self) -> anyhow::Result<()> {
        let stdin = std::io::stdin();
        let mut stdout = std::io::stdout();
        for line in stdin.lock().lines() {
            let line = line?;
            if line.trim().is_empty() {
                continue;
            }
            let request: Value = serde_json::from_str(&line)?;
            if request.get("id").is_none() {
                continue;
            }
            serde_json::to_writer(&mut stdout, &self.handle_value(request))?;
            stdout.write_all(b"\n")?;
            stdout.flush()?;
        }
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
}

pub fn identity_hint() -> &'static str {
    "仅在身份或工作阶段明显变化时低频调用 update_self_summary。不要修改用户任务，不要自动批准权限，不要向其他 Agent 派发任务。"
}

fn tool_definitions() -> Vec<Value> {
    vec![
        json!({
            "name":"get_self_agent",
            "description":"读取当前 VoxFlow 队员会话身份。无需周期性调用。",
            "inputSchema":{"type":"object","properties":{},"additionalProperties":false}
        }),
        json!({
            "name":"update_self_summary",
            "description":"低频更新当前队员正在处理的工作摘要；仅在任务或阶段明显变化时调用。",
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
            "description":"为当前队员附加 provider 会话、transcript 或日志引用，不上传日志正文。",
            "inputSchema":{"type":"object","required":["provider","kind","value"],"properties":{
                "provider":{"type":"string"},
                "kind":{"type":"string","enum":["session_id","transcript_path","log_path","conversation_id","other"]},
                "value":{"type":"string"},
                "description":{"type":"string"}
            },"additionalProperties":false}
        }),
        json!({
            "name":"get_self_dispatch_log",
            "description":"读取用户投喂给当前队员的最近指令记录，不读取 Agent 输出。",
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
