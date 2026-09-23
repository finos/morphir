#![cfg(unix)]
use morphir_mck::package::local_registry::{
    AdmittedMvpInventory, MvpRepositorySource, admit_mvp_inventory,
};
use morphir_mck::package::{MvpRun, run_mvp_process};
use morphir_mck::transport::Limits;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{ffi::OsString, path::Path};

const CAPS: &str = r#"{"id":1,"suite":"package","contractVersion":"0.1.0-draft.3","implementation":"fixture","implementationVersion":"1","profiles":["local-library-mvp:0.1.0-draft.1"],"operations":["restore-local-library","resolve-local-library","refresh-local-library","update-local-library"]}"#;

fn inventory() -> AdmittedMvpInventory {
    let source =
        MvpRepositorySource::new(Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")).unwrap();
    admit_mvp_inventory(&source).unwrap()
}

#[test]
fn generated_lock_is_a_required_restore_input() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let generated = std::fs::read(
        root.join("spec/package/mck/fixtures/mvp-fresh-restore/expected/resolve.lock.json"),
    )
    .unwrap();
    let admitted = inventory();
    let replay = admitted
        .cases()
        .iter()
        .find(|case| case.id() == "mvp.restore.generated-lock-replay")
        .expect("generated-lock replay must be a required case");
    assert_eq!(replay.operation(), "restore");
    assert_eq!(replay.inputs().get("morphir.lock"), Some(&generated));
    let resolved = admitted
        .cases()
        .iter()
        .find(|case| case.id() == "mvp.resolve.fresh-two-libraries")
        .unwrap();
    let expected: Value = serde_json::from_slice(resolved.expected()).unwrap();
    let digest: String = Sha256::digest(&generated)
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect();
    assert_eq!(
        expected["outputFiles"][0]["sha256"],
        format!("sha256:{digest}")
    );
}

#[test]
fn frozen_initial_resolve_cases_are_required_by_the_public_mvp_inventory() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let frozen: Value = serde_json::from_slice(
        &std::fs::read(root.join("spec/package/mck/fixtures/mvp-fresh-restore/resolve-cases.json"))
            .unwrap(),
    )
    .unwrap();
    let admitted = inventory();
    let ids = admitted
        .cases()
        .iter()
        .map(|case| case.id())
        .collect::<std::collections::BTreeSet<_>>();
    let expected = frozen["cases"].as_array().unwrap();
    assert_eq!(expected.len(), 13);
    for case in expected {
        let id = case["id"].as_str().unwrap();
        assert!(ids.contains(id), "missing required resolve case: {id}");
    }
    assert_eq!(ids.len(), 70);
}

#[test]
fn frozen_metadata_only_refresh_cases_are_required_by_the_public_mvp_inventory() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let frozen: Value = serde_json::from_slice(
        &std::fs::read(root.join("spec/package/mck/fixtures/mvp-fresh-restore/refresh-cases.json"))
            .unwrap(),
    )
    .unwrap();
    let admitted = inventory();
    let ids = admitted
        .cases()
        .iter()
        .map(|case| case.id())
        .collect::<std::collections::BTreeSet<_>>();
    let expected = frozen["cases"].as_array().unwrap();
    assert_eq!(expected.len(), 14);
    for case in expected {
        let id = case["id"].as_str().unwrap();
        assert!(ids.contains(id), "missing required refresh case: {id}");
    }
    assert_eq!(ids.len(), 70);
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
    assert_eq!(report["records"].as_array().unwrap().len(), 70);
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
    assert_eq!(report["records"].as_array().unwrap().len(), 70);
    assert!(
        report["records"]
            .as_array()
            .unwrap()
            .iter()
            .all(|record| record["result"] == "pass"),
        "{report}"
    );
    assert_eq!(report["testee"]["implementation"], "fixture");
    assert_eq!(report["scope"], "fresh-local-library-workflow");
    assert_eq!(requests.len(), 70);
    for (index, request) in requests.into_iter().enumerate() {
        assert_eq!(
            request["op"],
            if index < 16 {
                "restore-local-library"
            } else if index < 29 {
                "resolve-local-library"
            } else if index < 43 {
                "refresh-local-library"
            } else {
                "update-local-library"
            }
        );
        if (16..29).contains(&index) {
            assert!(
                request["exactRoot"]
                    .as_str()
                    .unwrap()
                    .starts_with("example.com/finance/loan-rules@")
            );
        }
        assert!((7..=50).contains(&request["files"].as_array().unwrap().len()));
        assert_eq!(request.get("targets").is_some(), index >= 43);
        assert!(request.get("environment").is_some());
        assert!(request.get("expected").is_none());
        assert!(request.get("caseId").is_none());
    }

    let mut wrong = replies.clone();
    wrong[0]["packages"][0]["version"] = json!("1.2.1");
    wrong[6]["outputFiles"][0]["sha256"] = json!(format!("sha256:{}", "0".repeat(64)));
    wrong[29]["receipt"]["timestampDigest"] = json!(format!("sha256:{}", "0".repeat(64)));
    wrong[43]["outputFiles"][0]["sha256"] = json!(format!("sha256:{}", "0".repeat(64)));
    let (report, _) = run_replies(&inventory, &wrong);
    assert_eq!(report["records"].as_array().unwrap().len(), 70);
    for (index, record) in report["records"].as_array().unwrap().iter().enumerate() {
        let expected = if index == 0 || index == 6 || index == 29 || index == 43 {
            "fail"
        } else {
            "pass"
        };
        assert_eq!(record["result"], expected, "record {index}: {record}");
    }
}

