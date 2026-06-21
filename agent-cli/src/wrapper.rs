use crate::input::InputChannel;
use crate::mcp_config::{prepare_agent_command, McpPreference};
use crate::pty::{terminal_size_from_tty, PtyProcess};
use crate::session::{SessionCard, SessionRegistry};
use anyhow::{Context, Result};
use std::io::{IsTerminal, Read, Write};
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::time::Duration;

static PENDING_SIGNAL: AtomicI32 = AtomicI32::new(0);
static RESIZE_PENDING: AtomicBool = AtomicBool::new(false);

pub fn run(command: Vec<String>, registry: &SessionRegistry) -> Result<i32> {
    let cwd = std::env::current_dir()?;
    let agent_id = uuid::Uuid::new_v4().to_string();
    let router_home = registry.home().display().to_string();
    let helper_path = std::env::current_exe()?;
    let prepared = prepare_agent_command(
        &command,
        &helper_path,
        &registry.home().join("mcp"),
        McpPreference::load(registry.home()),
    )?;
    let mut process = PtyProcess::spawn_with_env(
        &prepared.command,
        &cwd,
        &[
            ("VOXFLOW_AGENT_ID", &agent_id),
            ("VOXFLOW_AGENT_ROUTER_HOME", &router_home),
            ("VOXFLOW_IDENTITY_HINT", crate::mcp::identity_hint()),
        ],
    )?;
    let child_pid = process
        .child_pid()
        .context("PTY child did not expose a process ID")?;
    let channel = InputChannel::create(registry.input_dir().join(format!("{agent_id}.stdin")))?;
    let mut card = SessionCard::new(
        command,
        channel.path().to_owned(),
        std::process::id(),
        child_pid,
    );
    card.agent_id = agent_id;
    registry.upsert(&card)?;
    eprintln!(
        "[VoxFlow] agent_id={} command={} cwd={} call-name={}",
        card.agent_id,
        card.cli,
        card.cwd,
        card.display_name()
    );
    eprint!("\x1b]0;VoxFlow · {}\x07", card.display_name());

    install_signal_handlers();
    let writer = process.writer();
    let _fifo_thread = channel.start_forwarding(writer.clone())?;
    let _terminal = RawTerminalGuard::enable();
    let _stdin_thread = if std::io::stdin().is_terminal() {
        Some(std::thread::spawn(move || {
            let mut stdin = std::io::stdin();
            let mut bytes = [0_u8; 8192];
            while let Ok(length) = stdin.read(&mut bytes) {
                if length == 0 {
                    break;
                }
                let Ok(mut target) = writer.lock() else {
                    break;
                };
                if target
                    .write_all(&bytes[..length])
                    .and_then(|_| target.flush())
                    .is_err()
                {
                    break;
                }
            }
        }))
    } else {
        None
    };

    let mut last_terminal_size = terminal_size_from_tty();
    let status = loop {
        if let Some(bytes) = process.try_output(Duration::from_millis(20)) {
            std::io::stdout().write_all(&bytes)?;
            std::io::stdout().flush()?;
        }
        if let Some(status) = process.try_wait()? {
            break status.exit_code() as i32;
        }
        let signal = PENDING_SIGNAL.swap(0, Ordering::SeqCst);
        if signal != 0 {
            process.forward_signal(signal);
        }
        let terminal_size = terminal_size_from_tty();
        if RESIZE_PENDING.swap(false, Ordering::SeqCst) || terminal_size != last_terminal_size {
            if let Some((cols, rows)) = terminal_size {
                let _ = process.resize(cols, rows);
            }
            last_terminal_size = terminal_size;
        }
    };
    process.reap_process_group();
    registry.update_exit(&card.agent_id, status)?;
    drop(channel);
    Ok(status)
}

extern "C" fn handle_termination_signal(signal: i32) {
    PENDING_SIGNAL.store(signal, Ordering::SeqCst);
}

extern "C" fn handle_resize_signal(_: i32) {
    RESIZE_PENDING.store(true, Ordering::SeqCst);
}

fn install_signal_handlers() {
    #[cfg(unix)]
    unsafe {
        let termination = handle_termination_signal as *const () as libc::sighandler_t;
        let resize = handle_resize_signal as *const () as libc::sighandler_t;
        libc::signal(libc::SIGTERM, termination);
        libc::signal(libc::SIGHUP, termination);
        libc::signal(libc::SIGINT, termination);
        libc::signal(libc::SIGWINCH, resize);
    }
}

struct RawTerminalGuard {
    enabled: bool,
}

impl RawTerminalGuard {
    fn enable() -> Self {
        let enabled =
            std::io::stdin().is_terminal() && crossterm::terminal::enable_raw_mode().is_ok();
        Self { enabled }
    }
}

impl Drop for RawTerminalGuard {
    fn drop(&mut self) {
        if self.enabled {
            let _ = crossterm::terminal::disable_raw_mode();
        }
    }
}
