use anyhow::{Context, Result};
use fs2::FileExt;
use serde::{Deserialize, Serialize};
use std::fs::{self, OpenOptions};
use std::io::{BufRead, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SessionStatus {
    Active,
    Exited,
    Stale,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SelfSummary {
    pub label: String,
    pub summary: String,
    pub topics: Vec<String>,
    pub phase: String,
    pub expires_at: f64,
}

impl SelfSummary {
    pub fn is_current(&self) -> bool {
        self.expires_at > now()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProviderReference {
    pub provider: String,
    pub kind: String,
    pub value: String,
    pub description: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ObservedTitle {
    pub title: String,
    pub source: String,
    pub updated_at: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SessionCard {
    pub schema_version: u32,
    pub agent_id: String,
    pub wrapper_pid: u32,
    pub child_pid: u32,
    pub cli: String,
    pub command: Vec<String>,
    pub cwd: String,
    pub repo_root: Option<String>,
    pub repo_name: Option<String>,
    pub branch: Option<String>,
    pub terminal: Option<String>,
    pub tty: Option<String>,
    pub input_channel: PathBuf,
    pub status: SessionStatus,
    pub exit_code: Option<i32>,
    #[serde(default)]
    pub self_summary: Option<SelfSummary>,
    #[serde(default)]
    pub provider_session_refs: Vec<ProviderReference>,
    #[serde(default)]
    pub observed_title: Option<ObservedTitle>,
    #[serde(default)]
    pub last_dispatched_at: Option<f64>,
    #[serde(default)]
    pub mcp_injected: bool,
    #[serde(default)]
    pub mcp_seen_at: Option<f64>,
    #[serde(default)]
    pub mcp_reported_at: Option<f64>,
    #[serde(default)]
    pub mcp_config_path: Option<PathBuf>,
    #[serde(default)]
    pub mcp_command: Option<String>,
    #[serde(default)]
    pub mcp_args: Vec<String>,
    #[serde(default)]
    pub mcp_log_path: Option<PathBuf>,
    #[serde(default)]
    pub mcp_last_request: Option<String>,
    #[serde(default)]
    pub mcp_last_error: Option<String>,
    pub started_at: f64,
    pub updated_at: f64,
}

impl SessionCard {
    pub fn new(
        command: Vec<String>,
        input_channel: PathBuf,
        wrapper_pid: u32,
        child_pid: u32,
    ) -> Self {
        let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        let repo_root = git(&cwd, &["rev-parse", "--show-toplevel"]);
        let now = now();
        let cli = command
            .first()
            .and_then(|value| Path::new(value).file_name())
            .and_then(|value| value.to_str())
            .unwrap_or("unknown")
            .to_owned();
        Self {
            schema_version: 1,
            agent_id: uuid::Uuid::new_v4().to_string(),
            wrapper_pid,
            child_pid,
            cli,
            command,
            cwd: cwd.display().to_string(),
            repo_name: repo_root
                .as_ref()
                .and_then(|root| Path::new(root).file_name())
                .and_then(|name| name.to_str())
                .map(str::to_owned),
            repo_root,
            branch: git(&cwd, &["branch", "--show-current"]),
            terminal: std::env::var("TERM_PROGRAM").ok(),
            tty: tty(),
            input_channel,
            status: SessionStatus::Active,
            exit_code: None,
            self_summary: None,
            provider_session_refs: Vec::new(),
            observed_title: None,
            last_dispatched_at: None,
            mcp_injected: false,
            mcp_seen_at: None,
            mcp_reported_at: None,
            mcp_config_path: None,
            mcp_command: None,
            mcp_args: Vec::new(),
            mcp_log_path: None,
            mcp_last_request: None,
            mcp_last_error: None,
            started_at: now,
            updated_at: now,
        }
    }

    pub fn display_name(&self) -> &str {
        self.observed_title
            .as_ref()
            .map(|title| title.title.as_str())
            .or_else(|| {
                self.self_summary
                    .as_ref()
                    .filter(|summary| summary.is_current())
                    .map(|summary| summary.label.as_str())
            })
            .or(self.repo_name.as_deref())
            .unwrap_or(&self.cli)
    }

    pub fn set_observed_title(&mut self, title: &str, source: &str) {
        let title = sanitize_short_text(title, 80);
        let source = sanitize_short_text(source, 80);
        if title.is_empty() || source.is_empty() {
            return;
        }
        self.observed_title = Some(ObservedTitle {
            title,
            source,
            updated_at: now(),
        });
        self.updated_at = now();
    }

    pub fn set_summary(
        &mut self,
        label: &str,
        summary: &str,
        topics: Vec<String>,
        phase: &str,
        ttl_seconds: u64,
    ) -> Result<()> {
        if label.chars().count() > 20 {
            anyhow::bail!("label must be at most 20 characters");
        }
        if summary.chars().count() > 80 {
            anyhow::bail!("summary must be at most 80 characters");
        }
        if topics.len() > 8 || topics.iter().any(|topic| topic.chars().count() > 20) {
            anyhow::bail!("topics exceed limits");
        }
        if !matches!(
            phase,
            "planning" | "editing" | "testing" | "waiting" | "done" | "blocked"
        ) {
            anyhow::bail!("invalid phase");
        }
        self.self_summary = Some(SelfSummary {
            label: label.to_owned(),
            summary: summary.to_owned(),
            topics,
            phase: phase.to_owned(),
            expires_at: now() + ttl_seconds.max(1) as f64,
        });
        self.updated_at = now();
        Ok(())
    }

    pub fn mark_mcp_seen(&mut self) {
        self.mcp_seen_at = Some(now());
        self.updated_at = now();
    }

    pub fn mark_mcp_request(&mut self, method: &str, error: Option<&str>, reported: bool) {
        let timestamp = now();
        self.mcp_seen_at = Some(timestamp);
        if reported && error.is_none() {
            self.mcp_reported_at = Some(timestamp);
        }
        self.mcp_last_request = Some(method.to_owned());
        self.mcp_last_error = error.map(str::to_owned);
        self.updated_at = timestamp;
    }
}

fn sanitize_short_text(value: &str, max_chars: usize) -> String {
    value
        .chars()
        .filter(|character| !character.is_control())
        .take(max_chars)
        .collect::<String>()
        .trim()
        .to_owned()
}

pub trait ProcessInspector {
    fn is_alive(&self, pid: u32) -> bool;
}

pub struct SystemProcessInspector;

impl ProcessInspector for SystemProcessInspector {
    fn is_alive(&self, pid: u32) -> bool {
        unsafe {
            libc::kill(pid as i32, 0) == 0
                || std::io::Error::last_os_error().raw_os_error() == Some(libc::EPERM)
        }
    }
}

#[derive(Debug, Clone)]
pub struct SessionRegistry {
    home: PathBuf,
}

impl SessionRegistry {
    pub fn new(home: impl AsRef<Path>) -> Self {
        Self {
            home: home.as_ref().to_owned(),
        }
    }

    pub fn home(&self) -> &Path {
        &self.home
    }

    pub fn input_dir(&self) -> PathBuf {
        self.home.join("fifo")
    }

    pub fn path(&self) -> PathBuf {
        self.home.join("sessions.jsonl")
    }

    pub fn upsert(&self, card: &SessionCard) -> Result<()> {
        self.with_lock(|cards| {
            cards.retain(|existing| existing.agent_id != card.agent_id);
            cards.push(card.clone());
            Ok(())
        })
    }

    pub fn update_exit(&self, agent_id: &str, exit_code: i32) -> Result<()> {
        self.with_lock(|cards| {
            let card = cards
                .iter_mut()
                .find(|card| card.agent_id == agent_id)
                .context("session not found")?;
            card.status = SessionStatus::Exited;
            card.exit_code = Some(exit_code);
            card.updated_at = now();
            Ok(())
        })
    }

    pub fn update(
        &self,
        agent_id: &str,
        operation: impl FnOnce(&mut SessionCard) -> Result<()>,
    ) -> Result<()> {
        self.with_lock(|cards| {
            let card = cards
                .iter_mut()
                .find(|card| card.agent_id == agent_id)
                .context("session not found")?;
            operation(card)?;
            card.updated_at = now();
            Ok(())
        })
    }

    pub fn list(
        &self,
        include_inactive: bool,
        inspector: &dyn ProcessInspector,
    ) -> Result<Vec<SessionCard>> {
        let mut result = Vec::new();
        self.with_lock(|cards| {
            for card in cards.iter_mut() {
                if card.status == SessionStatus::Active && !inspector.is_alive(card.wrapper_pid) {
                    card.status = SessionStatus::Stale;
                    card.updated_at = now();
                }
                if include_inactive || card.status == SessionStatus::Active {
                    result.push(card.clone());
                }
            }
            Ok(())
        })?;
        result.sort_by(|left, right| right.updated_at.total_cmp(&left.updated_at));
        Ok(result)
    }

    pub fn remove_stale(&self, inspector: &dyn ProcessInspector) -> Result<usize> {
        self.with_lock(|cards| {
            for card in cards.iter_mut() {
                if card.status == SessionStatus::Active && !inspector.is_alive(card.wrapper_pid) {
                    card.status = SessionStatus::Stale;
                }
            }
            let before = cards.len();
            cards.retain(|card| card.status != SessionStatus::Stale);
            Ok(before - cards.len())
        })
    }

    pub fn remove_inactive(&self, inspector: &dyn ProcessInspector) -> Result<usize> {
        self.with_lock(|cards| {
            for card in cards.iter_mut() {
                if card.status == SessionStatus::Active && !inspector.is_alive(card.wrapper_pid) {
                    card.status = SessionStatus::Stale;
                    card.updated_at = now();
                }
            }
            let before = cards.len();
            cards.retain(|card| card.status == SessionStatus::Active);
            Ok(before - cards.len())
        })
    }

    fn with_lock<T>(
        &self,
        operation: impl FnOnce(&mut Vec<SessionCard>) -> Result<T>,
    ) -> Result<T> {
        ensure_private_directory(&self.home)?;
        let lock = OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .mode(0o600)
            .open(self.home.join("sessions.lock"))?;
        secure_private_file(&self.home.join("sessions.lock"))?;
        lock.lock_exclusive()?;
        let mut cards = self.read_all()?;
        let result = operation(&mut cards);
        if result.is_ok() {
            self.write_all(&cards)?;
        }
        let _ = FileExt::unlock(&lock);
        result
    }

    fn read_all(&self) -> Result<Vec<SessionCard>> {
        if !self.path().exists() {
            return Ok(Vec::new());
        }
        let reader = std::io::BufReader::new(fs::File::open(self.path())?);
        Ok(reader
            .lines()
            .map_while(Result::ok)
            .filter(|line| !line.trim().is_empty())
            .filter_map(|line| serde_json::from_str(&line).ok())
            .collect())
    }

    fn write_all(&self, cards: &[SessionCard]) -> Result<()> {
        let temporary = self
            .home
            .join(format!("sessions.{}.tmp", std::process::id()));
        let mut file = fs::File::create(&temporary)?;
        secure_private_file(&temporary)?;
        for card in cards {
            serde_json::to_writer(&mut file, card)?;
            file.write_all(b"\n")?;
        }
        file.sync_all()?;
        fs::rename(temporary, self.path())?;
        Ok(())
    }
}

pub(crate) fn ensure_private_directory(path: &Path) -> Result<()> {
    fs::create_dir_all(path)?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    Ok(())
}

pub(crate) fn secure_private_file(path: &Path) -> Result<()> {
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
    Ok(())
}

pub(crate) fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
}

fn git(cwd: &Path, args: &[&str]) -> Option<String> {
    let output = Command::new("git")
        .args(args)
        .current_dir(cwd)
        .output()
        .ok()?;
    output
        .status
        .success()
        .then(|| String::from_utf8_lossy(&output.stdout).trim().to_owned())
        .filter(|value| !value.is_empty())
}

fn tty() -> Option<String> {
    let pointer = unsafe { libc::ttyname(libc::STDIN_FILENO) };
    (!pointer.is_null()).then(|| {
        unsafe { std::ffi::CStr::from_ptr(pointer) }
            .to_string_lossy()
            .into_owned()
    })
}
