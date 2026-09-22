#![cfg(unix)]
use morphir_mck::package::local_registry::{MvpRepositorySource, admit_mvp_inventory};
use morphir_mck::package::run_mvp_process;
use morphir_mck::transport::Limits;
use std::{ffi::OsString, path::Path};

fn inventory() -> morphir_mck::package::local_registry::AdmittedMvpInventory {
    let source =
        MvpRepositorySource::new(Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")).unwrap();
    admit_mvp_inventory(&source).unwrap()
}

#[test]
fn missing_mvp_capability_fails_every_required_case_without_skips() {
    let inventory = inventory();
    let script = "read -r line; printf '%s\\n' '{\"id\":1,\"suite\":\"package\",\"contractVersion\":\"0.1.0-draft.3\",\"implementation\":\"fixture\",\"implementationVersion\":\"1\",\"profiles\":[],\"operations\":[]}'; read -r line; exit 0";
    let run = run_mvp_process(
        &inventory,
        std::ffi::OsStr::new("sh"),
        &[OsString::from("-c"), OsString::from(script)],
        Limits::DEFAULT,
    );
    let report = serde_json::to_value(&run).unwrap();
    assert_eq!(report["records"].as_array().unwrap().len(), 2);
    assert!(
        report["records"]
            .as_array()
            .unwrap()
            .iter()
            .all(|record| record["result"] == "kit-error")
    );
    assert_eq!(run.exit_code(), 1);
}

#[test]
fn fixed_results_pass_over_input_only_transcript_and_wrong_result_fails() {
    let inventory = inventory();
    let temp = tempfile::tempdir().unwrap();
    let transcript = temp.path().join("request.jsonl");
    let caps = r#"{"id":1,"suite":"package","contractVersion":"0.1.0-draft.3","implementation":"fixture","implementationVersion":"1","profiles":["local-library-mvp:0.1.0-draft.1"],"operations":["restore-local-library"]}"#;
    let replies: Vec<String> = inventory
        .cases()
        .iter()
        .enumerate()
        .map(|(index, case)| {
            let mut value: serde_json::Value = serde_json::from_slice(case.expected()).unwrap();
            value["id"] = serde_json::json!(index + 2);
            value.to_string()
        })
        .collect();
    let script = format!(
        "read -r line; printf '%s\\n' '{caps}'; read -r line; printf '%s\\n' \"$line\" >> \"$1\"; printf '%s\\n' '{}'; read -r line; printf '%s\\n' \"$line\" >> \"$1\"; printf '%s\\n' '{}'; read -r line; exit 0",
        replies[0], replies[1]
    );
    let run = run_mvp_process(
        &inventory,
        std::ffi::OsStr::new("sh"),
        &[
            OsString::from("-c"),
            script.into(),
            OsString::from("adapter"),
            transcript.clone().into_os_string(),
        ],
        Limits::DEFAULT,
    );
    assert_eq!(run.exit_code(), 0, "{:?}", run.records);
    assert_eq!(
        serde_json::to_value(&run).unwrap()["testee"]["implementation"],
        "fixture"
    );
    let requests: Vec<serde_json::Value> = std::fs::read_to_string(&transcript)
        .unwrap()
        .lines()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect();
    assert_eq!(requests.len(), 2);
    for request in requests {
        assert_eq!(request["op"], "restore-local-library");
        assert_eq!(request["files"].as_array().unwrap().len(), 15);
        assert!(request.get("expected").is_none());
        assert!(request.get("caseId").is_none());
    }

    let wrong = replies[0].replace("1.2.0", "1.2.1");
    let script = format!(
        "read -r line; printf '%s\\n' '{caps}'; read -r line; printf '%s\\n' '{wrong}'; read -r line; printf '%s\\n' '{}'; read -r line; exit 0",
        replies[1]
    );
    let run = run_mvp_process(
        &inventory,
        std::ffi::OsStr::new("sh"),
        &[OsString::from("-c"), script.into()],
        Limits::DEFAULT,
    );
    let report = serde_json::to_value(&run).unwrap();
    assert_eq!(report["records"][0]["result"], "fail");
    assert_eq!(report["records"][1]["result"], "pass");
    assert_eq!(run.exit_code(), 1);

    let mut wrong_output: serde_json::Value = serde_json::from_str(&replies[0]).unwrap();
    wrong_output["outputFiles"][0]["sha256"] = format!("sha256:{}", "0".repeat(64)).into();
    for (first, second, failing_index) in [
        (wrong_output.to_string(), replies[1].clone(), 0),
        (
            replies[0].clone(),
            replies[1].replace("timestamp-signature-threshold", "timestamp-expired"),
            1,
        ),
    ] {
        let script = format!(
            "read -r line; printf '%s\\n' '{caps}'; read -r line; printf '%s\\n' '{first}'; read -r line; printf '%s\\n' '{second}'; read -r line; exit 0"
        );
        let run = run_mvp_process(
            &inventory,
            std::ffi::OsStr::new("sh"),
            &[OsString::from("-c"), script.into()],
            Limits::DEFAULT,
        );
        let report = serde_json::to_value(&run).unwrap();
        assert_eq!(report["records"][failing_index]["result"], "fail");
        assert_eq!(run.exit_code(), 1);
    }
}

#[test]
fn adapter_disappearing_after_one_case_keeps_the_required_denominator() {
    let inventory = inventory();
    let caps = r#"{"id":1,"suite":"package","contractVersion":"0.1.0-draft.3","implementation":"fixture","implementationVersion":"1","profiles":["local-library-mvp:0.1.0-draft.1"],"operations":["restore-local-library"]}"#;
    let mut first: serde_json::Value =
        serde_json::from_slice(inventory.cases()[0].expected()).unwrap();
    first["id"] = serde_json::json!(2);
    let script = format!(
        "read -r line; printf '%s\\n' '{caps}'; read -r line; printf '%s\\n' '{first}'; exit 0"
    );
    let run = run_mvp_process(
        &inventory,
        std::ffi::OsStr::new("sh"),
        &[OsString::from("-c"), script.into()],
        Limits::DEFAULT,
    );
    let report = serde_json::to_value(&run).unwrap();
    assert_eq!(report["records"].as_array().unwrap().len(), 2);
    assert_eq!(report["records"][0]["result"], "pass");
    assert_eq!(report["records"][1]["result"], "kit-error");
    assert_eq!(run.exit_code(), 1);
}
