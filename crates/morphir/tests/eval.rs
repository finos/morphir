use serde_json::{Value, json};
use std::{fs, process::Command};

fn request(source: &str, entrypoints: &[&str]) -> Value {
    json!({
        "version": 1,
        "provider": "rego",
        "program": {"kind":"source", "language":"rego", "modules":[
            {"path":"example.rego", "source":source}
        ]},
        "entrypoints": entrypoints,
        "input": {"answer":42},
        "timeout_ms":1000
    })
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

fn report(output: &std::process::Output) -> Value {
    serde_json::from_slice(&output.stdout).unwrap_or_else(|error| {
        panic!(
            "{error}; stdout={}; stderr={}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        )
    })
}

#[test]
fn eval_reports_values_and_undefined_without_treating_false_as_failure() {
    let output = evaluate(&request(
        "package example\ntest_ok := input.answer == 42\ntest_false := false\ntest_undefined if input.missing\ntest_object := {\"answer\": input.answer}",
        &[
            "data.example.test_ok",
            "data.example.test_false",
            "data.example.test_undefined",
            "data.example.test_object",
        ],
    ));
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        report(&output),
        json!({"version":1, "provider":"rego", "results":[
            {"entrypoint":"data.example.test_ok", "status":"value", "value":true},
            {"entrypoint":"data.example.test_false", "status":"value", "value":false},
            {"entrypoint":"data.example.test_undefined", "status":"undefined"},
            {"entrypoint":"data.example.test_object", "status":"value", "value":{"answer":42}}
        ]})
    );
}

#[test]
fn eval_retains_error_reports_for_invalid_source_missing_rules_and_runtime_errors() {
    for (source, entrypoint) in [
        ("this is not rego", "data.example.test_ok"),
        ("package example\ntest_ok := true", "data.example.missing"),
        ("package example\ntest_ok := 1 / 0", "data.example.test_ok"),
    ] {
        let output = evaluate(&request(source, &[entrypoint]));
        assert!(!output.status.success());
        let report = report(&output);
        assert_eq!(report["results"][0]["status"], "error");
        assert!(!report["results"][0]["message"].as_str().unwrap().is_empty());
    }
}

#[test]
fn eval_rejects_invalid_request_contracts() {
    let valid = request(
        "package example\ntest_ok := true",
        &["data.example.test_ok"],
    );
    for (pointer, invalid) in [
        ("/version", json!(2)),
        ("/provider", json!("unknown")),
        ("/program/language", json!("elm")),
        ("/program/modules", json!([])),
        ("/program/modules/0/path", json!(" ")),
        ("/entrypoints", json!([])),
        ("/entrypoints", json!([" "])),
        (
            "/entrypoints",
            json!(["data.example.test_ok", "data.example.test_ok"]),
        ),
        ("/timeout_ms", json!(0)),
        ("/timeout_ms", json!(300001)),
    ] {
        let mut invalid_request = valid.clone();
        *invalid_request.pointer_mut(pointer).unwrap() = invalid;
        let output = evaluate(&invalid_request);
        assert!(!output.status.success(), "accepted invalid {pointer}");
        assert!(String::from_utf8_lossy(&output.stderr).contains("invalid evaluation request"));
    }
    let mut duplicate_modules = valid;
    duplicate_modules["program"]["modules"]
        .as_array_mut()
        .unwrap()
        .push(json!({"path":"example.rego", "source":"package second\nvalue := true"}));
    assert!(!evaluate(&duplicate_modules).status.success());
}

#[test]
fn eval_bounds_expensive_rule_execution() {
    let mut req = request(
        "package example\ntest_ok := count([x | x := input.values[_]; y := input.values[_]; x == y])",
        &["data.example.test_ok"],
    );
    req["timeout_ms"] = json!(1);
    req["input"] = json!({"values":(0..1000).collect::<Vec<_>>()});
    let output = evaluate(&req);
    assert!(!output.status.success());
    let report = report(&output);
    assert_eq!(report["results"][0]["status"], "error");
    assert!(
        report["results"][0]["message"]
            .as_str()
            .unwrap()
            .to_lowercase()
            .contains("time")
    );
}
