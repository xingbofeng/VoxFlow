use std::fs;

use tempfile::tempdir;
use voxflow::mcp::identity_hint;
use voxflow::mcp_config::{prepare_agent_command, McpIdentityEnv, McpPreference};

fn identity() -> McpIdentityEnv {
    McpIdentityEnv {
        agent_id: "agent-1".into(),
        router_home: "/tmp/router home".into(),
        identity_hint: identity_hint().into(),
    }
}

#[test]
fn codex_receives_session_bound_mcp_overrides_without_changing_user_arguments() {
    let temp = tempdir().unwrap();
    let prepared = prepare_agent_command(
        &["codex".into(), "--profile".into(), "work".into()],
        std::path::Path::new("/Applications/VoxFlow.app/Contents/Helpers/voxflow"),
        temp.path(),
        McpPreference::Enabled,
        &identity(),
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
    assert!(prepared
        .command
        .iter()
        .any(|value| { value == "mcp_servers.voxflow.env.VOXFLOW_AGENT_ID=\"agent-1\"" }));
    assert!(prepared.command.iter().any(|value| {
        value == "mcp_servers.voxflow.env.VOXFLOW_AGENT_ROUTER_HOME=\"/tmp/router home\""
    }));
    assert!(prepared.temporary_files.is_empty());
}

#[test]
fn claude_and_codebuddy_receive_standard_session_mcp_json_and_session_start_hook() {
    for cli in ["claude", "codebuddy"] {
        let temp = tempdir().unwrap();
        let prepared = prepare_agent_command(
            &[cli.into(), "--verbose".into()],
            std::path::Path::new("/tmp/voxflow"),
            temp.path(),
            McpPreference::Enabled,
            &identity(),
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
        assert_eq!(
            config["mcpServers"]["voxflow"]["env"]["VOXFLOW_AGENT_ID"],
            "agent-1"
        );
        assert_eq!(
            config["mcpServers"]["voxflow"]["env"]["VOXFLOW_AGENT_ROUTER_HOME"],
            "/tmp/router home"
        );
        let settings_index = prepared
            .command
            .iter()
            .position(|value| value == "--settings")
            .unwrap();
        let settings_path = std::path::Path::new(&prepared.command[settings_index + 1]);
        let settings: serde_json::Value =
            serde_json::from_slice(&fs::read(settings_path).unwrap()).unwrap();
        let hook = &settings["hooks"]["SessionStart"][0]["hooks"][0];
        assert_eq!(hook["type"], "command");
        assert!(hook["command"]
            .as_str()
            .unwrap()
            .contains(&format!("hook-session-start {cli}")));
        assert_eq!(prepared.command.last().unwrap(), "--verbose");
    }
}

#[test]
fn short_vox_helper_runs_mcp_through_flow_subcommand() {
    let temp = tempdir().unwrap();
    let prepared = prepare_agent_command(
        &["codex".into()],
        std::path::Path::new("/Users/counter/.local/bin/vox"),
        temp.path(),
        McpPreference::Enabled,
        &identity(),
    )
    .unwrap();

    assert!(prepared
        .command
        .iter()
        .any(|value| { value == "mcp_servers.voxflow.args=[\"flow\",\"mcp\"]" }));

    let prepared = prepare_agent_command(
        &["claude".into()],
        std::path::Path::new("/Users/counter/.local/bin/vox"),
        temp.path(),
        McpPreference::Enabled,
        &identity(),
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
    assert_eq!(
        config["mcpServers"]["voxflow"]["command"],
        "/Users/counter/.local/bin/vox"
    );
    assert_eq!(
        config["mcpServers"]["voxflow"]["args"],
        serde_json::json!(["flow", "mcp"])
    );
    let settings_index = prepared
        .command
        .iter()
        .position(|value| value == "--settings")
        .unwrap();
    let settings_path = std::path::Path::new(&prepared.command[settings_index + 1]);
    let settings: serde_json::Value =
        serde_json::from_slice(&fs::read(settings_path).unwrap()).unwrap();
    assert!(settings["hooks"]["SessionStart"][0]["hooks"][0]["command"]
        .as_str()
        .unwrap()
        .contains("flow hook-session-start claude"));
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
        &identity(),
    )
    .unwrap();
    let disabled = prepare_agent_command(
        &["claude".into()],
        std::path::Path::new("/tmp/voxflow"),
        temp.path(),
        McpPreference::Disabled,
        &identity(),
    )
    .unwrap();
    assert_eq!(unknown.command, original);
    assert_eq!(disabled.command, vec!["claude"]);
}
