use anyhow::Result;
use serde_json::json;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum McpPreference {
    Enabled,
    Disabled,
}

impl McpPreference {
    pub fn load(router_home: &Path) -> Self {
        let path = router_home.join("settings.json");
        let enabled = std::fs::read(path)
            .ok()
            .and_then(|data| serde_json::from_slice::<serde_json::Value>(&data).ok())
            .and_then(|value| value["mcp_enabled"].as_bool())
            .unwrap_or(true);
        if enabled {
            Self::Enabled
        } else {
            Self::Disabled
        }
    }
}

pub struct PreparedAgentCommand {
    pub command: Vec<String>,
    pub temporary_files: Vec<PathBuf>,
    pub mcp_injected: bool,
    pub mcp_config_path: Option<PathBuf>,
    pub mcp_command: Option<String>,
    pub mcp_args: Vec<String>,
}

pub struct McpIdentityEnv {
    pub agent_id: String,
    pub router_home: String,
    pub identity_hint: String,
}

impl Drop for PreparedAgentCommand {
    fn drop(&mut self) {
        for path in &self.temporary_files {
            let _ = std::fs::remove_file(path);
        }
    }
}

pub fn prepare_agent_command(
    command: &[String],
    helper_path: &Path,
    temporary_directory: &Path,
    preference: McpPreference,
    identity: &McpIdentityEnv,
) -> Result<PreparedAgentCommand> {
    if preference == McpPreference::Disabled || command.is_empty() {
        return Ok(PreparedAgentCommand {
            command: command.to_vec(),
            temporary_files: Vec::new(),
            mcp_injected: false,
            mcp_config_path: None,
            mcp_command: None,
            mcp_args: Vec::new(),
        });
    }
    let cli = Path::new(&command[0])
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("");
    let helper = helper_path.display().to_string();
    let mcp_args = mcp_server_args(helper_path);
    match cli {
        "codex" => {
            let quoted_helper = serde_json::to_string(&helper)?;
            let quoted_args = serde_json::to_string(&mcp_args)?;
            let quoted_agent_id = serde_json::to_string(&identity.agent_id)?;
            let quoted_router_home = serde_json::to_string(&identity.router_home)?;
            let quoted_identity_hint = serde_json::to_string(&identity.identity_hint)?;
            let mut prepared = vec![
                command[0].clone(),
                "-c".into(),
                format!("mcp_servers.voxflow.command={quoted_helper}"),
                "-c".into(),
                format!("mcp_servers.voxflow.args={quoted_args}"),
                "-c".into(),
                format!("mcp_servers.voxflow.env.VOXFLOW_AGENT_ID={quoted_agent_id}"),
                "-c".into(),
                format!("mcp_servers.voxflow.env.VOXFLOW_AGENT_ROUTER_HOME={quoted_router_home}"),
                "-c".into(),
                format!("mcp_servers.voxflow.env.VOXFLOW_IDENTITY_HINT={quoted_identity_hint}"),
            ];
            prepared.extend_from_slice(&command[1..]);
            Ok(PreparedAgentCommand {
                command: prepared,
                temporary_files: Vec::new(),
                mcp_injected: true,
                mcp_config_path: None,
                mcp_command: Some(helper.clone()),
                mcp_args,
            })
        }
        "claude" | "codebuddy" => {
            std::fs::create_dir_all(temporary_directory)?;
            let path = temporary_directory.join(format!("mcp-{}.json", uuid::Uuid::new_v4()));
            let settings_path =
                temporary_directory.join(format!("settings-{}.json", uuid::Uuid::new_v4()));
            let config = json!({
                "mcpServers": {
                    "voxflow": {
                        "type": "stdio",
                        "command": helper,
                        "args": mcp_args.clone(),
                        "env": mcp_env(identity)
                    }
                }
            });
            std::fs::write(&path, serde_json::to_vec_pretty(&config)?)?;
            let settings = json!({
                "hooks": {
                    "SessionStart": [{
                        "matcher": "startup|resume|clear|compact",
                        "hooks": [{
                            "type": "command",
                            "command": session_start_hook_command(helper_path, cli)
                        }]
                    }]
                }
            });
            std::fs::write(&settings_path, serde_json::to_vec_pretty(&settings)?)?;
            let mut prepared = vec![
                command[0].clone(),
                "--mcp-config".into(),
                path.display().to_string(),
                "--settings".into(),
                settings_path.display().to_string(),
            ];
            prepared.extend_from_slice(&command[1..]);
            Ok(PreparedAgentCommand {
                command: prepared,
                temporary_files: vec![path.clone(), settings_path.clone()],
                mcp_injected: true,
                mcp_config_path: Some(path),
                mcp_command: Some(helper),
                mcp_args,
            })
        }
        _ => Ok(PreparedAgentCommand {
            command: command.to_vec(),
            temporary_files: Vec::new(),
            mcp_injected: false,
            mcp_config_path: None,
            mcp_command: None,
            mcp_args: Vec::new(),
        }),
    }
}

fn mcp_server_args(helper_path: &Path) -> Vec<String> {
    let helper_name = helper_path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("");
    if helper_name == "vox" {
        vec!["flow".into(), "mcp".into()]
    } else {
        vec!["mcp".into()]
    }
}

fn session_start_hook_command(helper_path: &Path, provider: &str) -> String {
    let mut parts = vec![posix_quote(&helper_path.display().to_string())];
    let helper_name = helper_path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("");
    if helper_name == "vox" {
        parts.push("flow".into());
    }
    parts.push("hook-session-start".into());
    parts.push(provider.to_owned());
    parts.join(" ")
}

fn posix_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

fn mcp_env(identity: &McpIdentityEnv) -> serde_json::Value {
    json!({
        "VOXFLOW_AGENT_ID": identity.agent_id,
        "VOXFLOW_AGENT_ROUTER_HOME": identity.router_home,
        "VOXFLOW_IDENTITY_HINT": identity.identity_hint
    })
}
