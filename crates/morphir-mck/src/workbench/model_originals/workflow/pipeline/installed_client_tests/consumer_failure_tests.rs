//! Byte-exact historical failure DATA from actual unhooked installed014 runs.
//! This does not recreate live process/port authority or successful business facts.
use super::*;
use crate::workbench::{Report, RunConfiguration, check_report_configured};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

const REPORT: &[u8] = include_bytes!("consumer_failure_controls/operation-report.json");
const CONFIGURATION: &[u8] = include_bytes!("consumer_failure_controls/operation-policy.json");
const REPORT_SHA: &str = "42b62a4d4818f224e661fce517ff529fad0443efbabb5ef1bc5a296e74fa582a";
const CONFIGURATION_SHA: &str = "b1053606dc2dcfe71889213260e92f4896c469487d9c3004c029f57542454cb8";
fn digest(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}
fn input() -> (Value, Value) {
    assert_eq!(digest(REPORT), REPORT_SHA);
    assert_eq!(digest(CONFIGURATION), CONFIGURATION_SHA);
    assert_eq!(
        digest(CORPUS.as_bytes()),
        "26559149b6a1e67e13a4e59422ebf5e22f399799f3f28eba0b20c7002919e26e"
    );
    let report: Value = serde_json::from_slice(REPORT).unwrap();
    assert_eq!(report["qualified"], false);
    assert_eq!(
        report["errors"],
        json!([{"phase":"installed-consumer","code":"framing","message":"private consumer operation transport refused"}])
    );
    assert_eq!(report["records"].as_array().unwrap().len(), 24);
    assert_eq!(
        report["records"][0]["evidence"],
        json!({"kind":"attempt-failed","failureIndex":0})
    );
    for row in &report["records"].as_array().unwrap()[1..] {
        assert_eq!(
            row["evidence"],
            json!({"kind":"not-attempted","priorFailureIndex":0})
        );
    }
    (report, serde_json::from_slice(CONFIGURATION).unwrap())
}
fn replay(report: &Value, configuration: &Value) -> Result<(), String> {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"), CORPUS).unwrap();
    let report = Report::from_json(&report.to_string())?;
    let configuration = RunConfiguration::from_json(&configuration.to_string())?;
    check_report_configured(root.path(), &report, &configuration)
}
#[test]
fn actual_operation_failure_replays_as_unqualified_closed_failure_data_only() {
    let (report, configuration) = input();
    replay(&report, &configuration)
        .expect("actual recorded framing failure is valid unqualified failure DATA");
}
#[test]
fn consumer_failure_requires_explicit_operation_selection() {
    let (report, mut configuration) = input();
    configuration
        .as_object_mut()
        .unwrap()
        .remove("consumerObservation");
    assert_eq!(
        replay(&report, &configuration).unwrap_err(),
        "unverified incomplete installed attempt category"
    );
}
#[test]
fn unknown_or_inexact_consumer_failure_strings_do_not_replay() {
    let (original, configuration) = input();
    for (key, value) in [
        ("phase", "installed-consumer-other"),
        ("code", "imagined-success"),
        ("code", "Framing"),
        ("message", "transport refused"),
    ] {
        let mut report = original.clone();
        report["errors"][0][key] = json!(value);
        assert_eq!(
            replay(&report, &configuration).unwrap_err(),
            "unverified incomplete installed attempt category",
            "{key}={value}"
        );
    }
}
#[test]
fn consumer_failure_cannot_qualify_the_report() {
    let (mut report, configuration) = input();
    report["qualified"] = json!(true);
    assert_eq!(
        replay(&report, &configuration).unwrap_err(),
        "forged qualified claim for partial/unproven source set"
    );
}
#[test]
fn consumer_failure_preserves_first_failure_prefix_and_exact_single_error() {
    let (original, configuration) = input();
    for evidence in [
        json!({"kind":"attempt-failed","failureIndex":0}),
        json!({"kind":"not-attempted","priorFailureIndex":1}),
    ] {
        let mut report = original.clone();
        report["records"][1]["evidence"] = evidence;
        assert_eq!(
            replay(&report, &configuration).unwrap_err(),
            "evidence after first failure"
        );
    }
    let mut report = original;
    let duplicate = report["errors"][0].clone();
    report["errors"].as_array_mut().unwrap().push(duplicate);
    assert_eq!(
        replay(&report, &configuration).unwrap_err(),
        "saved first failure differs"
    );
}
#[test]
fn consumer_failure_does_not_replace_missing_first_attempt_or_inventory() {
    let (original, configuration) = input();
    let mut report = original.clone();
    report["records"][0]["evidence"] = json!({"kind":"not-attempted","priorFailureIndex":0});
    assert_eq!(
        replay(&report, &configuration).unwrap_err(),
        "installed factual evidence missing"
    );
    let mut report = original;
    report["records"][0]["caseId"] = json!("foreign-case");
    assert_eq!(
        replay(&report, &configuration).unwrap_err(),
        "inventory execution key/order differs"
    );
}

mod report_revision_tests;
