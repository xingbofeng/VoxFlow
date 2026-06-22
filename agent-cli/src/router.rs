use crate::input::InputChannel;
use crate::session::{
    ensure_private_directory, secure_private_file, ProcessInspector, ProviderReference,
    SessionCard, SessionRegistry, SessionStatus,
};
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::fs::{self, OpenOptions};
use std::io::{BufRead, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use unicode_normalization::UnicodeNormalization;

const MAX_DISPATCH_LOG_BYTES: u64 = 1_048_576;
const MAX_DISPATCH_LOG_ENTRIES: usize = 256;
const MAX_DISPATCH_MESSAGE_CHARS: usize = 512;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ParsedIntent {
    pub target_phrase: String,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DispatchFailureReason {
    Exited,
    Stale,
    InputChannelMissing,
    Ambiguous,
    NotFound,
    WriteFailed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "outcome", rename_all = "snake_case")]
pub enum ResolveOutcome {
    Direct {
        agent_id: String,
        message: String,
        matched_by: String,
    },
    Ambiguous {
        candidates: Vec<String>,
    },
    NotFound,
    InvalidMessage,
    Unavailable {
        agent_id: String,
        reason: DispatchFailureReason,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DispatchLogEntry {
    pub agent_id: String,
    pub message: String,
    pub submitted: bool,
    pub failure_reason: Option<DispatchFailureReason>,
    pub provider_refs: Vec<ProviderReference>,
    pub timestamp: f64,
}

#[derive(Debug, Clone)]
pub struct Router {
    home: PathBuf,
    registry: SessionRegistry,
}

impl Router {
    pub fn new(home: impl AsRef<Path>) -> Self {
        let home = home.as_ref().to_owned();
        Self {
            registry: SessionRegistry::new(&home),
            home,
        }
    }

    pub fn registry(&self) -> &SessionRegistry {
        &self.registry
    }

    pub fn resolve_utterance(
        &self,
        utterance: &str,
        inspector: &dyn ProcessInspector,
    ) -> Result<ResolveOutcome> {
        let cards = self.registry.list(true, inspector)?;
        let aliases = self.aliases()?;
        let utterance_key = normalize(utterance);

        let alias_matches: BTreeSet<_> = aliases
            .iter()
            .filter(|(alias, _)| alias_can_direct_match(alias))
            .filter(|(alias, _)| utterance_key.contains(alias.as_str()))
            .map(|(_, agent_id)| agent_id.clone())
            .collect();
        if !alias_matches.is_empty() {
            return self.resolve_matches(utterance, &cards, alias_matches, "confirmed_alias");
        }

        let mut card_matches: BTreeSet<_> = cards
            .iter()
            .filter(|card| {
                card_match_values(card)
                    .iter()
                    .map(|value| normalize(value))
                    .filter(|value| !value.is_empty())
                    .any(|value| utterance_key.contains(&value))
            })
            .map(|card| card.agent_id.clone())
            .collect();
        let active_matches = card_matches
            .iter()
            .filter(|agent_id| {
                cards.iter().any(|card| {
                    card.agent_id == agent_id.as_str() && card.status == SessionStatus::Active
                })
            })
            .cloned()
            .collect::<BTreeSet<_>>();
        if !active_matches.is_empty() {
            card_matches = active_matches;
        }
        self.resolve_matches(utterance, &cards, card_matches, "exact_name")
    }

    fn resolve_matches(
        &self,
        utterance: &str,
        cards: &[SessionCard],
        matches: BTreeSet<String>,
        matched_by: &str,
    ) -> Result<ResolveOutcome> {
        if matches.is_empty() {
            return Ok(ResolveOutcome::NotFound);
        }
        if matches.len() > 1 {
            return Ok(ResolveOutcome::Ambiguous {
                candidates: matches.into_iter().collect(),
            });
        }
        let agent_id = matches.into_iter().next().expect("one match");
        let card = cards
            .iter()
            .find(|card| card.agent_id == agent_id)
            .context("matched session disappeared")?;
        let candidates = card_match_values(card)
            .into_iter()
            .map(str::to_owned)
            .collect::<Vec<_>>();
        let parsed = parse_intent(utterance, &candidates).unwrap_or(ParsedIntent {
            target_phrase: card.display_name().to_owned(),
            message: String::new(),
        });
        if parsed.message.trim().is_empty() {
            return Ok(ResolveOutcome::InvalidMessage);
        }
        match card.status {
            SessionStatus::Exited => Ok(ResolveOutcome::Unavailable {
                agent_id,
                reason: DispatchFailureReason::Exited,
            }),
            SessionStatus::Stale => Ok(ResolveOutcome::Unavailable {
                agent_id,
                reason: DispatchFailureReason::Stale,
            }),
            SessionStatus::Active if !card.input_channel.exists() => {
                Ok(ResolveOutcome::Unavailable {
                    agent_id,
                    reason: DispatchFailureReason::InputChannelMissing,
                })
            }
            SessionStatus::Active => Ok(ResolveOutcome::Direct {
                agent_id,
                message: parsed.message,
                matched_by: matched_by.to_owned(),
            }),
        }
    }

    pub fn learn_alias(&self, alias: &str, agent_id: &str, user_confirmed: bool) -> Result<()> {
        if !user_confirmed {
            anyhow::bail!("alias requires user confirmation");
        }
        if !self
            .registry
            .list(true, &crate::session::SystemProcessInspector)?
            .iter()
            .any(|card| card.agent_id == agent_id)
        {
            anyhow::bail!("session not found");
        }
        let alias = normalize(alias);
        if alias.is_empty() {
            anyhow::bail!("alias is empty");
        }
        let mut aliases = self.aliases()?;
        aliases.insert(alias, agent_id.to_owned());
        self.write_json("aliases.json", &aliases)
    }

    pub fn list_aliases(&self) -> Result<BTreeMap<String, String>> {
        self.aliases()
    }

    pub fn remove_alias(&self, alias: &str) -> Result<bool> {
        let mut aliases = self.aliases()?;
        let removed = aliases.remove(&normalize(alias)).is_some();
        self.write_json("aliases.json", &aliases)?;
        Ok(removed)
    }

    pub fn attach_reference(&self, agent_id: &str, reference: ProviderReference) -> Result<()> {
        if reference.provider.trim().is_empty() || reference.value.trim().is_empty() {
            anyhow::bail!("provider and value are required");
        }
        if !matches!(
            reference.kind.as_str(),
            "session_id" | "transcript_path" | "log_path" | "conversation_id" | "other"
        ) {
            anyhow::bail!("invalid reference kind");
        }
        self.registry.update(agent_id, |card| {
            card.provider_session_refs.retain(|existing| {
                !(existing.provider == reference.provider
                    && existing.kind == reference.kind
                    && existing.value == reference.value)
            });
            card.provider_session_refs.push(reference);
            Ok(())
        })
    }

    pub fn record_provider_session_start(
        &self,
        agent_id: &str,
        provider: &str,
        session_id: &str,
        transcript_path: Option<String>,
        source: Option<&str>,
    ) -> Result<()> {
        if provider.trim().is_empty() || session_id.trim().is_empty() {
            anyhow::bail!("provider and session_id are required");
        }
        let provider = provider.trim().to_owned();
        let session_id = session_id.trim().to_owned();
        let transcript_path = transcript_path
            .map(|value| value.trim().to_owned())
            .filter(|value| !value.is_empty());
        let title = transcript_path.as_deref().and_then(|path| {
            latest_provider_title(Path::new(path), &provider)
                .ok()
                .flatten()
        });
        self.registry.update(agent_id, |card| {
            upsert_reference(
                card,
                ProviderReference {
                    provider: provider.clone(),
                    kind: "session_id".into(),
                    value: session_id.clone(),
                    description: source.map(|value| format!("SessionStart {value}")),
                },
            );
            if let Some(path) = &transcript_path {
                upsert_reference(
                    card,
                    ProviderReference {
                        provider: provider.clone(),
                        kind: "transcript_path".into(),
                        value: path.clone(),
                        description: None,
                    },
                );
            }
            if let Some((title, title_source)) = &title {
                card.set_observed_title(title, title_source);
            }
            Ok(())
        })
    }

    pub fn refresh_provider_titles(&self) -> Result<()> {
        let cards = self
            .registry
            .list(true, &crate::session::SystemProcessInspector)?;
        for card in cards {
            let existing = card.provider_session_refs.iter().find_map(|reference| {
                if reference.kind == "transcript_path" {
                    Some((reference.provider.as_str(), reference.value.as_str()))
                } else {
                    None
                }
            });
            let discovered = if existing.is_none() {
                discover_provider_transcript(&card)
            } else {
                None
            };
            let Some((provider, transcript_path)) =
                existing.or(discovered.as_ref().map(|reference| {
                    (
                        reference.provider.as_str(),
                        reference.transcript_path.as_str(),
                    )
                }))
            else {
                continue;
            };
            let Some((title, source)) =
                latest_provider_title(Path::new(transcript_path), provider)?
            else {
                continue;
            };
            self.registry.update(&card.agent_id, |card| {
                if let Some(reference) = &discovered {
                    upsert_reference(
                        card,
                        ProviderReference {
                            provider: reference.provider.clone(),
                            kind: "session_id".into(),
                            value: reference.session_id.clone(),
                            description: Some("discovered transcript".into()),
                        },
                    );
                    upsert_reference(
                        card,
                        ProviderReference {
                            provider: reference.provider.clone(),
                            kind: "transcript_path".into(),
                            value: reference.transcript_path.clone(),
                            description: None,
                        },
                    );
                }
                card.set_observed_title(&title, &source);
                Ok(())
            })?;
        }
        Ok(())
    }

    pub fn update_summary(
        &self,
        agent_id: &str,
        label: &str,
        summary: &str,
        topics: Vec<String>,
        phase: &str,
        ttl_seconds: u64,
    ) -> Result<()> {
        self.registry.update(agent_id, |card| {
            card.set_summary(label, summary, topics, phase, ttl_seconds)
        })
    }

    pub fn terminate_agent(&self, agent_id: &str) -> Result<()> {
        let card = self
            .registry
            .list(true, &crate::session::SystemProcessInspector)?
            .into_iter()
            .find(|card| card.agent_id == agent_id)
            .context("session not found")?;
        if card.status != SessionStatus::Active {
            anyhow::bail!("session is not active");
        }
        terminate_process(card.child_pid)?;
        terminate_process(card.wrapper_pid)?;
        self.registry.update(agent_id, |card| {
            card.status = SessionStatus::Exited;
            card.exit_code = Some(143);
            Ok(())
        })
    }

    pub fn send_message(&self, agent_id: &str, message: &str, submit: bool) -> Result<()> {
        let card = self
            .registry
            .list(true, &crate::session::SystemProcessInspector)?
            .into_iter()
            .find(|card| card.agent_id == agent_id)
            .context("session not found")?;
        let timestamp = now();
        if card.status != SessionStatus::Active {
            let reason = match card.status {
                SessionStatus::Exited => DispatchFailureReason::Exited,
                SessionStatus::Stale => DispatchFailureReason::Stale,
                SessionStatus::Active => unreachable!(),
            };
            self.append_dispatch(agent_id, message, false, Some(reason), timestamp)?;
            anyhow::bail!("session is unavailable");
        }
        if !card.input_channel.exists() {
            self.append_dispatch(
                agent_id,
                message,
                false,
                Some(DispatchFailureReason::InputChannelMissing),
                timestamp,
            )?;
            anyhow::bail!("session input channel is unavailable");
        }
        if let Err(error) = InputChannel::send(&card.input_channel, message, submit) {
            self.append_dispatch(
                agent_id,
                message,
                false,
                Some(DispatchFailureReason::WriteFailed),
                timestamp,
            )?;
            return Err(error);
        }
        self.registry.update(agent_id, |card| {
            card.last_dispatched_at = Some(now());
            Ok(())
        })?;
        self.append_dispatch(agent_id, message, submit, None, timestamp)
    }

    pub fn append_dispatch(
        &self,
        agent_id: &str,
        message: &str,
        submitted: bool,
        failure_reason: Option<DispatchFailureReason>,
        timestamp: f64,
    ) -> Result<()> {
        ensure_private_directory(&self.home)?;
        let provider_refs = self
            .registry
            .list(true, &crate::session::SystemProcessInspector)?
            .into_iter()
            .find(|card| card.agent_id == agent_id)
            .map(|card| card.provider_session_refs)
            .unwrap_or_default();
        let entry = DispatchLogEntry {
            agent_id: agent_id.to_owned(),
            message: truncate_for_dispatch_log(message),
            submitted,
            failure_reason,
            provider_refs,
            timestamp,
        };
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .mode(0o600)
            .open(self.log_path())?;
        secure_private_file(&self.log_path())?;
        serde_json::to_writer(&mut file, &entry)?;
        file.write_all(b"\n")?;
        drop(file);
        self.prune_dispatch_log_limits()?;
        Ok(())
    }

    pub fn dispatch_logs(
        &self,
        agent_id: Option<&str>,
        limit: usize,
    ) -> Result<Vec<DispatchLogEntry>> {
        if !self.log_path().exists() {
            return Ok(Vec::new());
        }
        let reader = std::io::BufReader::new(fs::File::open(self.log_path())?);
        let mut entries: Vec<_> = reader
            .lines()
            .map_while(Result::ok)
            .filter_map(|line| serde_json::from_str::<DispatchLogEntry>(&line).ok())
            .filter(|entry| agent_id.is_none_or(|id| entry.agent_id == id))
            .collect();
        if entries.len() > limit {
            entries.drain(0..entries.len() - limit);
        }
        Ok(entries)
    }

    pub fn prune_dispatch_logs(&self, cutoff: f64) -> Result<()> {
        let retained = self
            .dispatch_logs(None, usize::MAX)?
            .into_iter()
            .filter(|entry| entry.timestamp >= cutoff)
            .collect::<Vec<_>>();
        self.write_dispatch_logs(&retained)
    }

    pub fn clear_dispatch_logs(&self) -> Result<()> {
        self.write_dispatch_logs(&[])
    }

    fn prune_dispatch_log_limits(&self) -> Result<()> {
        let path = self.log_path();
        if !path.exists() || fs::metadata(&path)?.len() <= MAX_DISPATCH_LOG_BYTES {
            return Ok(());
        }

        let mut entries = self.dispatch_logs(None, usize::MAX)?;
        if entries.len() > MAX_DISPATCH_LOG_ENTRIES {
            entries.drain(0..entries.len() - MAX_DISPATCH_LOG_ENTRIES);
        }
        while encoded_dispatch_log_size(&entries)? > MAX_DISPATCH_LOG_BYTES && entries.len() > 1 {
            entries.remove(0);
        }
        self.write_dispatch_logs(&entries)
    }

    fn write_dispatch_logs(&self, entries: &[DispatchLogEntry]) -> Result<()> {
        ensure_private_directory(&self.home)?;
        let mut file = fs::File::create(self.log_path())?;
        secure_private_file(&self.log_path())?;
        for entry in entries {
            serde_json::to_writer(&mut file, entry)?;
            file.write_all(b"\n")?;
        }
        Ok(())
    }

    fn aliases(&self) -> Result<BTreeMap<String, String>> {
        let path = self.home.join("aliases.json");
        if !path.exists() {
            return Ok(BTreeMap::new());
        }
        Ok(serde_json::from_slice(&fs::read(path)?)?)
    }

    fn write_json<T: Serialize>(&self, name: &str, value: &T) -> Result<()> {
        ensure_private_directory(&self.home)?;
        let path = self.home.join(name);
        let temporary = path.with_extension("tmp");
        fs::write(&temporary, serde_json::to_vec_pretty(value)?)?;
        secure_private_file(&temporary)?;
        fs::rename(temporary, path)?;
        Ok(())
    }

    fn log_path(&self) -> PathBuf {
        self.home.join("dispatch-log.jsonl")
    }
}

pub fn parse_intent(utterance: &str, candidates: &[String]) -> Option<ParsedIntent> {
    let utterance = utterance.trim();
    for separator in ['，', ',', '：', ':'] {
        if let Some((target, message)) = utterance.split_once(separator) {
            return Some(ParsedIntent {
                target_phrase: target.trim().to_owned(),
                message: message.trim().to_owned(),
            });
        }
    }
    if let Some(rest) = utterance.strip_prefix('给') {
        if let Some((target, message)) = rest.split_once('说') {
            return Some(ParsedIntent {
                target_phrase: target.trim().to_owned(),
                message: message.trim().to_owned(),
            });
        }
    }
    for prefix in ['让', '叫'] {
        if let Some(rest) = utterance.strip_prefix(prefix) {
            if let Some(candidate) = longest_prefix_candidate(rest, candidates) {
                return Some(ParsedIntent {
                    target_phrase: candidate.clone(),
                    message: rest[candidate.len()..].trim().to_owned(),
                });
            }
        }
    }
    if let Some(candidate) = candidates
        .iter()
        .filter(|candidate| normalize(utterance).starts_with(&normalize(candidate)))
        .max_by_key(|candidate| normalize(candidate).len())
    {
        if utterance.starts_with(candidate.as_str()) {
            return Some(ParsedIntent {
                target_phrase: candidate.clone(),
                message: utterance[candidate.len()..].trim().to_owned(),
            });
        }
        if normalize(utterance) == normalize(candidate) {
            return Some(ParsedIntent {
                target_phrase: candidate.clone(),
                message: String::new(),
            });
        }
    }
    None
}

fn longest_prefix_candidate<'a>(value: &str, candidates: &'a [String]) -> Option<&'a String> {
    candidates
        .iter()
        .filter(|candidate| value.starts_with(candidate.as_str()))
        .max_by_key(|candidate| candidate.len())
}

fn card_match_values(card: &SessionCard) -> Vec<&str> {
    let mut values = vec![card.agent_id.as_str(), card.cli.as_str(), card.cwd.as_str()];
    values.extend(card.repo_name.as_deref());
    values.extend(card.branch.as_deref());
    if let Some(title) = &card.observed_title {
        values.push(title.title.as_str());
    }
    if let Some(summary) = card
        .self_summary
        .as_ref()
        .filter(|summary| summary.is_current())
    {
        values.push(summary.label.as_str());
        values.push(summary.summary.as_str());
        values.extend(summary.topics.iter().map(String::as_str));
    }
    for reference in &card.provider_session_refs {
        values.push(reference.value.as_str());
        values.extend(reference.description.as_deref());
    }
    values
}

fn upsert_reference(card: &mut SessionCard, reference: ProviderReference) {
    card.provider_session_refs.retain(|existing| {
        !(existing.provider == reference.provider
            && existing.kind == reference.kind
            && existing.value == reference.value)
    });
    card.provider_session_refs.push(reference);
}

struct DiscoveredProviderTranscript {
    provider: String,
    session_id: String,
    transcript_path: String,
}

fn discover_provider_transcript(card: &SessionCard) -> Option<DiscoveredProviderTranscript> {
    if card.cli != "codebuddy" {
        return None;
    }
    let home = std::env::var_os("HOME").map(PathBuf::from)?;
    let project_dir = home
        .join(".codebuddy")
        .join("projects")
        .join(codebuddy_project_key(&card.cwd));
    let entries = fs::read_dir(project_dir).ok()?;
    entries
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| {
            path.extension()
                .is_some_and(|extension| extension == std::ffi::OsStr::new("jsonl"))
        })
        .filter_map(|path| {
            let metadata = fs::metadata(&path).ok()?;
            let modified = metadata.modified().ok()?;
            let session_id = path.file_stem()?.to_string_lossy().into_owned();
            Some((modified, session_id, path))
        })
        .max_by_key(|(modified, _, _)| *modified)
        .map(|(_, session_id, path)| DiscoveredProviderTranscript {
            provider: "codebuddy".into(),
            session_id,
            transcript_path: path.display().to_string(),
        })
}

