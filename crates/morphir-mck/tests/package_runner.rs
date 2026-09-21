#![cfg(unix)]
use morphir_mck::package::{Contract, load_kit, run_process};
use morphir_mck::transport::Limits;
use std::ffi::OsString;
use std::path::PathBuf;
use std::time::Duration;

fn kit() -> morphir_mck::package::Kit {
    load_kit(
        &PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../spec/package/mck"),
        Contract::Integrity,
    )
}
fn run(script: &str) -> morphir_mck::package::Report {
    run_process(
        &kit(),
        std::ffi::OsStr::new("sh"),
        &[OsString::from("-c"), OsString::from(script)],
        Limits {
            request_timeout: Duration::from_millis(500),
            shutdown_grace: Duration::from_millis(100),
            ..Limits::DEFAULT
        },
        "test",
        "2000-01-01T00:00:00Z",
    )
}
const EMPTY_CAPS: &str = r#"{"id":1,"suite":"package","contractVersion":"0.1.0-draft.1","implementation":"fixture","implementationVersion":"1","operations":[]}"#;

#[test]
fn unsupported_required_operations_are_skips_and_nonzero() {
    let report = run(&format!(
        "read -r line; printf '%s\\n' '{EMPTY_CAPS}'; read -r line; exit 0"
    ));
    assert_eq!(report.exit_code(), 1);
    let value = serde_json::to_value(report).unwrap();
    assert_eq!(value["records"].as_array().unwrap().len(), 80);
    assert!(
        value["records"]
            .as_array()
            .unwrap()
            .iter()
            .all(|record| record["result"] == "skipped")
    );
    assert_eq!(value["testee"]["implementation"], "fixture");
}

#[test]
fn mismatched_or_duplicate_capabilities_are_kit_errors() {
    for caps in [
        EMPTY_CAPS.replace("draft.1", "draft.2"),
        EMPTY_CAPS.replace(
            "\"operations\":[]",
            "\"operations\":[\"normalize\",\"normalize\"]",
        ),
        EMPTY_CAPS.replace("\"id\":1", "\"id\":1,\"id\":1"),
    ] {
        let report = run(&format!(
            "read -r line; printf '%s\\n' '{caps}'; read -r line; exit 0"
        ));
        let value = serde_json::to_value(report).unwrap();
        assert_eq!(value["records"][0]["result"], "kit-error");
        assert_eq!(value["records"][0]["caseId"], "package-adapter");
    }
}

#[test]
fn shutdown_failures_remain_kit_errors() {
    let report = run(&format!(
        "read -r line; printf '%s\\n' '{EMPTY_CAPS}'; read -r line; exit 3"
    ));
    let value = serde_json::to_value(report).unwrap();
    let last = value["records"].as_array().unwrap().last().unwrap();
    assert_eq!(last["caseId"], "package-adapter-close");
    assert_eq!(last["result"], "kit-error");
}

#[test]
fn invalid_kit_does_not_start_the_adapter_and_spawn_failure_is_reported() {
    let temp = tempfile::tempdir().unwrap();
    let bad = load_kit(temp.path(), Contract::Integrity);
    let report = run_process(
        &bad,
        std::ffi::OsStr::new("/missing-package-adapter"),
        &[],
        Limits::DEFAULT,
        "test",
        "fixed",
    );
    assert_eq!(
        serde_json::to_value(report).unwrap()["records"][0]["caseId"],
        "package-kit"
    );
    let report = run_process(
        &kit(),
        std::ffi::OsStr::new("/missing-package-adapter"),
        &[],
        Limits::DEFAULT,
        "test",
        "fixed",
    );
    assert_eq!(
        serde_json::to_value(report).unwrap()["records"][0]["caseId"],
        "package-adapter"
    );
}

