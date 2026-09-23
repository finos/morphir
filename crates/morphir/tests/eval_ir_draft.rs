use serde_json::{Value, json};
use std::{fs, process::Command};

fn fixed_request() -> Value {
    serde_json::from_str(include_str!(
        "../../../spec/ir/semantics/v3/cases/evaluation/five-cases.request.json"
    ))
    .unwrap()
}

fn evaluate(request: &Value) -> std::process::Output {
    let temp = tempfile::tempdir().unwrap();
    fs::write(temp.path().join("request.json"), request.to_string()).unwrap();
    Command::new(env!("CARGO_BIN_EXE_morphir"))
        .args(["eval", "--request", "request.json", "--json"])
        .current_dir(temp.path())
        .env("MORPHIR_HOME", temp.path().join("home"))
        .env("MORPHIR_LOG_FILE", "false")
        .output()
        .unwrap()
}

#[test]
fn eval_ir_draft_emits_five_literal_results_in_order() {
    let output = evaluate(&fixed_request());
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let expected: Value = serde_json::from_str(include_str!(
        "../../../spec/ir/semantics/v3/cases/evaluation/five-cases.report.json"
    ))
    .unwrap();
    assert_eq!(
        serde_json::from_slice::<Value>(&output.stdout).unwrap(),
        expected
    );
}

#[test]
fn eval_ir_draft_rejects_preflight_errors_without_a_report() {
    let mut request = fixed_request();
    request["calls"][0]["arguments"][0]["value"]["value"] = json!("not-an-integer");
    let output = evaluate(&request);
    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
    assert!(String::from_utf8_lossy(&output.stderr).contains("VALUE_CODEC_ERROR"));
}

#[test]
fn eval_ir_draft_rejects_unsupported_string_version_with_native_diagnostic() {
    let mut request = fixed_request();
    request["version"] = json!("1.1.0-draft.2");
    let output = evaluate(&request);
    assert!(!output.status.success());
    assert!(output.stdout.is_empty());
    assert!(
        String::from_utf8_lossy(&output.stderr).contains("UNSUPPORTED_EVALUATION_VERSION"),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn eval_ir_draft_emits_runtime_error_report_and_exits_nonzero() {
    let mut request = fixed_request();
    request["calls"] = json!([request["calls"][0].clone()]);
    request["limits"]["fuel"] = json!(1);
    let output = evaluate(&request);
    assert!(!output.status.success());
    let report: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(report["version"], "1.1.0-draft.1");
    assert_eq!(report["results"][0]["code"], "FUEL_EXHAUSTED");
}
