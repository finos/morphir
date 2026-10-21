//! Historical actual52 DATA. No runtime, process or source authority is issued.
use super::*;
use crate::workbench::model_originals::workflow::{
    Decode, installed_measurements::InstalledClientMeasurements,
};
use crate::workbench::{Report, RunConfiguration, check_report_configured};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
mod partial;
mod release_connection;
mod structure;

const NODE: &str = include_str!("consumer_operation_controls/node-healthy.json");
const NATIVE: &str = include_str!("consumer_operation_controls/native-healthy.json");
const CONFIGURATION: &str =
    include_str!("consumer_operation_controls/checker-policy-operation.json");
const MEASUREMENT: &str = "/records/0/evidence/measurement";
fn genuine(raw: &str, expected: &str) -> Value {
    let hash: String = Sha256::digest(raw.as_bytes())
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect();
    assert_eq!(hash, expected, "byte-exact actual exported report");
    let value: Value = serde_json::from_str(raw).unwrap();
    assert_eq!(value["formatVersion"], "0.1.0-draft.31");
    assert_eq!(value["qualified"], false);
    assert_eq!(value["records"].as_array().unwrap().len(), 24);
    value
}
fn node() -> Value {
    genuine(
        NODE,
        "ee208b3a2c06f75027c71d459dc84c5ec65c7beaf105b16a74609f192b20a45e",
    )
}
fn native() -> Value {
    genuine(
        NATIVE,
        "bda106175f704b1c041eda815babaa3e02875004960fced6a1c7c1c86b8db950",
    )
}
fn evaluate(report: &Value) -> ObservationError {
    let source = source(CORPUS);
    let configuration: Value = serde_json::from_str(CONFIGURATION).unwrap();
    let policy = policy(&configuration["checker"].to_string());
    let raw = report.pointer(MEASUREMENT).unwrap().to_string();
    let mut cause = None;
    prepared_installed_client(
        &source,
        &policy,
        ReviewedSources::installed_client_selected(),
        |inventory, owners| {
            assert_eq!(inventory.len(), 24);
            let document = owners.decode.literal_with_raw(&raw).unwrap().0;
            let actual =
                InstalledClientMeasurements::decode_consumer(&document, &mut owners.decode)
                    .expect("mutation preserves the strict draft31 measurement shape");
            cause = Some(
                inventory
                    .invocation()
                    .compiled_source()
                    .report_context()
                    .check_installed_process(&actual, &mut owners.comparison)
                    .expect_err("whole source set remains explicitly blocked"),
            );
            Ok(())
        },
    )
    .unwrap();
    cause.unwrap()
}
fn exact(report: &Value, expected: &str) {
    assert_eq!(
        format!("{:?}", evaluate(report)),
        expected,
        "precise SAME checker cause"
    );
}
fn measurement(value: &mut Value) -> &mut Value {
    value.pointer_mut(MEASUREMENT).unwrap()
}
fn record(value: &mut Value) -> &mut Value {
    &mut measurement(value)["consumerObservation"]
}
fn coherent_fact(report: &mut Value, kind: &str, field: &str, value: Value) {
    let measured = measurement(report);
    let dynamic = match kind {
        "release-accepted" => "clientReleaseAcceptance",
        "destination-commit-finished" => "dynamicCommit",
        "scratch-cleanup-finished" => "dynamicScratchCleanup",
        _ => panic!("closed test kind"),
    };
    measured[dynamic][field] = value.clone();
    let mut found = 0;
    for endpoint in measured["consumerObservation"]["endpoints"]
        .as_array_mut()
        .unwrap()
    {
        for row in endpoint["frames"].as_array_mut().unwrap() {
            let mut body: Value = serde_json::from_str(row["literal"].as_str().unwrap()).unwrap();
            if body["kind"] == "fact" && body["fact"]["kind"] == kind {
                body["fact"][field] = value.clone();
                row["literal"] = body.to_string().into();
                found += 1;
            }
        }
    }
    assert_eq!(
        found, 1,
        "one genuine fact, projection changes with literal"
    );
}
#[test]
fn actual52_node_record_reaches_original_expected_blocked() {
    exact(&node(), "ExpectedBlocked");
}
#[test]
fn actual52_native_record_reaches_original_expected_blocked() {
    exact(&native(), "ExpectedBlocked");
}
#[test]
fn consumer_foreign_process_has_exact_association_fault() {
    let mut report = node();
    record(&mut report)["association"]["processOrdinal"] = json!(u64::MAX);
    exact(&report, "InstalledClient(ConsumerAssociation)");
}
#[test]
fn consumer_wrong_publish_action_has_exact_association_fault() {
    let mut report = node();
    record(&mut report)["association"]["actionIndex"] = json!(5);
    exact(&report, "InstalledClient(ConsumerAssociation)");
}
#[test]
fn consumer_wrong_clock_interval_has_exact_clock_fault() {
    let mut report = node();
    record(&mut report)["clock"]["endNs"] = json!("0");
    exact(&report, "InstalledClient(ConsumerClock)");
}
#[test]
fn logical_close_is_not_physical_terminal_drain() {
    let mut report = node();
    record(&mut report)["endpoints"][0]["terminal"] = json!({"kind":"close-ack-written"});
    exact(&report, "InstalledClient(ConsumerTranscript)");
}
#[test]
fn healthy_record_requires_every_ack_delivery_complete() {
    let mut report = node();
    record(&mut report)["endpoints"][0]["frames"][0]["delivery"] =
        json!({"kind":"prefix","written":0,"total":62});
    exact(&report, "InstalledClient(ConsumerTranscript)");
}
#[test]
fn coherent_release_request_hash_still_requires_actual_host_prefix() {
    let mut report = node();
    coherent_fact(
        &mut report,
        "release-accepted",
        "requestSha256",
        json!("0".repeat(64)),
    );
    exact(&report, "InstalledClient(ConsumerRelease)");
}
#[test]
fn coherent_release_reply_hash_still_requires_actual_host_prefix() {
    let mut report = node();
    coherent_fact(
        &mut report,
        "release-accepted",
        "replySha256",
        json!("0".repeat(64)),
    );
    exact(&report, "InstalledClient(ConsumerRelease)");
}
#[test]
fn coherent_returned_commit_still_requires_selected_destination() {
    let mut report = node();
    coherent_fact(
        &mut report,
        "destination-commit-finished",
        "path",
        json!({"kind":"unix-bytes","bytes":{"kind":"utf8","text":"destination/foreign"}}),
    );
    exact(&report, "InstalledClient(ConsumerCommit)");
}
#[test]
fn coherent_returned_cleanup_still_requires_actual_scratch_root() {
    let mut report = node();
    coherent_fact(
        &mut report,
        "scratch-cleanup-finished",
        "path",
        json!({"kind":"unix-bytes","bytes":{"kind":"utf8","text":"/foreign/scratch"}}),
    );
    exact(&report, "InstalledClient(ConsumerCleanup)");
}
#[test]
fn partial_actual_reports_replay_as_failed_prefixes_only() {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"), CORPUS).unwrap();
    let configuration = RunConfiguration::from_json(CONFIGURATION).unwrap();
    for (raw, hash) in [
        (
            include_str!("consumer_operation_controls/node-release-ack-loss.json"),
            "bffb37b6617943a773f25e791da7f7bd3603d4d384e9c4bc8919bc9a8f775927",
        ),
        (
            include_str!("consumer_operation_controls/node-commit-ack-loss.json"),
            "70f82c1b0ade7953500fd85632193273b2853d357f53fc80497e826f3bd2c6d1",
        ),
        (
            include_str!("consumer_operation_controls/native-release-ack-loss.json"),
            "c2dfa3fae80639b98f829bffe815fc10e75ad05313351972bf245862db738073",
        ),
        (
            include_str!("consumer_operation_controls/native-commit-ack-loss.json"),
            "486287f50c3a74a1d8e6a6b47e152e97b7cec3a647ce03c7e96038919fd68960",
        ),
    ] {
        let value = genuine(raw, hash);
        assert_eq!(value["errors"][0]["code"], "io");
        assert_eq!(
            value["records"][0]["evidence"]["consumerFailure"]["context"]["kind"],
            "prefix"
        );
        check_report_configured(
            root.path(),
            &Report::from_json(raw).unwrap(),
            &configuration,
        )
        .expect("genuine failed prefix integrity, without successful qualification");
    }
}
