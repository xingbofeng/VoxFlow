#[cfg(unix)]
use anyhow::{bail, Result};
#[cfg(unix)]
use std::io::Read;
#[cfg(unix)]
use voxflow::cli::{normalize_invocation_args, parse_from, VoxflowCommand};
#[cfg(unix)]
use voxflow::ipc::RouterServer;
#[cfg(unix)]
use voxflow::mcp::McpServer;
#[cfg(unix)]
use voxflow::paths::router_home;
#[cfg(unix)]
use voxflow::router::Router;
#[cfg(unix)]
use voxflow::session::{SessionRegistry, SystemProcessInspector};

#[cfg(unix)]
fn main() {
    if let Err(error) = run() {
        eprintln!("voxflow: {error:#}");
        std::process::exit(1);
    }
}

#[cfg(unix)]
fn run() -> Result<()> {
    let args = normalize_invocation_args(std::env::args()).map_err(anyhow::Error::msg)?;
    let command = parse_from(args).map_err(anyhow::Error::msg)?;
    let home = router_home();
    let registry = SessionRegistry::new(&home);
    match command {
        VoxflowCommand::Run(command) => {
            std::process::exit(voxflow::wrapper::run(command, &registry)?)
        }
        VoxflowCommand::List { all } => {
            for card in registry.list(all, &SystemProcessInspector)? {
                println!(
                    "{}\t{:?}\t{}\t{}\t{}",
                    card.agent_id,
                    card.status,
                    card.cli,
                    card.display_name(),
                    card.cwd
                );
            }
        }
        VoxflowCommand::Send {
            target,
            message,
            submit,
        } => {
            let matches: Vec<_> = registry.list(false, &SystemProcessInspector)?.into_iter().filter(|card| {
                card.agent_id == target || card.cli.eq_ignore_ascii_case(&target) || card.display_name().eq_ignore_ascii_case(&target)
            }).collect();
            let [card] = matches.as_slice() else {
                bail!(if matches.is_empty() {
                    "agent not found"
                } else {
                    "agent target is ambiguous"
                });
            };
            Router::new(&home).send_message(&card.agent_id, &message, submit)?;
        }
        VoxflowCommand::Help => println!(
            "voxflow <agent-command> | run -- <command> | list [--all] | send [--no-enter] <target> <message> | resolve <target> | serve | mcp | hook-session-start <provider> | builtin-agent"
        ),
        VoxflowCommand::BuiltinAgent { args } => {
            if args.iter().any(|arg| arg == "--help" || arg == "-h") {
                println!("voxflow builtin-agent stdio");
            } else if args.iter().any(|arg| arg == "--version") {
                println!("voxflow-builtin-agent {}", env!("CARGO_PKG_VERSION"));
            } else {
                let stdin = std::io::stdin();
                let stdout = std::io::stdout();
                let exit_code = voxflow::builtin_agent::run_builtin_agent_stdio(
                    stdin.lock(),
                    stdout.lock(),
                )?;
                std::process::exit(exit_code);
            }
        }
        VoxflowCommand::Resolve { target } => {
            let result = Router::new(&home).resolve_utterance(
                &format!("{target}，resolve"),
                &SystemProcessInspector,
            )?;
            println!("{}", serde_json::to_string_pretty(&result)?);
        }
        VoxflowCommand::Serve => {
            RouterServer::new(Router::new(&home), home.join("router.sock")).serve()?;
        }
        VoxflowCommand::Mcp => {
            let agent_id = std::env::var("VOXFLOW_AGENT_ID")
                .map_err(|_| anyhow::anyhow!("VOXFLOW_AGENT_ID is required for MCP identity"))?;
            McpServer::new(Router::new(&home), agent_id).run_stdio()?;
        }
        VoxflowCommand::HookSessionStart { provider } => {
            let agent_id = std::env::var("VOXFLOW_AGENT_ID").map_err(|_| {
                anyhow::anyhow!("VOXFLOW_AGENT_ID is required for session hook reporting")
            })?;
            let mut input = String::new();
            std::io::stdin().read_to_string(&mut input)?;
            let payload: serde_json::Value = serde_json::from_str(&input)?;
            Router::new(&home).record_provider_session_start(
                &agent_id,
                &provider,
                payload["session_id"]
                    .as_str()
                    .ok_or_else(|| anyhow::anyhow!("session_id is required"))?,
                payload["transcript_path"].as_str().map(str::to_owned),
                payload["source"].as_str(),
            )?;
        }
    }
    Ok(())
}

#[cfg(not(unix))]
fn main() {
    eprintln!("voxflow is available only on Unix; use voxflow-agent on Windows");
    std::process::exit(1);
}
