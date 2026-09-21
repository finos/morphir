use std::path::{Path, PathBuf};

use morphir_mck::kit::manifest::LockSource;
use morphir_mck::kit::snapshot::collect;
use morphir_mck::kit::{Kit, KitSource, load_kit};
use morphir_mck::report::check::{AllowedFailures, check};
use morphir_mck::report::draft::DraftReport;
use serde_json::{Value, json};

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn baseline() -> (Kit, Value) {
    let root = repo();
    let kit = load_kit(KitSource::directory(&root.join("spec/ir/mck"), Some(&root))).unwrap();
    assert!(kit.errors.is_empty(), "{:?}", kit.errors);
    let mut report: Value = serde_json::from_str(include_str!(
        "../../../spec/ir/mck/report-draft.example.json"
    ))
    .unwrap();
    let legacy: Value = serde_json::from_str(include_str!(
        "../../../spec/mck/baseline/reports/morphir-typescript.json"
    ))
    .unwrap();
    let transcript =
        include_str!("../../../spec/mck/baseline/transcripts/morphir-typescript.ndjson");
    let response: Value = serde_json::from_str(transcript.lines().nth(1).unwrap()).unwrap();
    let mut caps = response["message"].clone();
    caps.as_object_mut().unwrap().remove("id");
    report["adapter"]["negotiation"]["capabilities"] = caps;
    report["records"] = legacy["records"].clone();
    let lock = collect(&kit)
        .unwrap()
        .lock(LockSource::Local { revision: None });
    report["kit"]["snapshotDigest"] = json!(lock.snapshot_digest.as_str());
    (kit, report)
}

fn verdict(kit: &Kit, value: Value, filter: Option<&str>, allowed: &[&str]) -> Result<(), String> {
    let report = DraftReport::from_value(value).unwrap();
    let allowed = AllowedFailures::from_json(&json!({"cases":allowed}).to_string()).unwrap();
    check(&report, kit, &allowed, filter).map(|_| ())
}

#[test]
fn frozen_baseline_passes_but_missing_extra_and_reordered_records_fail() {
    let (kit, value) = baseline();
    verdict(&kit, value.clone(), None, &[]).unwrap();
    for mutation in ["pinned", "case", "duplicate", "reorder"] {
        let mut changed = value.clone();
        let records = changed["records"].as_array_mut().unwrap();
        match mutation {
            "pinned" => records.retain(|r| r["path"] != "pinned"),
            "case" => records.retain(|r| r["caseId"] != "types-0001"),
            "duplicate" => records.push(records[0].clone()),
            "reorder" => records.swap(0, 1),
            _ => unreachable!(),
        }
        assert!(
            verdict(&kit, changed, None, &[])
                .unwrap_err()
                .contains("inventory"),
            "{mutation}"
        );
    }
}

#[test]
fn filtered_claim_requires_independent_filter_and_scopes_stale_entries() {
    let (kit, mut value) = baseline();
    value["selection"] = json!({"kind":"filter","syntax":"rust-regex","pattern":"^types-0001$"});
    value["records"]
        .as_array_mut()
        .unwrap()
        .retain(|r| r["caseId"] == "types-0001");
    assert!(
        verdict(&kit, value.clone(), None, &[])
            .unwrap_err()
            .contains("selection")
    );
    verdict(&kit, value.clone(), Some("^types-0001$"), &["types-0002"]).unwrap();
    assert!(
        verdict(&kit, value, Some("^types-0001$"), &["types-0001"])
            .unwrap_err()
            .contains("stale")
    );
}

#[test]
fn failed_sessions_bad_digests_and_forged_skip_reasons_fail() {
    let (kit, value) = baseline();
    let mut failed = value.clone();
    failed["execution"]["session"] =
        json!({"status":"failed","errors":[{"phase":"shutdown","message":"exit 7"}]});
    assert!(
        verdict(&kit, failed, None, &[])
            .unwrap_err()
            .contains("session")
    );
    let mut different = value.clone();
    different["kit"]["snapshotDigest"] = json!(format!("sha256-{}", "0".repeat(64)));
    assert!(
        verdict(&kit, different, None, &[])
            .unwrap_err()
            .contains("digest")
    );
    let mut skipped = value;
    skipped["records"][0]["result"] = json!("skipped");
    skipped["records"][0]["message"] = json!("node Value not in capabilities");
    assert!(
        verdict(&kit, skipped, None, &[])
            .unwrap_err()
            .contains("skip")
    );
}

#[test]
fn unsupported_records_cannot_claim_a_pass() {
    let (kit, mut value) = baseline();
    for record in value["records"].as_array_mut().unwrap() {
        if record["result"] == "skipped" {
            record["result"] = json!("pass");
            record.as_object_mut().unwrap().remove("message");
        }
    }
    assert!(
        verdict(&kit, value, None, &[])
            .unwrap_err()
            .contains("skip")
    );
}

#[test]
fn repeated_adapter_paths_cannot_authorize_duplicate_fences() {
    let (kit, mut value) = baseline();
    value["adapter"]["negotiation"]["capabilities"]["paths"] = json!(["current", "current"]);
    for record in value["records"].as_array_mut().unwrap() {
        if record["path"] == "pinned" {
            record["path"] = json!("current");
        }
    }
    assert!(
        verdict(&kit, value, None, &[])
            .unwrap_err()
            .contains("duplicate")
    );
}

#[test]
fn kit_error_allowances_require_a_complete_kit_identity() {
    let (mut kit, mut value) = baseline();
    let id = value["records"][0]["caseId"].as_str().unwrap().to_owned();
    value["records"][0]["result"] = json!("kit-error");
    value["records"][0]["message"] = json!("adapter could not process this fence");
    verdict(&kit, value.clone(), None, &[&id]).unwrap();
    kit.errors.push(morphir_mck::kit::syntax::case::KitError {
        file: "spec/ir/mck/types.md".into(),
        line: 1,
        message: "authoring error".into(),
    });
    assert!(
        verdict(&kit, value, None, &[&id])
            .unwrap_err()
            .contains("cannot establish kit snapshot digest")
    );
}

#[test]
fn baseline_allowances_cannot_hide_unknown_cases_or_an_absence_of_passes() {
    let (kit, mut value) = baseline();
    assert!(
        verdict(&kit, value.clone(), None, &["types-9999"])
            .unwrap_err()
            .contains("unknown allowed")
    );
    for record in value["records"].as_array_mut().unwrap() {
        if record["result"] == "pass" {
            record["result"] = json!("fail");
        }
    }
    let ids: Vec<_> = kit.cases.iter().map(|case| case.id.as_str()).collect();
    assert!(
        verdict(&kit, value, None, &ids)
            .unwrap_err()
            .contains("no passing record")
    );
}
