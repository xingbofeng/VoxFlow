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
) -> Result<PreparedAgentCommand> {
    if preference == McpPreference::Disabled || command.is_empty() {
        return Ok(PreparedAgentCommand {
            command: command.to_vec(),
            temporary_files: Vec::new(),
        });
    }
    let cli = Path::new(&command[0])
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("");
    let helper = helper_path.display().to_string();
    match cli {
        "codex" => {
            let quoted_helper = serde_json::to_string(&helper)?;
            let mut prepared = vec![
                command[0].clone(),
                "-c".into(),
                format!("mcp_servers.voxflow.command={quoted_helper}"),
                "-c".into(),
                "mcp_servers.voxflow.args=[\"mcp\"]".into(),
            ];
            prepared.extend_from_slice(&command[1..]);
            Ok(PreparedAgentCommand {
                command: prepared,
                temporary_files: Vec::new(),
            })
        }
        "claude" | "codebuddy" => {
            std::fs::create_dir_all(temporary_directory)?;
            let path = temporary_directory.join(format!("mcp-{}.json", uuid::Uuid::new_v4()));
            let config = json!({
                "mcpServers": {
                    "voxflow": {
                        "type": "stdio",
                        "command": helper,
                        "args": ["mcp"]
                    }
                }
            });
            std::fs::write(&path, serde_json::to_vec_pretty(&config)?)?;
            let mut prepared = vec![
                command[0].clone(),
                "--mcp-config".into(),
                path.display().to_string(),
            ];
            prepared.extend_from_slice(&command[1..]);
            Ok(PreparedAgentCommand {
                command: prepared,
                temporary_files: vec![path],
            })
        }
        _ => Ok(PreparedAgentCommand {
            command: command.to_vec(),
            temporary_files: Vec::new(),
        }),
    }
}
