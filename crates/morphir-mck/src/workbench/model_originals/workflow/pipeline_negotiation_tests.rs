//! Source-authored R1/R2 controls. Partial23 never grants qualification.
use crate::transport::{Limits, Session};
use crate::workbench::{
    Report, RunConfiguration, check_report_configured, load, run_with_session_configured,
};
use serde::{Deserialize, Serialize};
use serde_json::value::RawValue;
use std::ffi::OsString;
use std::path::Path;

const OLD: &str = include_str!("pipeline_controls/honest-unqualified-report.json");
const NEW: &str =
    include_str!("pipeline_negotiation_controls/honest-unqualified-negotiated-report.json");
const CAPS_SENT: &str = include_str!("pipeline_controls/capabilities-request.payload.json");
const CAPS_RECEIVED: &str = include_str!("pipeline_controls/capabilities-reply.payload.json");

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Saved {
    format_version: Box<RawValue>,
    suite: Box<RawValue>,
    corpus_hash: Box<RawValue>,
    capabilities: Box<RawValue>,
    records: Vec<Box<RawValue>>,
    errors: Box<RawValue>,
    qualified: Box<RawValue>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    negotiation: Option<Box<RawValue>>,
}
#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Negotiation {
    sent_payload: String,
    received_payload: String,
}

fn policy() -> RunConfiguration {
    RunConfiguration::from_json(include_str!("pipeline_controls/explicit-test-policy.json"))
        .unwrap()
}
fn kit(root: &Path) {
    std::fs::write(
        root.join("cases.json"),
        include_bytes!("pipeline_controls/cases.json"),
    )
    .unwrap();
}
fn replay(root: &Path, raw: &str, configuration: &RunConfiguration) -> Result<(), String> {
    let report = Report::from_json(raw)?;
    check_report_configured(root, &report, configuration)
}
fn live(root: &Path, configuration: &RunConfiguration) -> Report {
    let corpus = load(root).unwrap();
    assert_eq!(corpus.case_count(), 23);
    let peer = std::env::var_os("MORPHIR_MCK_REPORT_PEER_BIN")
        .expect("actual existing compiled MEP harness");
    let session = Session::spawn_mep(
        &peer,
        &[
            OsString::from("--adapter"),
            OsString::from("workflow-pipeline-blocked23"),
        ],
        Limits::DEFAULT,
    )
    .unwrap();
    run_with_session_configured(&corpus, session, configuration).unwrap()
}
fn refused(root: &Path, raw: &str, configuration: &RunConfiguration, phase: &str) {
    let result = replay(root, raw, configuration);
    assert!(result.is_err(), "forged/missing evidence accepted: {phase}");
    let error = result.unwrap_err();
    assert!(
        error.contains(phase),
        "wrong refusal boundary, expected {phase}: {error}"
    );
}

#[test]
fn required_negotiation_has_no_legacy_saved_report_downgrade() {
    let temp = tempfile::tempdir().unwrap();
    kit(temp.path());
    let current = replay(temp.path(), OLD, &policy());
    eprintln!("legacy missing-negotiation replay actual result: {current:?}");
    assert!(
        current.is_err(),
        "old report omits actual negotiation but was accepted"
    );
    assert!(current.unwrap_err().contains("negotiation"));
}

#[test]
fn negotiation_successor_keeps_all_original23_oracles_and_exact_payloads() {
    let old: Saved = serde_json::from_str(OLD).unwrap();
    let new: Saved = serde_json::from_str(NEW).unwrap();
    assert!(old.negotiation.is_none());
    assert_eq!(new.records.len(), 23);
    for (left, right) in old.records.iter().zip(&new.records) {
        assert_eq!(left.get(), right.get());
    }
    for (left, right) in [
        (&old.format_version, &new.format_version),
        (&old.suite, &new.suite),
        (&old.corpus_hash, &new.corpus_hash),
        (&old.capabilities, &new.capabilities),
        (&old.errors, &new.errors),
        (&old.qualified, &new.qualified),
    ] {
        assert_eq!(left.get(), right.get());
    }
    assert_eq!(new.qualified.get(), "false");
    let negotiation: Negotiation =
        serde_json::from_str(new.negotiation.as_ref().unwrap().get()).unwrap();
    assert_eq!(negotiation.sent_payload.as_bytes(), CAPS_SENT.as_bytes());
    assert_eq!(
        negotiation.received_payload.as_bytes(),
        CAPS_RECEIVED.as_bytes()
    );
    let temp = tempfile::tempdir().unwrap();
    kit(temp.path());
    replay(temp.path(), NEW, &policy())
        .expect("source-bound honest successor must replay its same ExpectedBlocked failure");
    assert!(!Report::from_json(NEW).unwrap().qualified());
}

