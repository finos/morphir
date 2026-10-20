//! Prospective actual shared Workbench entrypoint controls. No alternate checker.
//! Frozen before the configuration/facade implementation. The full23 subset is
//! partial; original175 role executions and complete proofs remain mandatory.
use crate::transport::{Limits, Session};
use crate::workbench::{
    Report, RunConfiguration, RunOptions, check_report_configured, load, run_configured,
    run_with_session_configured,
};
use serde::{Deserialize, Serialize};
use serde_json::value::RawValue;
use std::ffi::OsString;
use std::path::Path;

// Mutation helper only. All top-level operands except the records array remain
// exact RawValue tokens; records retain raw payload strings and exact lexemes.
// It never decides validity or provides source/compiler/checking authority.
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SavedWire {
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
struct RecordSnapshot {
    case_id: String,
    execution: Box<RawValue>,
    evidence: EvidenceSnapshot,
}
#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case", deny_unknown_fields)]
enum EvidenceSnapshot {
    Captured {
        exchange: Payloads,
        verdict: VerdictSnapshot,
    },
    AttemptFailed {
        #[serde(rename = "failureIndex")]
        failure_index: usize,
    },
    NotAttempted {
        #[serde(rename = "priorFailureIndex")]
        prior_failure_index: usize,
    },
}
#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Payloads {
    sent_payload: String,
    received_payload: String,
}
#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "kebab-case", deny_unknown_fields)]
enum VerdictSnapshot {
    Checked,
    Failed {
        #[serde(rename = "failureIndex")]
        failure_index: usize,
    },
}

fn configuration() -> RunConfiguration {
    RunConfiguration::from_json(include_str!("pipeline_controls/explicit-test-policy.json"))
        .expect("explicit caller policy; never corpus/peer/default policy")
}

fn put_kit(path: &Path, bytes: &[u8]) {
    std::fs::create_dir_all(path).unwrap();
    std::fs::write(path.join("cases.json"), bytes).unwrap();
}

fn honest_report(root: &Path) -> Report {
    put_kit(root, include_bytes!("pipeline_controls/cases.json"));
    let corpus = load(root).unwrap();
    assert_eq!(
        corpus.case_count(),
        23,
        "no accepted prefix or easier two-row kit"
    );
    let peer = std::env::var_os("MORPHIR_MCK_REPORT_PEER_BIN")
        .expect("root provides the actual compiled existing MEP harness");
    let session = Session::spawn_mep(
        &peer,
        &[
            OsString::from("--adapter"),
            OsString::from("workflow-pipeline-blocked23"),
        ],
        Limits::DEFAULT,
    )
    .unwrap();
    run_with_session_configured(&corpus, session, &configuration()).unwrap()
}

