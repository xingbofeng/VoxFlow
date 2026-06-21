use anyhow::{bail, Result};
use voxflow::cli::{normalize_invocation_args, parse_from, VoxflowCommand};
use voxflow::ipc::RouterServer;
use voxflow::mcp::McpServer;
use voxflow::paths::router_home;
use voxflow::router::Router;
use voxflow::session::{SessionRegistry, SystemProcessInspector};

fn main() {
    if let Err(error) = run() {
        eprintln!("voxflow: {error:#}");
        std::process::exit(1);
    }
}

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
            "voxflow <agent-command> | run -- <command> | list [--all] | send [--no-enter] <target> <message> | resolve <target> | serve | mcp"
        ),
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
    }
    Ok(())
}