#[test]
fn live_and_saved_capture_charge_the_same_negotiation_before_first_record() {
    assert_eq!(CAPS_SENT.len(), 83);
    assert_eq!(CAPS_RECEIVED.len(), 185);
    let first_sent = include_str!("pipeline_controls/first-request.payload.json");
    let first_received = include_str!("pipeline_controls/first-reply.payload.json");
    assert_eq!(first_sent.len(), 10765);
    assert_eq!(first_received.len(), 797);
    assert_eq!(
        83usize
            .checked_add(185)
            .unwrap()
            .checked_add(10765)
            .unwrap()
            .checked_add(797)
            .unwrap(),
        11830
    );
    let temp = tempfile::tempdir().unwrap();
    kit(temp.path());
    let low = RunConfiguration::from_json(include_str!(
        "pipeline_negotiation_controls/capture-aggregate-11562.json"
    ))
    .unwrap();
    let report = live(temp.path(), &low);
    let text = report.to_json();
    // Existing actual peer proves first request/reply and exit. Test-only view
    // extracts a bounded report summary; opaque literal payloads stay strings.
    let wire: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!(wire["errors"][0]["code"], "capture-refused");
    assert_eq!(wire["records"][0]["evidence"]["kind"], "attempt-failed");
    assert_eq!(wire["records"].as_array().unwrap().len(), 23);
    assert!(!report.qualified());
    eprintln!(
        "actual live aggregate11562: capture-refused; old saved same-policy result: {:?}",
        replay(temp.path(), OLD, &low)
    );
    refused(temp.path(), NEW, &low, "capture");
    let one_less = RunConfiguration::from_json(include_str!(
        "pipeline_negotiation_controls/capture-aggregate-11829.json"
    ))
    .unwrap();
    refused(temp.path(), NEW, &one_less, "capture");
    let exact = RunConfiguration::from_json(include_str!(
        "pipeline_negotiation_controls/capture-aggregate-11830.json"
    ))
    .unwrap();
    replay(temp.path(), NEW, &exact)
        .expect("exact11830 authorizes capability268 plus first11562, retaining ExpectedBlocked");
}

fn sequence(raw: &str) {
    let temp = tempfile::tempdir().unwrap();
    kit(temp.path());
    // This preserved diagnostic isolates CURRENT acceptance with the old wire;
    // the normative successor check below requires negotiation and schedule.
    let mut legacy: Saved = serde_json::from_str(raw).unwrap();
    legacy.negotiation = None;
    eprintln!(
        "legacy matching wrong-ID replay actual result: {:?}",
        replay(
            temp.path(),
            &serde_json::to_string(&legacy).unwrap(),
            &policy()
        )
    );
    refused(temp.path(), raw, &policy(), "sequence");
}
#[test]
fn first_case_cannot_reuse_negotiation_id_one() {
    sequence(include_str!(
        "pipeline_negotiation_controls/first-id-1.json"
    ));
}
#[test]
fn first_case_cannot_jump_to_matching_outer_id999() {
    sequence(include_str!(
        "pipeline_negotiation_controls/first-id-999.json"
    ));
}

#[test]
fn negotiation_evidence_is_required_and_closed() {
    let temp = tempfile::tempdir().unwrap();
    kit(temp.path());
    for raw in [
        include_str!("pipeline_negotiation_controls/extra-negotiation-field.json"),
        include_str!("pipeline_negotiation_controls/missing-negotiation-reply.json"),
        include_str!("pipeline_negotiation_controls/null-negotiation.json"),
        include_str!("pipeline_negotiation_controls/duplicate-negotiation.json"),
    ] {
        assert!(
            replay(temp.path(), raw, &policy()).is_err(),
            "malformed negotiation accepted"
        );
    }
}

#[test]
fn generic_record_component_keeps_arbitrary_canonical_positive_id_contract() {
    use super::observation_check::{CompareLimits, CompareOwner, ObservationError};
    use super::record_check::WorkflowRecordError;
    use crate::workbench::report::WorkflowExchangeRecord;
    super::record_boundary_support::with_v3(|context, decode| {
        for id in [1, 999] {
            let sent = include_str!("pipeline_controls/first-request.payload.json").replacen(
                "\"id\":2,",
                &format!("\"id\":{id},"),
                1,
            );
            let received = include_str!("pipeline_controls/first-reply.payload.json").replacen(
                "\"id\" : 2,",
                &format!("\"id\" : {id},"),
                1,
            );
            let record = WorkflowExchangeRecord::from_decoded_payloads(sent, received);
            let mut compare =
                CompareOwner::new(CompareLimits::new(100_000, 1_000_000, 100_000).unwrap());
            assert!(
                matches!(
                    context.check_record(&record, decode, &mut compare),
                    Err(WorkflowRecordError::Observation(
                        ObservationError::ExpectedBlocked
                    ))
                ),
                "generic component must not claim knowledge of Session schedule"
            );
        }
    });
}
