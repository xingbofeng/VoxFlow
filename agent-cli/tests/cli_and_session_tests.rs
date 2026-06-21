use std::io::{Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::sync::Arc;
use std::thread;

use tempfile::tempdir;
use voxflow::cli::{normalize_invocation_args, parse_from, VoxflowCommand};
use voxflow::input::InputChannel;
use voxflow::pty::{initial_terminal_size, PtyProcess};
use voxflow::session::{ProcessInspector, SessionCard, SessionRegistry, SessionStatus};

#[test]
fn cli_keeps_agent_arguments_verbatim_and_supports_documented_forms() {
    assert_eq!(
        parse_from(["voxflow", "codex", "--profile", "work"]).unwrap(),
        VoxflowCommand::Run(vec!["codex".into(), "--profile".into(), "work".into()])
    );
    assert_eq!(
        parse_from(["voxflow", "run", "--", "custom-agent", "send"]).unwrap(),
        VoxflowCommand::Run(vec!["custom-agent".into(), "send".into()])
    );
    assert_eq!(
        parse_from(["voxflow", "list"]).unwrap(),
        VoxflowCommand::List { all: false }
    );
    assert_eq!(
        parse_from(["voxflow", "send", "front", "fix", "button"]).unwrap(),
        VoxflowCommand::Send {
            target: "front".into(),
            message: "fix button".into(),
            submit: true
        }
    );
}

#[test]
fn vox_symlink_invocation_forwards_documented_flow_commands() {
    assert_eq!(
        normalize_invocation_args(["/usr/local/bin/vox", "flow", "codex"]).unwrap(),
        ["/usr/local/bin/vox", "codex"]
    );
    assert_eq!(
        normalize_invocation_args(["vox", "flow", "--claude", "--resume"]).unwrap(),
        ["vox", "claude", "--resume"]
    );
    assert_eq!(
        normalize_invocation_args(["vox", "flow", "--codebuddy"]).unwrap(),
        ["vox", "codebuddy"]
    );
}

#[test]
fn terminal_size_uses_environment_for_non_tty_contexts() {
    std::env::set_var("COLUMNS", "132");
    std::env::set_var("LINES", "43");
    assert_eq!(initial_terminal_size(), (132, 43));
    std::env::remove_var("COLUMNS");
    std::env::remove_var("LINES");
}

#[test]
fn portable_pty_preserves_output_and_accepts_external_input_with_enter() {
    let temp = tempdir().unwrap();
    let channel = InputChannel::create(temp.path().join("agent.stdin")).unwrap();
    let channel_path = channel.path().to_owned();
    let mut process = PtyProcess::spawn(
        &[
            "/bin/sh".into(),
            "-c".into(),
            "IFS= read -r line; printf 'SEEN:<%s>\\n' \"$line\"".into(),
        ],
        temp.path(),
    )
    .unwrap();
    channel.start_forwarding(process.writer()).unwrap();

    InputChannel::send(channel.path(), "按钮改成白色", true).unwrap();
    let output = process.read_until_exit().unwrap();
    drop(channel);

    assert!(String::from_utf8_lossy(&output).contains("SEEN:<按钮改成白色>"));
    assert!(
        !channel_path.exists(),
        "FIFO must be removed with its owner"
    );
}

#[test]
fn submitted_message_forwards_enter_byte_to_raw_terminal_program() {
    let temp = tempdir().unwrap();
    let output = temp.path().join("raw-input.bin");
    let channel = InputChannel::create(temp.path().join("raw.stdin")).unwrap();
    let mut process = PtyProcess::spawn(
        &[
            "/bin/sh".into(),
            "-c".into(),
            format!(
                "stty raw -echo; dd bs=1 count=7 of='{}' 2>/dev/null",
                output.display()
            ),
        ],
        temp.path(),
    )
    .unwrap();
    channel.start_forwarding(process.writer()).unwrap();

    InputChannel::send(channel.path(), "submit", true).unwrap();
    let _ = process.read_until_exit().unwrap();
    drop(channel);

    assert_eq!(std::fs::read(output).unwrap(), b"submit\r");
}

struct AlwaysAlive;
impl ProcessInspector for AlwaysAlive {
    fn is_alive(&self, _: u32) -> bool {
        true
    }
}

struct NeverAlive;
impl ProcessInspector for NeverAlive {
    fn is_alive(&self, _: u32) -> bool {
        false
    }
}

#[test]
fn locked_jsonl_registry_keeps_concurrent_sessions_and_marks_stale() {
    let temp = tempdir().unwrap();
    let registry = Arc::new(SessionRegistry::new(temp.path()));
    let threads: Vec<_> = (0..8)
        .map(|index| {
            let registry = registry.clone();
            thread::spawn(move || {
                let mut card = SessionCard::new(
                    vec![format!("agent-{index}")],
                    format!("/tmp/{index}.stdin").into(),
                    1000 + index,
                    2000 + index,
                );
                card.agent_id = format!("agent-{index}");
                registry.upsert(&card).unwrap();
            })
        })
        .collect();
    for handle in threads {
        handle.join().unwrap();
    }

    let active = registry.list(true, &AlwaysAlive).unwrap();
    assert_eq!(active.len(), 8);
    assert_eq!(
        std::fs::metadata(registry.path())
            .unwrap()
            .permissions()
            .mode()
            & 0o777,
        0o600
    );
    assert!(active
        .iter()
        .all(|card| card.status == SessionStatus::Active));

    let stale = registry.list(true, &NeverAlive).unwrap();
    assert!(stale.iter().all(|card| card.status == SessionStatus::Stale));
}

#[test]
fn fifo_stays_available_across_multiple_senders() {
    let temp = tempdir().unwrap();
    let channel = InputChannel::create(temp.path().join("repeat.stdin")).unwrap();
    let (mut reader, writer) = std::os::unix::net::UnixStream::pair().unwrap();
    channel
        .start_forwarding(Arc::new(std::sync::Mutex::new(
            Box::new(writer.try_clone().unwrap()) as Box<dyn Write + Send>,
        )))
        .unwrap();

    InputChannel::send(channel.path(), "one", true).unwrap();
    InputChannel::send(channel.path(), "two", true).unwrap();
    let mut bytes = [0_u8; 8];
    reader.read_exact(&mut bytes).unwrap();

    assert_eq!(&bytes, b"one\rtwo\r");
}
