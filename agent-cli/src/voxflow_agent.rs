use std::io::BufReader;

fn main() {
    if let Err(error) = run() {
        eprintln!("voxflow-agent: {error:#}");
        std::process::exit(1);
    }
}

fn run() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    match args.next().as_deref() {
        Some("--version") => {
            println!("voxflow-agent {}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        Some("--help") | Some("-h") => {
            println!("voxflow-agent reads one builtin-agent JSONL run request from stdin");
            Ok(())
        }
        Some(argument) => anyhow::bail!("unsupported argument: {argument}"),
        None => {
            let stdin = std::io::stdin();
            let stdout = std::io::stdout();
            let exit_code = voxflow::builtin_agent::run_builtin_agent_stdio(
                BufReader::new(stdin.lock()),
                stdout.lock(),
            )?;
            std::process::exit(exit_code);
        }
    }
}
