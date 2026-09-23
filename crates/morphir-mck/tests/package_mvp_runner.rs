#![cfg(unix)]
use morphir_mck::package::local_registry::{
    AdmittedMvpInventory, MvpRepositorySource, admit_mvp_inventory,
};
use morphir_mck::package::run_mvp_process;
use morphir_mck::transport::Limits;
use serde_json::{Value, json};
use std::{ffi::OsString, path::Path};

const CAPS: &str = r#"{"id":1,"suite":"package","contractVersion":"0.1.0-draft.3","implementation":"fixture","implementationVersion":"1","profiles":["local-library-mvp:0.1.0-draft.1"],"operations":["restore-local-library"]}"#;

fn inventory() -> AdmittedMvpInventory {
    let source =
        MvpRepositorySource::new(Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")).unwrap();
    admit_mvp_inventory(&source).unwrap()
}

fn fixed_replies(inventory: &AdmittedMvpInventory) -> Vec<Value> {
    inventory
        .cases()
        .iter()
        .enumerate()
        .map(|(index, case)| {
            let mut value: Value = serde_json::from_slice(case.expected()).unwrap();
            value["id"] = json!(index + 2);
            value
        })
        .collect()
}

fn run_replies(inventory: &AdmittedMvpInventory, replies: &[Value]) -> (Value, Vec<Value>) {
    let temp = tempfile::tempdir().unwrap();
    let transcript = temp.path().join("request.jsonl");
    let response_file = temp.path().join("responses.jsonl");
    let bytes = replies
        .iter()
        .map(Value::to_string)
        .collect::<Vec<_>>()
        .join("\n")
        + "\n";
    std::fs::write(&response_file, bytes).unwrap();
    let script = format!(
        "exec 3<\"$2\"; read -r line; printf '%s\\n' '{CAPS}'; while IFS= read -r reply <&3; do IFS= read -r line; printf '%s\\n' \"$line\" >> \"$1\"; printf '%s\\n' \"$reply\"; done; read -r line; exit 0"
    );
    let run = run_mvp_process(
        inventory,
        std::ffi::OsStr::new("sh"),
        &[
            OsString::from("-c"),
            script.into(),
            OsString::from("adapter"),
            transcript.clone().into_os_string(),
            response_file.into_os_string(),
        ],
        Limits::DEFAULT,
    );
    let report = serde_json::to_value(&run).unwrap();
    let requests = std::fs::read_to_string(&transcript)
        .unwrap()
        .lines()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect();
    (report, requests)
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
    assert_eq!(report["records"].as_array().unwrap().len(), 15);
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
fn all_fixed_results_pass_over_input_only_transcript_and_wrong_results_fail() {
    let inventory = inventory();
    let replies = fixed_replies(&inventory);
    let (report, requests) = run_replies(&inventory, &replies);
    assert_eq!(report["records"].as_array().unwrap().len(), 15);
    assert!(
        report["records"]
            .as_array()
            .unwrap()
            .iter()
            .all(|record| record["result"] == "pass"),
        "{report}"
    );
    assert_eq!(report["testee"]["implementation"], "fixture");
    assert_eq!(report["scope"], "fresh-exact-lock-restore");
    assert_eq!(requests.len(), 15);
    for request in requests {
        assert_eq!(request["op"], "restore-local-library");
        assert!((15..=16).contains(&request["files"].as_array().unwrap().len()));
        assert!(request.get("environment").is_some());
        assert!(request.get("expected").is_none());
        assert!(request.get("caseId").is_none());
    }

    let mut wrong = replies.clone();
    wrong[0]["packages"][0]["version"] = json!("1.2.1");
    wrong[6]["outputFiles"][0]["sha256"] = json!(format!("sha256:{}", "0".repeat(64)));
    let (report, _) = run_replies(&inventory, &wrong);
    assert_eq!(report["records"].as_array().unwrap().len(), 15);
    for (index, record) in report["records"].as_array().unwrap().iter().enumerate() {
        let expected = if index == 0 || index == 6 {
            "fail"
        } else {
            "pass"
        };
        assert_eq!(record["result"], expected, "record {index}: {record}");
    }
}

#[test]
fn adapter_disappearing_after_one_case_keeps_the_required_denominator() {
    let inventory = inventory();
    let first = fixed_replies(&inventory).remove(0);
    let script = format!(
        "read -r line; printf '%s\\n' '{CAPS}'; read -r line; printf '%s\\n' '{first}'; exit 0"
    );
    let run = run_mvp_process(
        &inventory,
        std::ffi::OsStr::new("sh"),
        &[OsString::from("-c"), script.into()],
        Limits::DEFAULT,
    );
    let report = serde_json::to_value(&run).unwrap();
    assert_eq!(report["records"].as_array().unwrap().len(), 15);
    assert_eq!(report["records"][0]["result"], "pass");
    assert!(
        report["records"]
            .as_array()
            .unwrap()
            .iter()
            .skip(1)
            .all(|record| record["result"] == "kit-error")
    );
    assert_eq!(run.exit_code(), 1);
}