#[test]
fn request_contains_only_adapter_inputs_and_exact_results_pass() {
    let temp = tempfile::tempdir().unwrap();
    let transcript = temp.path().join("request.json");
    let mut kit = kit();
    kit.cases.retain(|case| matches!(&case.request,morphir_mck::package::Request::HashBytes { hex } if hex.is_empty()));
    assert_eq!(kit.cases.len(), 1);
    let caps = EMPTY_CAPS.replace("\"operations\":[]", "\"operations\":[\"hash-bytes\"]");
    let script = format!(
        "read -r line; printf '%s\\n' '{caps}'; read -r line; printf '%s\\n' \"$line\" > \"$1\"; printf '%s\\n' '{{\"id\":2,\"ok\":true,\"digest\":\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"}}'; read -r line; exit 0"
    );
    let report = run_process(
        &kit,
        std::ffi::OsStr::new("sh"),
        &[
            OsString::from("-c"),
            script.into(),
            OsString::from("adapter"),
            transcript.clone().into_os_string(),
        ],
        Limits::DEFAULT,
        "test",
        "2000-01-01T00:00:00Z",
    );
    assert_eq!(report.exit_code(), 0, "{:?}", report.records);
    assert_eq!(
        report.summary_line(),
        "1 pass, 0 fail, 0 kit-error, 0 skipped"
    );
    let request: serde_json::Value =
        serde_json::from_slice(&std::fs::read(transcript).unwrap()).unwrap();
    assert_eq!(
        request,
        serde_json::json!({"id":2,"op":"hash-bytes","hex":""})
    );
    let schema: serde_json::Value = serde_json::from_str(include_str!(
        "../../../spec/package/schemas/package-report.schema.json"
    ))
    .unwrap();
    jsonschema::validator_for(&schema)
        .unwrap()
        .validate(&serde_json::to_value(report).unwrap())
        .unwrap();
}

#[test]
fn wrong_results_fail_but_malformed_responses_and_transport_faults_are_kit_errors() {
    let mut kit = kit();
    kit.cases.retain(|case| matches!(&case.request,morphir_mck::package::Request::HashBytes { hex } if hex.is_empty()));
    let caps = EMPTY_CAPS.replace("\"operations\":[]", "\"operations\":[\"hash-bytes\"]");
    for (response, result) in [
        (
            format!(
                "{{\"id\":2,\"ok\":true,\"digest\":\"sha256:{}\"}}",
                "0".repeat(64)
            ),
            "fail",
        ),
        (
            "{\"id\":2,\"ok\":false,\"error\":\"invalid-document\"}".into(),
            "kit-error",
        ),
        (
            "{\"id\":2,\"ok\":true,\"digest\":\"invalid\"}".into(),
            "kit-error",
        ),
        ("{\"id\":3,\"ok\":true}".into(), "kit-error"),
        ("{\"id\":2,\"ok\":true,\"ok\":false}".into(), "kit-error"),
    ] {
        let script = format!(
            "read -r line; printf '%s\\n' '{caps}'; read -r line; printf '%s\\n' '{response}'; read -r line; exit 0"
        );
        let report = run_process(
            &kit,
            std::ffi::OsStr::new("sh"),
            &[OsString::from("-c"), script.into()],
            Limits::DEFAULT,
            "test",
            "fixed",
        );
        assert_eq!(report.exit_code(), 1);
        assert_eq!(
            serde_json::to_value(report).unwrap()["records"][0]["result"],
            result
        );
    }
}

#[test]
fn resolution_requires_the_flat_library_profile_and_uses_its_report_schema() {
    let kit = load_kit(
        &PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../spec/package/mck"),
        Contract::Resolution,
    );
    let caps = EMPTY_CAPS.replace("draft.1", "draft.2").replace(
        "\"operations\":[]",
        "\"operations\":[\"resolve-library\"],\"profiles\":[]",
    );
    let script = format!("read -r line; printf '%s\\n' '{caps}'; read -r line; exit 0");
    let report = run_process(
        &kit,
        std::ffi::OsStr::new("sh"),
        &[OsString::from("-c"), script.into()],
        Limits::DEFAULT,
        "test",
        "2000-01-01T00:00:00Z",
    );
    assert_eq!(report.exit_code(), 1);
    assert_eq!(report.records.len(), 78);
    assert!(
        report
            .records
            .iter()
            .all(|record| record.result == morphir_mck::package::ResultKind::Skipped)
    );
    let schema: serde_json::Value = serde_json::from_str(include_str!(
        "../../../spec/package/schemas/package-resolution-report.schema.json"
    ))
    .unwrap();
    jsonschema::validator_for(&schema)
        .unwrap()
        .validate(&serde_json::to_value(report).unwrap())
        .unwrap();
}
