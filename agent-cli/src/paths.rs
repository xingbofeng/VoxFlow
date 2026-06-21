use std::path::PathBuf;

pub fn router_home() -> PathBuf {
    if let Some(path) = std::env::var_os("VOXFLOW_AGENT_ROUTER_HOME") {
        return PathBuf::from(path);
    }
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("Library/Application Support/VoxFlow/AgentRouter")
}