#[test]
fn selected_shared_load_run_report_and_saved_check_keep_full23_and_same_blocked_source() {
    let temp = tempfile::tempdir().unwrap();
    let report = honest_report(temp.path());
    assert!(
        !report.qualified(),
        "partial23/unproven/blocked cannot qualify"
    );
    let saved = report.to_json();
    let wire: SavedWire = serde_json::from_str(&saved).unwrap();
    assert_eq!(wire.records.len(), 23);
    assert_eq!(wire.qualified.get(), "false");
    let expected: SavedWire = serde_json::from_str(include_str!(
        "pipeline_controls/honest-unqualified-report.json"
    ))
    .unwrap();
    assert_eq!(
        wire.corpus_hash.get(),
        expected.corpus_hash.get(),
        "whole actual corpus bytes, not input token digest"
    );
    assert_eq!(
        wire.errors.get(),
        expected.errors.get(),
        "real first ExpectedBlocked retained; shutdown must not add a peer failure"
    );
    for (index, raw) in wire.records.iter().enumerate() {
        let actual: RecordSnapshot = serde_json::from_str(raw.get()).unwrap();
        let fixed: RecordSnapshot = serde_json::from_str(expected.records[index].get()).unwrap();
        assert_eq!(actual.case_id, fixed.case_id);
        // Key tokens may use different harmless object member ordering. Decode
        // only these fixed key tuples as literals, never source input/observed.
        #[derive(Deserialize, PartialEq, Debug)]
        #[serde(rename_all = "camelCase", deny_unknown_fields)]
        struct Key {
            origin: Origin,
            role: String,
            run_index: usize,
        }
        #[derive(Deserialize, PartialEq, Debug)]
        #[serde(deny_unknown_fields)]
        struct Origin {
            packet: String,
            sha256: String,
            id: String,
        }
        assert_eq!(
            serde_json::from_str::<Key>(actual.execution.get()).unwrap(),
            serde_json::from_str::<Key>(fixed.execution.get()).unwrap()
        );
        match (index, actual.evidence) {
            (
                0,
                EvidenceSnapshot::Captured {
                    exchange,
                    verdict: VerdictSnapshot::Failed { failure_index: 0 },
                },
            ) => {
                assert_eq!(
                    exchange.sent_payload.as_bytes(),
                    include_bytes!("pipeline_controls/first-request.payload.json")
                );
                assert_eq!(
                    exchange.received_payload.as_bytes(),
                    include_bytes!("pipeline_controls/first-reply.payload.json")
                );
                assert!(
                    exchange.received_payload.contains("0e0"),
                    "raw number preserved inside exact retained reply"
                );
            }
            (
                1..,
                EvidenceSnapshot::NotAttempted {
                    prior_failure_index: 0,
                },
            ) => {}
            _ => panic!("first fault must stop every later row without a fabricated exchange"),
        }
    }
    // Success here means the saved failure report is consistent, not qualified.
    let restored = Report::from_json(&saved).unwrap();
    check_report_configured(temp.path(), &restored, &configuration()).unwrap();
    assert!(!restored.qualified());
    // Existing historical checker has no implicit selected checker policy.
    assert!(crate::workbench::check_report(temp.path(), &restored).is_err());
}

fn rejected(root: &Path, wire: &SavedWire, boundary: &str) {
    // Each forgery is an explicitly independent top-level replay attempt.
    // No failed attempt or its owners are reset inside a selected inventory.
    let text = serde_json::to_string(wire).unwrap();
    let loaded = Report::from_json(&text).unwrap();
    let error = check_report_configured(root, &loaded, &configuration()).unwrap_err();
    assert!(error.to_string().contains(boundary), "wrong phase: {error}");
}

#[test]
fn selected_saved_shared_inventory_hash_order_and_qualification_are_recomputed() {
    let temp = tempfile::tempdir().unwrap();
    let report = honest_report(temp.path());
    let saved = report.to_json();
    let mut wire: SavedWire = serde_json::from_str(&saved).unwrap();
    let missing = wire.records.remove(22);
    rejected(temp.path(), &wire, "inventory");
    wire.records.push(missing);
    let duplicate = RawValue::from_string(wire.records[0].get().to_owned()).unwrap();
    wire.records.push(duplicate);
    rejected(temp.path(), &wire, "inventory");
    wire.records.pop();
    wire.records.swap(0, 1);
    rejected(temp.path(), &wire, "inventory");
    wire.records.swap(0, 1);
    wire.corpus_hash = RawValue::from_string(
        "\"b5e06157888b2721fa5831a1e3504b3061310d1f171dcfe15ea6939bcd1b797b\"".into(),
    )
    .unwrap();
    rejected(temp.path(), &wire, "corpus"); // independently fixed v3 input TOKEN hash
    wire = serde_json::from_str(&saved).unwrap();
    wire.qualified = RawValue::from_string("true".into()).unwrap();
    rejected(temp.path(), &wire, "qualified");
    // Different physical corpus with the SAME all23 input/expected tokens.
    // A source-independent saved corpusHash cannot bind its extra leading bytes.
    put_kit(
        temp.path(),
        include_bytes!("pipeline_controls/whitespace-cases.json"),
    );
    let report = Report::from_json(&saved).unwrap();
    let error = check_report_configured(temp.path(), &report, &configuration()).unwrap_err();
    assert!(error.to_string().contains("corpus"));
}

