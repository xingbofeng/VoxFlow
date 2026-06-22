#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VoxflowCommand {
    Run(Vec<String>),
    List {
        all: bool,
    },
    Send {
        target: String,
        message: String,
        submit: bool,
    },
    Resolve {
        target: String,
    },
    Serve,
    Mcp,
    HookSessionStart {
        provider: String,
    },
    Help,
}

pub fn normalize_invocation_args<I, S>(args: I) -> Result<Vec<String>, String>
where
    I: IntoIterator<Item = S>,
    S: Into<String>,
{
    let mut values: Vec<String> = args.into_iter().map(Into::into).collect();
    let invoked_as_vox = values
        .first()
        .and_then(|value| std::path::Path::new(value).file_name())
        .and_then(|value| value.to_str())
        == Some("vox");
    if !invoked_as_vox {
        return Ok(values);
    }
    if values.get(1).map(String::as_str) != Some("flow") {
        return Err("usage: vox flow <agent>".into());
    }
    values.remove(1);
    if let Some(provider) = values.get_mut(1) {
        match provider.as_str() {
            "--claude" => *provider = "claude".into(),
            "--codebuddy" => *provider = "codebuddy".into(),
            _ => {}
        }
    }
    Ok(values)
}

pub fn parse_from<I, S>(args: I) -> Result<VoxflowCommand, String>
where
    I: IntoIterator<Item = S>,
    S: Into<String>,
{
    let mut values: Vec<String> = args.into_iter().map(Into::into).collect();
    if !values.is_empty() {
        values.remove(0);
    }
    let Some(first) = values.first().map(String::as_str) else {
        return Ok(VoxflowCommand::Help);
    };

    match first {
        "run" => {
            let command = values[1..]
                .iter()
                .skip_while(|value| value.as_str() == "--")
                .cloned()
                .collect();
            run_command(command)
        }
        "list" => Ok(VoxflowCommand::List {
            all: values[1..].iter().any(|value| value == "--all"),
        }),
        "send" => {
            let submit = !values[1..].iter().any(|value| value == "--no-enter");
            let positional: Vec<_> = values[1..]
                .iter()
                .filter(|value| value.as_str() != "--no-enter")
                .cloned()
                .collect();
            let target = positional
                .first()
                .cloned()
                .ok_or("send requires a target")?;
            let message = positional[1..].join(" ");
            if message.is_empty() {
                return Err("send requires a message".into());
            }
            Ok(VoxflowCommand::Send {
                target,
                message,
                submit,
            })
        }
        "resolve" => Ok(VoxflowCommand::Resolve {
            target: values.get(1).cloned().ok_or("resolve requires a target")?,
        }),
        "serve" => Ok(VoxflowCommand::Serve),
        "mcp" => Ok(VoxflowCommand::Mcp),
        "hook-session-start" => Ok(VoxflowCommand::HookSessionStart {
            provider: values
                .get(1)
                .cloned()
                .ok_or("hook-session-start requires a provider")?,
        }),
        "help" | "--help" | "-h" => Ok(VoxflowCommand::Help),
        _ => run_command(values),
    }
}

fn run_command(command: Vec<String>) -> Result<VoxflowCommand, String> {
    if command.is_empty() {
        Err("missing agent command".into())
    } else {
        Ok(VoxflowCommand::Run(command))
    }
}