fn codebuddy_project_key(cwd: &str) -> String {
    cwd.trim_start_matches('/').replace('/', "-")
}

fn latest_provider_title(path: &Path, provider: &str) -> Result<Option<(String, String)>> {
    if !path.exists() {
        return Ok(None);
    }
    let reader = std::io::BufReader::new(fs::File::open(path)?);
    let mut explicit_title = None;
    let mut fallback_title = None;
    for line in reader.lines().map_while(Result::ok) {
        let Ok(value) = serde_json::from_str::<serde_json::Value>(&line) else {
            continue;
        };
        match value["type"].as_str() {
            Some("custom-title") => {
                if let Some(title) = value["customTitle"]
                    .as_str()
                    .filter(|title| !title.trim().is_empty())
                {
                    explicit_title = Some((title.to_owned(), format!("{provider}.custom-title")));
                }
            }
            Some("ai-title") => {
                if let Some(title) = value["aiTitle"]
                    .as_str()
                    .filter(|title| !title.trim().is_empty())
                {
                    explicit_title = Some((title.to_owned(), format!("{provider}.ai-title")));
                }
            }
            Some("summary") if provider == "codebuddy" => {
                if let Some(title) = value["summary"]
                    .as_str()
                    .filter(|title| !title.trim().is_empty())
                {
                    fallback_title = Some((title.to_owned(), "codebuddy.summary".into()));
                }
            }
            _ => {}
        }
    }
    Ok(explicit_title.or(fallback_title))
}