#[test]
fn selected_source_preparation_refuses_before_adapter_spawn() {
    let temp = tempfile::tempdir().unwrap();
    put_kit(
        temp.path(),
        include_bytes!("pipeline_controls/source-forged-cases.json"),
    );
    let options = RunOptions {
        adapter: temp
            .path()
            .join("definitely-no-adapter-executable")
            .into_os_string(),
        adapter_args: vec![],
        limits: Limits::DEFAULT,
    };
    let error = run_configured(temp.path(), &options, &configuration()).unwrap_err();
    assert!(
        error.to_string().contains("source"),
        "source preparation must precede spawn: {error}"
    );
}

#[test]
fn selected_full_fixed_inventory_cannot_be_replaced_by_prefix_or_reordered_source() {
    #[derive(Serialize, Deserialize)]
    #[serde(rename_all = "camelCase", deny_unknown_fields)]
    struct CorpusMutation {
        format_version: Box<RawValue>,
        cases: Vec<Box<RawValue>>,
    }
    let temp = tempfile::tempdir().unwrap();
    let options = RunOptions {
        adapter: temp
            .path()
            .join("definitely-no-adapter-executable")
            .into_os_string(),
        adapter_args: vec![],
        limits: Limits::DEFAULT,
    };
    let mut prefix: CorpusMutation =
        serde_json::from_str(include_str!("pipeline_controls/cases.json")).unwrap();
    assert_eq!(prefix.cases.len(), 23);
    prefix.cases.pop();
    put_kit(temp.path(), &serde_json::to_vec(&prefix).unwrap());
    let error = run_configured(temp.path(), &options, &configuration()).unwrap_err();
    assert!(
        error.to_string().contains("inventory"),
        "full fixed partial inventory required before spawn: {error}"
    );
    put_kit(
        temp.path(),
        include_bytes!("pipeline_controls/reordered-cases.json"),
    );
    let error = run_configured(temp.path(), &options, &configuration()).unwrap_err();
    assert!(
        error.to_string().contains("inventory"),
        "source order is independently fixed, not report-controlled: {error}"
    );
}

#[test]
fn selected_policy_is_closed_exact_validated_and_never_inferred_from_saved_data() {
    configuration();
    assert!(RunConfiguration::from_json(r#"{"kind":"historical"}"#).is_ok());
    let policy = include_str!("pipeline_controls/explicit-test-policy.json");
    assert!(
        RunConfiguration::from_json(&policy.replacen(
            "\"savedBytes\":16777216",
            "\"savedBytes\":0",
            1
        ))
        .is_err()
    );
    assert!(
        RunConfiguration::from_json(&policy.replacen(
            "\"slots\":4000000",
            "\"slots\":0.00000000000000000001",
            1
        ))
        .is_err()
    );
    assert!(
        RunConfiguration::from_json(&policy.replacen("\"slots\":4000000", "\"slots\":1e400", 1))
            .is_err()
    );
    assert!(
        RunConfiguration::from_json(&policy.replacen(
            "\"kind\":\"model-originals\"",
            "\"kind\":\"model-originals\",\"kind\":\"historical\"",
            1
        ))
        .is_err()
    );
    assert!(
        RunConfiguration::from_json(&policy.replacen(
            "\"definitions\":1000000",
            &format!("\"definitions\":{}", usize::MAX),
            1
        ))
        .is_err()
    );
    // Existing zero-means-refuse closure semantics are valid configuration,
    // unlike the existing positive-only Decoder policy constructor.
    assert!(
        RunConfiguration::from_json(&policy.replacen(
            "\"definitions\":1000000",
            "\"definitions\":0",
            1
        ))
        .is_ok()
    );
}
