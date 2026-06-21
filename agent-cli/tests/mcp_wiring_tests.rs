use std::fs;

use tempfile::tempdir;
use voxflow::mcp_config::{prepare_agent_command, McpPreference};

#[test]
fn codex_receives_session_bound_mcp_overrides_without_changing_user_arguments() {
    let temp = tempdir().unwrap();
    let prepared = prepare_agent_command(
        &["codex".into(), "--profile".into(), "work".into()],
        std::path::Path::new("/Applications/VoxFlow.app/Contents/Helpers/voxflow"),
        temp.path(),
        McpPreference::Enabled,
    )
    .unwrap();

    assert_eq!(prepared.command[0], "codex");
    assert!(prepared
        .command
        .windows(2)
        .any(|pair| { pair[0] == "-c" && pair[1].contains("mcp_servers.voxflow.command") }));
    assert!(prepared
        .command
        .ends_with(&["--profile".into(), "work".into()]));
    assert!(prepared.temporary_files.is_empty());
}

#[test]
fn claude_and_codebuddy_receive_standard_session_mcp_json() {
    for cli in ["claude", "codebuddy"] {
        let temp = tempdir().unwrap();
        let prepared = prepare_agent_command(
            &[cli.into(), "--verbose".into()],
            std::path::Path::new("/tmp/voxflow"),
            temp.path(),
            McpPreference::Enabled,
        )
        .unwrap();
        let config_index = prepared
            .command
            .iter()
            .position(|value| value == "--mcp-config")
            .unwrap();
        let config_path = std::path::Path::new(&prepared.command[config_index + 1]);
        let config: serde_json::Value =
            serde_json::from_slice(&fs::read(config_path).unwrap()).unwrap();
        assert_eq!(config["mcpServers"]["voxflow"]["command"], "/tmp/voxflow");
        assert_eq!(config["mcpServers"]["voxflow"]["args"][0], "mcp");
        assert_eq!(prepared.command.last().unwrap(), "--verbose");
    }
}

#[test]
fn disabled_or_unknown_agents_are_not_modified() {
    let temp = tempdir().unwrap();
    let original = vec!["custom-agent".into(), "--flag".into()];
    let unknown = prepare_agent_command(
        &original,
        std::path::Path::new("/tmp/voxflow"),
        temp.path(),
        McpPreference::Enabled,
    )
    .unwrap();
    let disabled = prepare_agent_command(
        &["claude".into()],
        std::path::Path::new("/tmp/voxflow"),
        temp.path(),
        McpPreference::Disabled,
    )
    .unwrap();
    assert_eq!(unknown.command, original);
    assert_eq!(disabled.command, vec!["claude"]);
}
