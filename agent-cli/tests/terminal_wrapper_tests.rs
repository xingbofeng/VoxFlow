use std::fs;
use std::thread;
use std::time::{Duration, Instant};

use tempfile::tempdir;
use voxflow::input::InputChannel;
use voxflow::session::SessionRegistry;

#[test]
fn wrapper_registers_receives_submitted_message_and_records_clean_exit() {
    let temp = tempdir().unwrap();
    let output = temp.path().join("received.txt");
    let registry = SessionRegistry::new(temp.path());
    let script = format!(
        "stty -echo; IFS= read -r line; printf '%s|%s' \"$line\" \"$VOXFLOW_AGENT_ID\" > '{}'",
        output.display()
    );
    let runner_registry = registry.clone();
    let child = thread::spawn(move || {
        voxflow::wrapper::run(
            vec!["/bin/sh".into(), "-c".into(), script],
            &runner_registry,
        )
        .unwrap()
    });

    let card_path = wait_for(|| {
        fs::read_to_string(temp.path().join("sessions.jsonl"))
            .ok()
            .and_then(|content| {
                content
                    .lines()
                    .find(|line| !line.is_empty())
                    .map(str::to_owned)
            })
    });
    let card: serde_json::Value = serde_json::from_str(&card_path).unwrap();
    let agent_id = card["agent_id"].as_str().unwrap();
    let input_path = card["input_channel"].as_str().unwrap();

    InputChannel::send(input_path, "自动回车验证", true).unwrap();
    assert_eq!(child.join().unwrap(), 0);
    assert_eq!(
        fs::read_to_string(output).unwrap(),
        format!("自动回车验证|{agent_id}")
    );

    let registry = fs::read_to_string(temp.path().join("sessions.jsonl")).unwrap();
    assert!(registry.contains("\"status\":\"exited\""));
    assert!(!temp
        .path()
        .join("fifo")
        .join(format!("{agent_id}.stdin"))
        .exists());
}

fn wait_for<T>(mut operation: impl FnMut() -> Option<T>) -> T {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        if let Some(value) = operation() {
            return value;
        }
        assert!(
            Instant::now() < deadline,
            "timed out waiting for wrapper state"
        );
        thread::sleep(Duration::from_millis(25));
    }
}
