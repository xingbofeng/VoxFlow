use crate::input::SharedWriter;
use anyhow::{anyhow, Context, Result};
use portable_pty::{native_pty_system, CommandBuilder, MasterPty, PtySize};
use std::io::Read;
use std::path::Path;
use std::sync::{mpsc, Arc, Mutex};
use std::time::Duration;

pub struct PtyProcess {
    master: Box<dyn MasterPty + Send>,
    child: Box<dyn portable_pty::Child + Send + Sync>,
    writer: SharedWriter,
    output: mpsc::Receiver<Vec<u8>>,
    child_pid: Option<u32>,
    process_group_id: Option<i32>,
}

impl PtyProcess {
    pub fn spawn(command: &[String], cwd: &Path) -> Result<Self> {
        Self::spawn_with_env(command, cwd, &[])
    }

    pub fn spawn_with_env(
        command: &[String],
        cwd: &Path,
        environment: &[(&str, &str)],
    ) -> Result<Self> {
        let binary = command
            .first()
            .ok_or_else(|| anyhow!("missing agent command"))?;
        let (cols, rows) = initial_terminal_size();
        let pair = native_pty_system().openpty(PtySize {
            rows,
            cols,
            pixel_width: 0,
            pixel_height: 0,
        })?;
        let mut builder = CommandBuilder::new(binary);
        for argument in &command[1..] {
            builder.arg(argument);
        }
        builder.cwd(cwd);
        builder.env("VOXFLOW_WRAPPER_PID", std::process::id().to_string());
        for (key, value) in environment {
            builder.env(*key, *value);
        }
        let child = pair
            .slave
            .spawn_command(builder)
            .with_context(|| format!("start {binary}"))?;
        drop(pair.slave);

        let mut reader = pair.master.try_clone_reader()?;
        let writer = Arc::new(Mutex::new(pair.master.take_writer()?));
        let (sender, output) = mpsc::channel();
        std::thread::spawn(move || {
            let mut buffer = [0_u8; 8192];
            loop {
                match reader.read(&mut buffer) {
                    Ok(0) => break,
                    Ok(length) => {
                        if sender.send(buffer[..length].to_vec()).is_err() {
                            break;
                        }
                    }
                    Err(error) if error.kind() == std::io::ErrorKind::Interrupted => continue,
                    Err(_) => break,
                }
            }
        });
        let child_pid = child.process_id();
        #[cfg(unix)]
        let process_group_id = child_pid.and_then(|pid| {
            let group = unsafe { libc::getpgid(pid as i32) };
            (group > 0).then_some(group)
        });
        #[cfg(not(unix))]
        let process_group_id = None;
        Ok(Self {
            master: pair.master,
            child,
            writer,
            output,
            child_pid,
            process_group_id,
        })
    }

    pub fn writer(&self) -> SharedWriter {
        self.writer.clone()
    }

    pub fn child_pid(&self) -> Option<u32> {
        self.child_pid
    }

    pub fn resize(&self, cols: u16, rows: u16) -> Result<()> {
        self.master.resize(PtySize {
            rows: rows.max(1),
            cols: cols.max(1),
            pixel_width: 0,
            pixel_height: 0,
        })?;
        Ok(())
    }

    pub fn try_output(&self, timeout: Duration) -> Option<Vec<u8>> {
        self.output.recv_timeout(timeout).ok()
    }

    pub fn try_wait(&mut self) -> Result<Option<portable_pty::ExitStatus>> {
        Ok(self.child.try_wait()?)
    }

    pub fn read_until_exit(&mut self) -> Result<Vec<u8>> {
        let mut result = Vec::new();
        loop {
            if let Some(bytes) = self.try_output(Duration::from_millis(20)) {
                result.extend(bytes);
            }
            if self.try_wait()?.is_some() {
                while let Ok(bytes) = self.output.recv_timeout(Duration::from_millis(20)) {
                    result.extend(bytes);
                }
                return Ok(result);
            }
        }
    }

    pub fn reap_process_group(&self) {
        #[cfg(unix)]
        if let Some(group) = self.process_group_id {
            unsafe {
                libc::kill(-group, libc::SIGKILL);
            }
        }
    }

    pub fn forward_signal(&self, signal: i32) {
        #[cfg(unix)]
        if let Some(group) = self.process_group_id {
            unsafe {
                libc::kill(-group, signal);
            }
        }
    }
}

impl Drop for PtyProcess {
    fn drop(&mut self) {
        if self.child.try_wait().ok().flatten().is_none() {
            self.reap_process_group();
            let _ = self.child.kill();
            let _ = self.child.wait();
        }
    }
}

pub fn initial_terminal_size() -> (u16, u16) {
    if let (Ok(cols), Ok(rows)) = (std::env::var("COLUMNS"), std::env::var("LINES")) {
        if let (Ok(cols), Ok(rows)) = (cols.parse::<u16>(), rows.parse::<u16>()) {
            return (cols.max(20), rows.max(1));
        }
    }
    terminal_size_from_tty().unwrap_or((80, 24))
}

pub fn terminal_size_from_tty() -> Option<(u16, u16)> {
    use std::os::fd::AsRawFd;
    let mut size: libc::winsize = unsafe { std::mem::zeroed() };
    if unsafe { libc::ioctl(std::io::stdout().as_raw_fd(), libc::TIOCGWINSZ, &mut size) } == 0
        && size.ws_col > 0
        && size.ws_row > 0
    {
        Some((size.ws_col.max(20), size.ws_row))
    } else {
        None
    }
}
