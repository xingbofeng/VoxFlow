use std::fs;
use std::os::unix::fs::PermissionsExt;
use tempfile::tempdir;
use voxflow::router::{DispatchFailureReason, ResolveOutcome, Router};
use voxflow::session::{ProcessInspector, ProviderReference, SessionCard, SessionStatus};

struct Alive;
impl ProcessInspector for Alive {
    fn is_alive(&self, _: u32) -> bool {
        true
    }
}

fn card(home: &std::path::Path, id: &str, cli: &str, repo: &str) -> SessionCard {
    let input = home.join(format!("{id}.stdin"));
    fs::write(&input, "").unwrap();
    let mut card = SessionCard::new(
        vec![cli.to_owned()],
        input,
        std::process::id(),
        std::process::id(),
    );
    card.agent_id = id.to_owned();
    card.cli = cli.to_owned();
    card.repo_name = Some(repo.to_owned());
    card.status = SessionStatus::Active;
    card
}

#[test]
fn intent_parser_supports_all_five_conservative_forms() {
    let cases = [
        ("前端，把按钮改白", "前端", "把按钮改白"),
        ("后端：检查接口", "后端", "检查接口"),
        ("给数据库说检查迁移", "数据库", "检查迁移"),
        ("让前端更新状态", "前端", "更新状态"),
        ("叫后端补单测", "后端", "补单测"),
    ];
    for (utterance, target, message) in cases {
        let parsed = voxflow::router::parse_intent(
            utterance,
            &["前端".into(), "后端".into(), "数据库".into()],
        )
        .unwrap();
        assert_eq!(parsed.target_phrase, target);
        assert_eq!(parsed.message, message);
    }
}

#[test]
fn intent_parser_supports_name_prefix_with_inline_message() {
    let cases = [
        ("Codex 帮我修复登录错误", "Codex", "帮我修复登录错误"),
        ("张三修一下 bug", "张三", "修一下 bug"),
        ("Claude 看下报错", "Claude", "看下报错"),
    ];
    for (utterance, target, message) in cases {
        let parsed = voxflow::router::parse_intent(
            utterance,
            &["Codex".into(), "张三".into(), "Claude".into()],
        )
        .unwrap();
        assert_eq!(parsed.target_phrase, target);
        assert_eq!(parsed.message, message);
    }

    let only_name =
        voxflow::router::parse_intent("张三", &["Codex".into(), "张三".into()]).unwrap();
    assert_eq!(only_name.target_phrase, "张三");
    assert_eq!(only_name.message, "");
}

#[test]
fn exact_unique_name_direct_sends_after_only_narrow_normalization() {
    let temp = tempdir().unwrap();
    let router = Router::new(temp.path());
    let mut frontend = card(temp.path(), "front-id", "codex", "web");
    frontend
        .set_summary("１号前端", "处理按钮", vec!["前端".into()], "editing", 3600)
        .unwrap();
    router.registry().upsert(&frontend).unwrap();

    let outcome = router
        .resolve_utterance("一 号 前 端，把按钮改白！", &Alive)
        .unwrap();
    assert_eq!(
        outcome,
        ResolveOutcome::Direct {
            agent_id: "front-id".into(),
            message: "把按钮改白！".into(),
            matched_by: "exact_name".into(),
        }
    );
    assert_eq!(
        router
            .resolve_utterance("前台，把按钮改白", &Alive)
            .unwrap(),
        ResolveOutcome::NotFound
    );
}

#[test]
fn ambiguous_missing_message_and_unavailable_are_never_sent() {
    let temp = tempdir().unwrap();
    let router = Router::new(temp.path());
    let mut first = card(temp.path(), "a", "codex", "web");
    first
        .set_summary("前端", "页面", vec![], "editing", 3600)
        .unwrap();
    let mut second = card(temp.path(), "b", "claude", "api");
    second
        .set_summary("后端", "接口", vec![], "testing", 3600)
        .unwrap();
    router.registry().upsert(&first).unwrap();
    router.registry().upsert(&second).unwrap();

    assert_eq!(
        router.resolve_utterance("前端后端看一下", &Alive).unwrap(),
        ResolveOutcome::Ambiguous {
            candidates: vec!["a".into(), "b".into()],
        }
    );
    assert_eq!(
        router.resolve_utterance("前端", &Alive).unwrap(),
        ResolveOutcome::InvalidMessage
    );

    first.status = SessionStatus::Exited;
    router.registry().upsert(&first).unwrap();
    assert_eq!(
        router.resolve_utterance("前端，继续", &Alive).unwrap(),
        ResolveOutcome::Unavailable {
            agent_id: "a".into(),
            reason: DispatchFailureReason::Exited,
        }
    );
}