#[test]
fn versioned_mvp_report_checks_the_independent_inventory() {
    let inventory = inventory();
    let (report, _) = run_replies(&inventory, &fixed_replies(&inventory));
    assert_eq!(report["contractVersion"], "0.1.0-draft.1");
    assert_eq!(report["suite"], "package");
    assert!(report["startedAt"].is_string());
    assert!(report["driver"]["version"].is_string());
    assert!(report["adapter"]["command"].is_array());
    assert_eq!(report["selection"]["kind"], "all");

    let parsed = MvpRun::from_json(&report.to_string()).unwrap();
    assert_eq!(parsed.check_inventory(&inventory).unwrap(), 70);

    let mut missing = report.clone();
    missing["records"].as_array_mut().unwrap().pop();
    assert!(
        MvpRun::from_json(&missing.to_string())
            .unwrap()
            .check_inventory(&inventory)
            .is_err()
    );

    let mut extra = report.clone();
    let duplicate = extra["records"][0].clone();
    extra["records"].as_array_mut().unwrap().push(duplicate);
    assert!(
        MvpRun::from_json(&extra.to_string())
            .unwrap()
            .check_inventory(&inventory)
            .is_err()
    );

    let mut wrong_hash = report.clone();
    wrong_hash["kitHash"] = json!(format!("sha256:{}", "0".repeat(64)));
    assert!(
        MvpRun::from_json(&wrong_hash.to_string())
            .unwrap()
            .check_inventory(&inventory)
            .is_err()
    );

    let (mut wrong_capabilities, _) = run_replies(&inventory, &fixed_replies(&inventory));
    wrong_capabilities["testee"]["operations"][0] = json!("not-an-operation");
    assert!(
        MvpRun::from_json(&wrong_capabilities.to_string())
            .unwrap()
            .check_inventory(&inventory)
            .is_err()
    );

    let mut bad_context = report.clone();
    bad_context["startedAt"] = json!("yesterday");
    assert!(MvpRun::from_json(&bad_context.to_string()).is_err());
    bad_context["startedAt"] = report["startedAt"].clone();
    bad_context["adapter"]["command"] = json!([""]);
    assert!(MvpRun::from_json(&bad_context.to_string()).is_err());
}

#[test]
fn mvp_html_is_offline_and_escapes_failure_text() {
    let inventory = inventory();
    let (mut report, _) = run_replies(&inventory, &fixed_replies(&inventory));
    report["records"][0]["result"] = json!("fail");
    report["records"][0]["message"] = json!("<script>alert('x')</script>");
    let parsed = MvpRun::from_json(&report.to_string()).unwrap();
    let html = parsed.render_html();
    assert!(html.contains("MVP local Library report"));
    assert!(html.contains("70 required cases"));
    assert!(html.contains("&lt;script&gt;"));
    assert!(!html.contains("<script>alert('x')</script>"));
    assert!(!html.contains("https://"));
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
    assert_eq!(report["records"].as_array().unwrap().len(), 70);
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
