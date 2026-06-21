use crate::router::Router;
use crate::session::{ensure_private_directory, secure_private_file, SystemProcessInspector};
use anyhow::Result;
use fs2::FileExt;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::thread;
use std::time::Duration;

const MAX_REQUEST_BYTES: u64 = 1_048_576;
const REQUEST_TIMEOUT: Duration = Duration::from_millis(800);

#[derive(Debug, Deserialize)]
struct Request {
    id: Value,
    method: String,
    #[serde(default)]
    params: Value,
}

#[derive(Debug, Serialize)]
struct Response {
    id: Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<Value>,
}

pub struct RouterServer {
    router: Router,
    socket_path: PathBuf,
}

impl RouterServer {
    pub fn new(router: Router, socket_path: impl AsRef<Path>) -> Self {
        Self {
            router,
            socket_path: socket_path.as_ref().to_owned(),
        }
    }

    pub fn serve(&self) -> Result<()> {
        self.serve_inner(None)
    }

    pub fn serve_n(&self, count: usize) -> Result<()> {
        self.serve_inner(Some(count))
    }

    fn serve_inner(&self, limit: Option<usize>) -> Result<()> {
        if let Some(parent) = self.socket_path.parent() {
            ensure_private_directory(parent)?;
        }
        let lock_path = self.socket_path.with_extension("lock");
        let server_lock = std::fs::OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .mode(0o600)
            .open(lock_path)?;
        secure_private_file(&self.socket_path.with_extension("lock"))?;
        server_lock
            .try_lock_exclusive()
            .map_err(|_| anyhow::anyhow!("Agent Router is already running"))?;
        let _ = std::fs::remove_file(&self.socket_path);
        let listener = UnixListener::bind(&self.socket_path)?;
        secure_private_file(&self.socket_path)?;
        let mut handles = Vec::new();
        for (index, stream) in listener.incoming().enumerate() {
            let router = self.router.clone();
            handles.push(thread::spawn(move || {
                let server = RouterServer {
                    router,
                    socket_path: PathBuf::new(),
                };
                let _ = server.handle(stream?);
                Ok::<(), anyhow::Error>(())
            }));
            if limit.is_some_and(|limit| index + 1 >= limit) {
                break;
            }
        }
        for handle in handles {
            let _ = handle.join();
        }
        let _ = std::fs::remove_file(&self.socket_path);
        let _ = FileExt::unlock(&server_lock);
        Ok(())
    }

    fn handle(&self, mut stream: UnixStream) -> Result<()> {
        stream.set_read_timeout(Some(REQUEST_TIMEOUT))?;
        stream.set_write_timeout(Some(REQUEST_TIMEOUT))?;

        let mut line = Vec::new();
        let mut reader = BufReader::new(stream.try_clone()?);
        let bytes_read = reader
            .by_ref()
            .take(MAX_REQUEST_BYTES + 1)
            .read_until(b'\n', &mut line)?;
        if bytes_read as u64 > MAX_REQUEST_BYTES {
            return self.write_error(
                &mut stream,
                Value::Null,
                "request_too_large",
                "request too large",
            );
        }
        let request: Request = serde_json::from_slice(&line)?;
        let response = match self.dispatch(&request) {
            Ok(result) => Response {
                id: request.id,
                result: Some(result),
                error: None,
            },
            Err(error) => Response {
                id: request.id,
                result: None,
                error: Some(json!({"code": "router_error", "message": error.to_string()})),
            },
        };
        serde_json::to_writer(&mut stream, &response)?;
        stream.write_all(b"\n")?;
        stream.flush()?;
        Ok(())
    }

    fn write_error(
        &self,
        stream: &mut UnixStream,
        id: Value,
        code: &str,
        message: &str,
    ) -> Result<()> {
        serde_json::to_writer(
            &mut *stream,
            &Response {
                id,
                result: None,
                error: Some(json!({"code": code, "message": message})),
            },
        )?;
        stream.write_all(b"\n")?;
        stream.flush()?;
        Ok(())
    }

    fn dispatch(&self, request: &Request) -> Result<Value> {
        match request.method.as_str() {
            "list_agents" => {
                self.router
                    .prune_dispatch_logs(now() - 30.0 * 24.0 * 60.0 * 60.0)?;
                let include_inactive = request.params["include_inactive"]
                    .as_bool()
                    .unwrap_or(false);
                Ok(serde_json::to_value(
                    self.router
                        .registry()
                        .list(include_inactive, &SystemProcessInspector)?,
                )?)
            }
            "resolve_agent" => {
                let utterance = required_string(&request.params, "utterance")?;
                Ok(serde_json::to_value(
                    self.router
                        .resolve_utterance(utterance, &SystemProcessInspector)?,
                )?)
            }
            "learn_alias" => {
                self.router.learn_alias(
                    required_string(&request.params, "alias")?,
                    required_string(&request.params, "agent_id")?,
                    request.params["user_confirmed"].as_bool().unwrap_or(false),
                )?;
                Ok(json!({"saved": true}))
            }
            "list_aliases" => Ok(serde_json::to_value(self.router.list_aliases()?)?),
            "remove_alias" => Ok(json!({
                "removed": self.router.remove_alias(required_string(&request.params, "alias")?)?
            })),
            "list_dispatch_log" => Ok(serde_json::to_value(self.router.dispatch_logs(
                request.params["agent_id"].as_str(),
                request.params["limit"].as_u64().unwrap_or(30).clamp(1, 100) as usize,
            )?)?),
            "clear_dispatch_log" => {
                self.router.clear_dispatch_logs()?;
                Ok(json!({"cleared": true}))
            }
            "clean_stale" => Ok(json!({
                "removed": self.router.registry().remove_stale(&SystemProcessInspector)?
            })),
            "send_message" => {
                let submit = request.params["submit"].as_bool().unwrap_or(true);
                self.router.send_message(
                    required_string(&request.params, "agent_id")?,
                    required_string(&request.params, "message")?,
                    submit,
                )?;
                Ok(json!({"submitted": submit}))
            }
            "append_dispatch_log" => {
                self.router.append_dispatch(
                    required_string(&request.params, "agent_id")?,
                    required_string(&request.params, "message")?,
                    request.params["submitted"].as_bool().unwrap_or(false),
                    None,
                    request.params["timestamp"].as_f64().unwrap_or_else(now),
                )?;
                Ok(json!({"saved": true}))
            }
            other => anyhow::bail!("unknown method: {other}"),
        }
    }
}

fn required_string<'a>(value: &'a Value, key: &str) -> Result<&'a str> {
    value[key]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("missing string parameter: {key}"))
}

fn now() -> f64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
}
