//! Producer-independent report controls. These never run a model adapter.
use morphir_mck::workbench::{Report, check_report, load};
use serde_json::{Value, json};
use std::path::{Path, PathBuf};

fn kit() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/workbench/mck/draft.29")
}

fn authored_report(root: &Path) -> Value {
    let corpus = load(root).expect("frozen independent corpus must load");
    let fixture: Value =
        serde_json::from_str(&std::fs::read_to_string(root.join("cases.json")).unwrap()).unwrap();
    let records: Vec<Value> = fixture["cases"]
        .as_array()
        .unwrap()
        .iter()
        .map(|case| {
            json!({
                "caseId":case["id"], "operation":case["operation"], "format":case["format"],
                "result":"pass", "observed":case["expected"]
            })
        })
        .collect();
    json!({"formatVersion":"0.1.0-draft.29","suite":"workbench","corpusHash":corpus.corpus_hash(),
        "capabilities":{"suite":"workbench","contractVersion":"0.1.0-draft.29","binding":"checker-positive-control-only","language":"rust-test","operations":["inspect-model","export-model-original"],"formats":["json"]},
        "records":records,"errors":[],"qualified":true})
}

#[test]
fn fixed_local_model_controls_are_accepted_without_a_producer() {
    let root = kit();
    assert_eq!(load(&root).unwrap().case_count(), 32);
    let report = Report::from_json(&authored_report(&root).to_string()).unwrap();
    check_report(&root, &report).unwrap();
}

fn refused(value: &Value) -> bool {
    Report::from_json(&value.to_string())
        .and_then(|r| check_report(&kit(), &r))
        .is_err()
}

#[test]
fn saved_local_model_reports_reject_tampering_and_incomplete_inventories() {
    let positive = authored_report(&kit());
    for pointer in [
        "/corpusHash",
        "/formatVersion",
        "/capabilities/contractVersion",
        "/capabilities/operations/0",
        "/records/0/caseId",
        "/records/0/operation",
        "/records/0/format",
        "/records/0/result",
        "/records/0/observed/value/providerId",
        "/records/0/observed/value/inputFormat",
        "/records/0/observed/value/packageName",
        "/records/0/observed/value/normalizedIr",
        "/records/1/observed/value/hex",
        "/records/1/observed/value/sha256",
        "/records/1/observed/value/kind",
    ] {
        let mut bad = positive.clone();
        *bad.pointer_mut(pointer).unwrap() = json!("forged");
        assert!(refused(&bad), "accepted tampering at {pointer}");
    }
    for mode in [
        "missing",
        "duplicate",
        "reordered",
        "null-observed",
        "absent-observed",
        "false-qualified",
        "missing-errors",
        "extra-field",
        "fractional-length",
    ] {
        let mut bad = positive.clone();
        match mode {
            "missing" => {
                bad["records"].as_array_mut().unwrap().pop();
            }
            "duplicate" => {
                let first = bad["records"][0].clone();
                bad["records"].as_array_mut().unwrap().push(first);
            }
            "reordered" => bad["records"].as_array_mut().unwrap().swap(0, 1),
            "null-observed" => bad["records"][0]["observed"] = Value::Null,
            "absent-observed" => {
                bad["records"][0]
                    .as_object_mut()
                    .unwrap()
                    .remove("observed");
            }
            "false-qualified" => bad["qualified"] = json!(false),
            "missing-errors" => {
                bad.as_object_mut().unwrap().remove("errors");
            }
            "extra-field" => {
                bad["records"][0]["observed"]["value"]["authority"] = json!("invented")
            }
            "fractional-length" => {
                bad["records"][1]["observed"]["value"]["byteLength"] = json!(1.5)
            }
            _ => unreachable!(),
        }
        assert!(refused(&bad), "accepted {mode}");
    }
    let raw = positive.to_string();
    assert!(Report::from_json(&format!("{{\"qualified\":true,{}", &raw[1..])).is_err());
}

#[test]
fn normalized_model_json_compares_exact_numbers_without_serialization_order() {
    let mut evidence = authored_report(&kit());
    let model = evidence["records"][0]["observed"]["value"]["normalizedIr"]
        .as_str()
        .unwrap();
    let parsed: Value = serde_json::from_str(model).unwrap();
    evidence["records"][0]["observed"]["value"]["normalizedIr"] =
        json!(serde_json::to_string_pretty(&parsed).unwrap());
    check_report(&kit(), &Report::from_json(&evidence.to_string()).unwrap()).unwrap();
    let record = evidence["records"]
        .as_array_mut()
        .unwrap()
        .iter_mut()
        .find(|r| r["caseId"] == "exact-scalars-json-inspect-model")
        .unwrap();
    record["observed"]["value"]["normalizedIr"] = json!(
        record["observed"]["value"]["normalizedIr"]
            .as_str()
            .unwrap()
            .replace("9007199254740993", "9007199254740992")
    );
    assert!(refused(&evidence));
}

#[test]
fn a_rehashed_changed_original_still_refuses_captured_input_mismatch() {
    let mut evidence = authored_report(&kit());
    let original = &mut evidence["records"][1]["observed"]["value"];
    original["hex"] = json!("");
    original["byteLength"] = json!(0);
    original["sha256"] = json!("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    assert!(refused(&evidence));
}

#[test]
fn report_and_model_evidence_have_explicit_byte_bounds() {
    let over_report = " ".repeat(morphir_mck::workbench::MAX_REPORT_BYTES + 1);
    assert!(
        Report::from_json(&over_report)
            .unwrap_err()
            .contains("32 MiB")
    );
    let mut evidence = authored_report(&kit());
    evidence["records"][0]["observed"]["value"]["normalizedIr"] = json!(" ".repeat(1048577));
    assert!(refused(&evidence));
    let positive = authored_report(&kit());
    let length = positive["records"][1]["observed"]["value"]["byteLength"]
        .as_u64()
        .unwrap();
    let raw = positive.to_string().replacen(
        &format!("\"byteLength\":{length}"),
        &format!("\"byteLength\":{length}.00000000000000000001"),
        1,
    );
    assert!(
        Report::from_json(&raw)
            .and_then(|r| check_report(&kit(), &r))
            .is_err()
    );
}

#[test]
fn corpus_source_hex_is_bounded_before_materialization() {
    let temp = tempfile::tempdir().unwrap();
    let mut fixture = json!({"formatVersion":"0.1.0-draft.29","cases":[{
        "id":"bounded-source", "operation":"inspect-model", "format":"json",
        "input":{"providerId":"local-model-fixture","format":"json","source":{"hex":""}},
        "expected":{"status":"invalid","code":"input_limit"}
    }]});
    for (length, accepted) in [(1048577, true), (1048578, false)] {
        fixture["cases"][0]["input"]["source"]["hex"] = json!("20".repeat(length));
        std::fs::write(temp.path().join("cases.json"), fixture.to_string()).unwrap();
        assert_eq!(load(temp.path()).is_ok(), accepted);
    }
    for malformed in ["0", "xx", "AB", "é"] {
        fixture["cases"][0]["input"]["source"]["hex"] = json!(malformed);
        std::fs::write(temp.path().join("cases.json"), fixture.to_string()).unwrap();
        assert!(load(temp.path()).is_err());
    }
}
