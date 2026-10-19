// Run the real evidence tool against the real sidecar. Tests never load a real
// model: on a host that could serve one, the full collection is skipped.
use std::{net::TcpStream, process::Command, time::Duration};

fn tool() -> Command {
    Command::new(env!("CARGO_BIN_EXE_neura_engine_evidence"))
}

fn host_may_serve_model() -> bool {
    cfg!(windows)
        && TcpStream::connect_timeout(
            &"127.0.0.1:11434".parse().unwrap(),
            Duration::from_millis(300),
        )
        .is_ok()
}

#[test]
fn refuses_without_explicit_consent_and_starts_nothing() {
    let output = tool().args(["--runs", "1"]).output().unwrap();
    assert_eq!(output.status.code(), Some(64));
    assert!(output.stdout.is_empty());
    let message = String::from_utf8(output.stderr).unwrap();
    assert!(message.contains("--confirm-local-model"));
    assert!(message.contains("never downloads a model"));
}

#[test]
fn reports_an_unavailable_model_as_content_free_json() {
    if host_may_serve_model() {
        return;
    }
    let report = std::env::temp_dir().join(format!("neura-evidence-{}.json", std::process::id()));
    let output = tool()
        .args(["--confirm-local-model", "--runs", "1", "--sidecar"])
        .arg(env!("CARGO_BIN_EXE_neura_api"))
        .arg("--out")
        .arg(&report)
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(2), "model unavailable exit code");
    let text = std::fs::read_to_string(&report).unwrap();
    let _ = std::fs::remove_file(&report);
    let value: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!(value["schema_version"], 2);
    assert_eq!(value["model_mode"], "unavailable");
    assert!(value["unavailable_code"].is_string());
    assert_eq!(value["model"]["tag"], "qwen3:4b-instruct");
    assert!(value["host"]["logical_cpus"].as_u64().unwrap() > 0);
    // Nothing was measured, so no run data exists.
    assert!(value.get("runs").is_none());
    assert!(value.get("cancellation").is_none());
}