pub fn normalize(value: &str) -> String {
    value
        .nfkc()
        .flat_map(char::to_lowercase)
        .filter_map(|character| {
            if character.is_whitespace()
                || character.is_ascii_punctuation()
                || matches!(
                    character,
                    '，' | '。' | '！' | '？' | '：' | '；' | '、' | '“' | '”' | '‘' | '’'
                )
            {
                None
            } else if character == '一' {
                Some('1')
            } else {
                Some(character)
            }
        })
        .collect()
}

fn alias_can_direct_match(alias: &str) -> bool {
    if alias.is_empty() {
        return false;
    }
    let min_length = if alias.is_ascii() { 3 } else { 2 };
    alias.chars().count() >= min_length
}

fn truncate_for_dispatch_log(message: &str) -> String {
    message.chars().take(MAX_DISPATCH_MESSAGE_CHARS).collect()
}

fn encoded_dispatch_log_size(entries: &[DispatchLogEntry]) -> Result<u64> {
    let mut size = 0_u64;
    for entry in entries {
        size += serde_json::to_vec(entry)?.len() as u64 + 1;
    }
    Ok(size)
}

fn now() -> f64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
}

fn terminate_process(pid: u32) -> Result<()> {
    let result = unsafe { libc::kill(pid as i32, libc::SIGTERM) };
    if result == 0 {
        return Ok(());
    }
    let error = std::io::Error::last_os_error();
    if error.raw_os_error() == Some(libc::ESRCH) {
        return Ok(());
    }
    Err(error).with_context(|| format!("failed to terminate process {pid}"))
}
