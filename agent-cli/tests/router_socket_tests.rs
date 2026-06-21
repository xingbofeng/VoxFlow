use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::UnixStream;
use std::thread;
use std::time::{Duration, Instant};

use tempfile::tempdir;
use voxflow::ipc::RouterServer;
use voxflow::router::Router;
use voxflow::session::{SessionCard, SessionStatus};

#[test]
fn unix_socket_lists_resolves_learns_alias_and_sends() {
    let temp = tempdir().unwrap();
    let input = temp.path().join("agent.stdin");
    fs::write(&input, "").unwrap();
    let router = Router::new(temp.path());
    let mut card = SessionCard::new(
        vec!["codex".into()],
        input.clone(),
        std::process::id(),
        std::process::id(),
    );
    card.agent_id = "agent-1".into();
    card.status = SessionStatus::Active;
    card.set_summary("前端", "页面", vec![], "editing", 3600)
        .unwrap();
    router.registry().upsert(&card).unwrap();
    let mut exited = card.clone();
    exited.agent_id = "agent-old".into();
    exited.status = SessionStatus::Exited;
    router.registry().upsert(&exited).unwrap();

    let socket = temp.path().join("router.sock");
    let server = RouterServer::new(router, &socket);
    let handle = thread::spawn(move || server.serve_n(10).unwrap());
    wait_for(|| socket.exists());
    assert_eq!(
        fs::metadata(&socket).unwrap().permissions().mode() & 0o777,
        0o600
    );

    let listed = request(&socket, r#"{"id":1,"method":"list_agents","params":{}}"#);
    assert_eq!(listed["result"].as_array().unwrap().len(), 1);
    assert_eq!(listed["result"][0]["agent_id"], "agent-1");
    let all = request(
        &socket,
        r#"{"id":8,"method":"list_agents","params":{"include_inactive":true}}"#,
    );
    assert_eq!(all["result"].as_array().unwrap().len(), 2);
    let resolved = request(
        &socket,
        r#"{"id":2,"method":"resolve_agent","params":{"utterance":"前端，检查按钮"}}"#,
    );
    assert_eq!(resolved["result"]["outcome"], "direct");
    let learned = request(
        &socket,
        r#"{"id":3,"method":"learn_alias","params":{"alias":"网页","agent_id":"agent-1","user_confirmed":true}}"#,
    );
    assert_eq!(learned["result"]["saved"], true);
    let sent = request(
        &socket,
        r#"{"id":4,"method":"send_message","params":{"agent_id":"agent-1","message":"更新按钮","submit":true}}"#,
    );
    assert_eq!(sent["result"]["submitted"], true);
    let aliases = request(&socket, r#"{"id":5,"method":"list_aliases","params":{}}"#);
    assert_eq!(aliases["result"]["网页"], "agent-1");
    let logs = request(
        &socket,
        r#"{"id":6,"method":"list_dispatch_log","params":{"agent_id":"agent-1","limit":10}}"#,
    );
    assert_eq!(logs["result"][0]["message"], "更新按钮");
    let cleared = request(
        &socket,
        r#"{"id":9,"method":"clear_dispatch_log","params":{}}"#,
    );
    assert_eq!(cleared["result"]["cleared"], true);
    let empty_logs = request(
        &socket,
        r#"{"id":10,"method":"list_dispatch_log","params":{"agent_id":"agent-1","limit":10}}"#,
    );
    assert!(empty_logs["result"].as_array().unwrap().is_empty());
    let removed = request(
        &socket,
        r#"{"id":7,"method":"remove_alias","params":{"alias":"网页"}}"#,
    );
    assert_eq!(removed["result"]["removed"], true);
    handle.join().unwrap();
    assert_eq!(fs::read_to_string(input).unwrap(), "更新按钮\r");
}

#[test]
fn router_server_rejects_a_second_owner_for_the_same_socket() {
    let temp = tempdir().unwrap();
    let socket = temp.path().join("router.sock");
    let first = RouterServer::new(Router::new(temp.path()), &socket);
    let handle = thread::spawn(move || first.serve_n(1).unwrap());
    wait_for(|| socket.exists());

    let second = RouterServer::new(Router::new(temp.path()), &socket);
    assert!(second.serve_n(1).is_err());

    let response = request(&socket, r#"{"id":1,"method":"list_agents","params":{}}"#);
    assert!(response["result"].is_array());
    handle.join().unwrap();
}

#[test]
fn stalled_client_does_not_block_following_requests() {
    let temp = tempdir().unwrap();
    let socket = temp.path().join("router.sock");
    let server = RouterServer::new(Router::new(temp.path()), &socket);
    let handle = thread::spawn(move || server.serve_n(2).unwrap());
    wait_for(|| socket.exists());

    let _stalled = UnixStream::connect(&socket).unwrap();

    let started = Instant::now();
    let response = request(&socket, r#"{"id":2,"method":"list_agents","params":{}}"#);

    assert!(started.elapsed() < Duration::from_secs(1));
    assert!(response["result"].is_array());
    handle.join().unwrap();
}

#[test]
fn oversized_request_is_rejected_without_stopping_server() {
    let temp = tempdir().unwrap();
    let socket = temp.path().join("router.sock");
    let server = RouterServer::new(Router::new(temp.path()), &socket);
    let handle = thread::spawn(move || server.serve_n(2).unwrap());
    wait_for(|| socket.exists());

    let mut stream = UnixStream::connect(&socket).unwrap();
    let oversized = format!(
        r#"{{"id":1,"method":"resolve_agent","params":{{"utterance":"{}"}}}}"#,
        "x".repeat(2 * 1024 * 1024)
    );
    let _ = stream.write_all(oversized.as_bytes());
    let _ = stream.write_all(b"\n");
    let mut line = String::new();
    BufReader::new(stream).read_line(&mut line).unwrap();
    let response: serde_json::Value = serde_json::from_str(&line).unwrap();
    assert_eq!(response["error"]["code"], "request_too_large");

    let healthy = request(&socket, r#"{"id":2,"method":"list_agents","params":{}}"#);
    assert!(healthy["result"].is_array());
    handle.join().unwrap();
}

fn request(socket: &std::path::Path, json: &str) -> serde_json::Value {
    let mut stream = UnixStream::connect(socket).unwrap();
    stream.write_all(json.as_bytes()).unwrap();
    stream.write_all(b"\n").unwrap();
    let mut line = String::new();
    BufReader::new(stream).read_line(&mut line).unwrap();
    serde_json::from_str(&line).unwrap()
}

fn wait_for(mut ready: impl FnMut() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(3);
    while !ready() {
        assert!(
            Instant::now() < deadline,
            "timed out waiting for router socket"
        );
        thread::sleep(Duration::from_millis(10));
    }
}