#[test]
fn inactive_session_with_the_same_name_does_not_block_the_unique_active_session() {
    let temp = tempdir().unwrap();
    let router = Router::new(temp.path());
    let mut active = card(temp.path(), "active", "codex", "web");
    active
        .set_summary("前端", "当前页面", vec![], "editing", 3600)
        .unwrap();
    let mut exited = card(temp.path(), "exited", "claude", "legacy");
    exited
        .set_summary("前端", "旧页面", vec![], "done", 3600)
        .unwrap();
    exited.status = SessionStatus::Exited;
    router.registry().upsert(&active).unwrap();
    router.registry().upsert(&exited).unwrap();

    assert_eq!(
        router.resolve_utterance("前端，检查按钮", &Alive).unwrap(),
        ResolveOutcome::Direct {
            agent_id: "active".into(),
            message: "检查按钮".into(),
            matched_by: "exact_name".into(),
        }
    );
}

#[test]
fn user_confirmed_alias_persists_and_precedes_agent_summary() {
    let temp = tempdir().unwrap();
    let router = Router::new(temp.path());
    let mut misleading = card(temp.path(), "a", "codex", "web");
    misleading
        .set_summary("数据库", "提到数据库", vec![], "editing", 3600)
        .unwrap();
    let database = card(temp.path(), "b", "claude", "db");
    router.registry().upsert(&misleading).unwrap();
    router.registry().upsert(&database).unwrap();

    router.learn_alias("数据库", "b", true).unwrap();
    assert!(router.learn_alias("未确认", "a", false).is_err());
    let reloaded = Router::new(temp.path());
    assert_eq!(
        fs::metadata(temp.path().join("aliases.json"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777,
        0o600
    );
    assert_eq!(
        fs::metadata(temp.path()).unwrap().permissions().mode() & 0o777,
        0o700
    );
    assert!(matches!(
        reloaded.resolve_utterance("数据库，检查迁移", &Alive).unwrap(),
        ResolveOutcome::Direct { agent_id, matched_by, .. }
            if agent_id == "b" && matched_by == "confirmed_alias"
    ));
}

#[test]
fn single_character_alias_does_not_direct_match_inside_general_utterance() {
    let temp = tempdir().unwrap();
    let router = Router::new(temp.path());
    let agent = card(temp.path(), "agent", "codex", "web");
    router.registry().upsert(&agent).unwrap();

    router.learn_alias("修", "agent", true).unwrap();

    assert_eq!(
        router
            .resolve_utterance("帮我修复登录错误", &Alive)
            .unwrap(),
        ResolveOutcome::NotFound
    );
}

#[test]
fn multiple_alias_matches_require_confirmation_instead_of_direct_send() {
    let temp = tempdir().unwrap();
    let router = Router::new(temp.path());
    let first = card(temp.path(), "front", "codex", "web");
    let second = card(temp.path(), "design", "claude", "design");
    router.registry().upsert(&first).unwrap();
    router.registry().upsert(&second).unwrap();

    router.learn_alias("前端", "front", true).unwrap();
    router.learn_alias("页面", "design", true).unwrap();

    assert_eq!(
        router
            .resolve_utterance("这个前端页面交给前端处理", &Alive)
            .unwrap(),
        ResolveOutcome::Ambiguous {
            candidates: vec!["design".into(), "front".into()],
        }
    );
}

#[test]
fn resolver_uses_summary_topics_and_provider_refs_as_auxiliary_match_signals() {
    let temp = tempdir().unwrap();
    let router = Router::new(temp.path());
    let mut agent = card(temp.path(), "agent", "codex", "web");
    agent
        .set_summary(
            "前端",
            "正在处理按钮样式",
            vec!["按钮样式".into()],
            "editing",
            3600,
        )
        .unwrap();
    router.registry().upsert(&agent).unwrap();
    router
        .attach_reference(
            "agent",
            ProviderReference {
                provider: "codex".into(),
                kind: "session_id".into(),
                value: "session-42".into(),
                description: Some("按钮会话".into()),
            },
        )
        .unwrap();

    assert!(matches!(
        router.resolve_utterance("按钮样式，继续收尾", &Alive).unwrap(),
        ResolveOutcome::Direct { agent_id, message, .. }
            if agent_id == "agent" && message == "继续收尾"
    ));
    assert!(matches!(
        router.resolve_utterance("session-42，检查状态", &Alive).unwrap(),
        ResolveOutcome::Direct { agent_id, message, .. }
            if agent_id == "agent" && message == "检查状态"
    ));
}

#[test]
fn session_start_hook_attaches_provider_refs_and_observed_title_without_transcript_body() {
    let temp = tempdir().unwrap();
    let router = Router::new(temp.path());
    let transcript = temp.path().join("claude-session.jsonl");
    fs::write(
        &transcript,
        r#"{"type":"user","message":{"content":"must not be copied"}}
{"type":"ai-title","sessionId":"provider-1","aiTitle":"登录页修复"}
"#,
    )
    .unwrap();
    let agent = card(temp.path(), "agent", "claude", "web");
    router.registry().upsert(&agent).unwrap();

    router
        .record_provider_session_start(
            "agent",
            "claude",
            "provider-1",
            Some(transcript.display().to_string()),
            Some("resume"),
        )
        .unwrap();

    let card = router
        .registry()
        .list(true, &Alive)
        .unwrap()
        .into_iter()
        .find(|card| card.agent_id == "agent")
        .unwrap();
    assert_eq!(card.display_name(), "登录页修复");
    assert!(card.provider_session_refs.iter().any(|reference| {
        reference.provider == "claude"
            && reference.kind == "session_id"
            && reference.value == "provider-1"
    }));
    assert!(card.provider_session_refs.iter().any(|reference| {
        reference.provider == "claude"
            && reference.kind == "transcript_path"
            && reference.value == transcript.display().to_string()
    }));
    let registry = fs::read_to_string(router.registry().path()).unwrap();
    assert!(registry.contains("登录页修复"));
    assert!(!registry.contains("must not be copied"));
    assert!(matches!(
        router.resolve_utterance("登录页修复，继续", &Alive).unwrap(),
        ResolveOutcome::Direct { agent_id, message, .. }
            if agent_id == "agent" && message == "继续"
    ));
}

#[test]
fn refresh_provider_titles_picks_up_later_rename_events_from_known_transcript() {
    let temp = tempdir().unwrap();
    let router = Router::new(temp.path());
    let transcript = temp.path().join("codebuddy-session.jsonl");
    fs::write(
        &transcript,
        r#"{"type":"ai-title","sessionId":"provider-2","aiTitle":"旧标题"}
"#,
    )
    .unwrap();
    let agent = card(temp.path(), "agent", "codebuddy", "web");
    router.registry().upsert(&agent).unwrap();
    router
        .record_provider_session_start(
            "agent",
            "codebuddy",
            "provider-2",
            Some(transcript.display().to_string()),
            Some("startup"),
        )
        .unwrap();

    fs::write(
        &transcript,
        r#"{"type":"ai-title","sessionId":"provider-2","aiTitle":"旧标题"}
{"type":"custom-title","sessionId":"provider-2","customTitle":"123","cwd":"/tmp/web"}
{"type":"summary","summary":"hello","providerData":{"source":"initial-user-message"}}
"#,
    )
    .unwrap();

    router.refresh_provider_titles().unwrap();
    let card = router
        .registry()
        .list(true, &Alive)
        .unwrap()
        .into_iter()
        .find(|card| card.agent_id == "agent")
        .unwrap();
    assert_eq!(card.display_name(), "123");
    assert_eq!(
        card.observed_title.unwrap().source,
        "codebuddy.custom-title"
    );
}

#[test]
fn dispatch_logs_summaries_and_provider_refs_persist_without_terminal_output() {
    let temp = tempdir().unwrap();
    let router = Router::new(temp.path());
    let agent = card(temp.path(), "agent", "codex", "web");
    router.registry().upsert(&agent).unwrap();
    router
        .attach_reference(
            "agent",
            ProviderReference {
                provider: "codex".into(),
                kind: "session_id".into(),
                value: "session-42".into(),
                description: None,
            },
        )
        .unwrap();
    router
        .append_dispatch("agent", "检查按钮", true, None, 100.0)
        .unwrap();
    router
        .append_dispatch("agent", "更新按钮", true, None, 1000.0)
        .unwrap();

    assert_eq!(router.dispatch_logs(Some("agent"), 10).unwrap().len(), 2);
    router.prune_dispatch_logs(500.0).unwrap();
    assert_eq!(
        router.dispatch_logs(None, 10).unwrap()[0].message,
        "更新按钮"
    );
    let registry = fs::read_to_string(router.registry().path()).unwrap();
    assert!(registry.contains("session-42"));
    assert!(!registry.contains("terminal_output"));
    for path in [
        router.registry().path(),
        temp.path().join("dispatch-log.jsonl"),
    ] {
        assert_eq!(
            fs::metadata(path).unwrap().permissions().mode() & 0o777,
            0o600
        );
    }
}

#[test]
fn dispatch_log_is_pruned_and_long_messages_are_truncated_on_append() {
    let temp = tempdir().unwrap();
    let router = Router::new(temp.path());
    let agent = card(temp.path(), "agent", "codex", "web");
    router.registry().upsert(&agent).unwrap();

    for index in 0..10_000 {
        router
            .append_dispatch(
                "agent",
                &format!("{}-{index}", "x".repeat(20_000)),
                true,
                None,
                index as f64,
            )
            .unwrap();
    }

    let log_size = fs::metadata(temp.path().join("dispatch-log.jsonl"))
        .unwrap()
        .len();
    assert!(log_size <= 1_048_576, "log grew to {log_size} bytes");

    let entries = router.dispatch_logs(Some("agent"), 100).unwrap();
    assert_eq!(entries.len(), 100);
    assert!(entries.last().unwrap().message.chars().count() <= 4_096);
}

#[test]
fn dispatch_log_can_be_cleared_by_user_action() {
    let temp = tempdir().unwrap();
    let router = Router::new(temp.path());
    router
        .append_dispatch("agent", "检查按钮", true, None, 100.0)
        .unwrap();
    assert_eq!(router.dispatch_logs(None, 10).unwrap().len(), 1);

    router.clear_dispatch_logs().unwrap();

    assert!(router.dispatch_logs(None, 10).unwrap().is_empty());
}
