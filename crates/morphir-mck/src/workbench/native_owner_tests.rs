use super::*;
use serde_json::{Value, json};

fn caps() -> Value {
    json!({"suite":"workbench","contractVersion":"0.1.0-draft.18",
        "binding":"production-owner","language":"moonbit",
        "operations":["run-native-owner"],"formats":["json"]})
}

#[test]
fn native_owner_negotiates_only_its_exact_json_operation() {
    Capabilities::parse(caps(), "0.1.0-draft.18").unwrap();
    for (field, value) in [
        ("operations", json!([])),
        ("operations", json!(["run-native-client"])),
        ("formats", json!(["ion-text"])),
        ("formats", json!(["json", "ion-text"])),
        ("contractVersion", json!("0.1.0-draft.18+local")),
        ("contractVersion", json!("0.1.0-draft.11")),
    ] {
        let mut bad = caps();
        bad[field] = value;
        assert!(Capabilities::parse(bad, "0.1.0-draft.18").is_err());
    }
    assert!(Capabilities::parse(caps(), "0.1.0-draft.17").is_err());
}

fn fixture() -> Value {
    serde_json::from_str::<Value>(include_str!(
        "../../../../spec/workbench/mck/draft.18/cases.json"
    ))
    .unwrap()["cases"][0]
        .clone()
}

struct Reply(Value);
impl Testee for Reply {
    fn exchange(&mut self, request: &Value) -> Result<Value, String> {
        assert!(request.get("expected").is_none() && request.get("caseId").is_none());
        Ok(if request["op"] == "capabilities" {
            caps()
        } else {
            assert_eq!(request["op"], "run-native-owner");
            self.0.clone()
        })
    }
}

#[test]
fn native_owner_runs_fixed_authority_negative_case_and_recomputes_report() {
    let root = tempfile::tempdir().unwrap();
    let corpus = small_corpus(root.path(), fixture()).unwrap();
    assert_eq!(corpus.case_count(), 1);
    let report = execute(&corpus, &mut Reply(fixture()["expected"].clone()));
    assert!(report.qualified, "{:?}", report.errors);
    check_report(root.path(), &Report::from_json(&report.to_json()).unwrap()).unwrap();
}

fn small_corpus(root: &std::path::Path, case: Value) -> Result<Corpus, String> {
    std::fs::write(
        root.join("cases.json"),
        json!({"formatVersion":"0.1.0-draft.18","cases":[case]}).to_string(),
    )
    .unwrap();
    load(root)
}

#[test]
fn native_owner_rejects_duplicate_and_dangling_fixture_infrastructure() {
    let root = tempfile::tempdir().unwrap();
    for kind in [
        "attempt",
        "boundary",
        "cleanup-session",
        "root",
        "file",
        "picker-root",
        "delivery",
        "unheld",
        "double-delivery",
        "replacement",
        "json-duplicate",
        "json-not-array",
        "decoded-source",
        "base64",
        "combined-boundaries",
    ] {
        let mut case = fixture();
        case["input"]["roots"] = json!([{"id":"r","manifest":"{}","files":[{"name":"morphir-ir.json","encoding":"utf8","source":"{}"}]}]);
        case["input"]["pickers"] = json!([{"id":"p","held":true,"root":"r","fail":false}]);
        case["input"]["cleanups"] = json!([{"id":"c","session":"open","held":true,"success":true}]);
        match kind {
            "attempt" => {
                case["input"]["actions"] = json!([{"op":"call","id":"open","operation":"session.open"},{"op":"shutdown","id":"open"}])
            }
            "boundary" => case["input"]["cleanups"][0]["id"] = json!("p"),
            "cleanup-session" => case["input"]["cleanups"]
                .as_array_mut()
                .unwrap()
                .push(json!({"id":"retry","session":"open","held":false,"success":true})),
            "root" => {
                let r = case["input"]["roots"][0].clone();
                case["input"]["roots"].as_array_mut().unwrap().push(r);
            }
            "file" => {
                let f = case["input"]["roots"][0]["files"][0].clone();
                case["input"]["roots"][0]["files"]
                    .as_array_mut()
                    .unwrap()
                    .push(f);
            }
            "picker-root" => case["input"]["pickers"][0]["root"] = json!("absent"),
            "delivery" => case["input"]["actions"] = json!([{"op":"deliver","id":"absent"}]),
            "unheld" => {
                case["input"]["pickers"][0]["held"] = json!(false);
                case["input"]["actions"] = json!([{"op":"deliver","id":"p"}]);
            }
            "double-delivery" => {
                case["input"]["actions"] =
                    json!([{"op":"deliver","id":"p"},{"op":"deliver","id":"p"}])
            }
            "replacement" => {
                case["input"]["actions"] = json!([{"op":"replace","root":"r","name":"morphir-ir.ion","encoding":"utf8","source":"x"}])
            }
            "json-duplicate" => {
                case["input"]["evaluation"]["inputs"]["source"] = json!("[{\"a\":1,\"a\":2}]")
            }
            "json-not-array" => case["input"]["evaluation"]["inputs"]["source"] = json!("{}"),
            "decoded-source" => {
                case["input"]["roots"][0]["files"][0]["source"] = json!("é".repeat(131073))
            }
            "base64" => {
                case["input"]["roots"][0]["files"][0]["encoding"] = json!("base64");
                case["input"]["roots"][0]["files"][0]["source"] = json!("not-base64");
            }
            "combined-boundaries" => {
                case["input"]["pickers"] = Value::Array(
                    (0..128)
                        .map(
                            |i| json!({"id":format!("p{i}"),"held":false,"root":null,"fail":false}),
                        )
                        .collect(),
                );
            }
            _ => unreachable!(),
        }
        assert!(small_corpus(root.path(), case).is_err(), "{kind}");
    }
}

#[test]
fn native_owner_literal_guards_reject_serde_markers_before_typed_conversion() {
    let root = tempfile::tempdir().unwrap();
    for kind in [
        "private-bool",
        "private-count",
        "private-outcomes",
        "unknown",
    ] {
        let mut case = fixture();
        match kind {
            "private-bool" => {
                case["input"]["services"]["workspace"] =
                    json!({"$serde_json::private::RawValue":"true"})
            }
            "private-count" => {
                case["expected"]["value"]["usedPickers"] =
                    json!({"$serde_json::private::Number":"0"})
            }
            "private-outcomes" => {
                case["input"]["actions"] = json!([{"op":"complete","execution":"unknown","outcomes":{"nested":{"$serde_json::private::RawValue":"true"}}}])
            }
            "unknown" => case["input"]["authority"] = json!(true),
            _ => unreachable!(),
        }
        assert!(small_corpus(root.path(), case).is_err(), "{kind}");
    }
    std::fs::write(
        root.path().join("cases.json"),
        json!({"formatVersion":"0.1.0-draft.18","cases":[fixture()]})
            .to_string()
            .replacen(
                "\"workspace\":true",
                "\"workspace\":true,\"workspace\":false",
                1,
            ),
    )
    .unwrap();
    assert!(load(root.path()).is_err());
}

#[test]
fn native_owner_expected_effect_sets_match_only_fixed_explicit_choices() {
    let root = tempfile::tempdir().unwrap();
    let mut case = fixture();
    case["expected"]["value"]["results"][0]["reply"]["code"] = json!("conflict");
    case["expected"]["value"]["results"][0]["reply"]["effect"] = json!(["none", "unknown"]);
    let corpus = small_corpus(root.path(), case.clone()).unwrap();
    for effect in ["none", "unknown"] {
        let mut observed = case["expected"].clone();
        observed["value"]["results"][0]["reply"]["effect"] = json!(effect);
        let report = execute(&corpus, &mut Reply(observed));
        assert!(report.qualified, "{effect}: {:?}", report.errors);
        check_report(root.path(), &Report::from_json(&report.to_json()).unwrap()).unwrap();
    }
    for allowed in [json!("none"), json!(["none"])] {
        let mut exact = case.clone();
        exact["expected"]["value"]["results"][0]["reply"]["effect"] = allowed;
        let corpus = small_corpus(root.path(), exact).unwrap();
        let mut observed = case["expected"].clone();
        observed["value"]["results"][0]["reply"]["effect"] = json!("unknown");
        let report = execute(&corpus, &mut Reply(observed));
        assert_eq!(report.records[0].result, ResultKind::Fail);
        check_report(root.path(), &report).unwrap();
    }
    for effect in [
        json!([]),
        json!(["none", "none"]),
        json!(["none", "other"]),
        json!(null),
    ] {
        let mut invalid = case.clone();
        invalid["expected"]["value"]["results"][0]["reply"]["effect"] = effect;
        assert!(small_corpus(root.path(), invalid).is_err());
    }
    let corpus = small_corpus(root.path(), case.clone()).unwrap();
    let report = execute(&corpus, &mut Reply(case["expected"].clone()));
    assert_eq!(
        report.records[0].result,
        ResultKind::Error,
        "actual observations forbid effect arrays"
    );
    check_report(root.path(), &report).unwrap();
    let mut observed = case["expected"].clone();
    observed["value"]["results"][0]["reply"]["effect"] = json!("none");
    let good = execute(&corpus, &mut Reply(observed));
    let mut saved = serde_json::to_value(&good).unwrap();
    saved["records"][0]["observed"]["value"]["results"][0]["reply"]["effect"] =
        json!(["none", "unknown"]);
    assert!(Report::from_json(&saved.to_string()).is_err());
    let mut forged = good;
    forged.records[0].observed = Some(Observation::parse(case["expected"].clone()).unwrap());
    assert!(check_report(root.path(), &forged).is_err());
}

#[test]
fn native_owner_reports_preserve_errors_mismatches_and_reject_forgery() {
    let root = tempfile::tempdir().unwrap();
    let case = fixture();
    let corpus = small_corpus(root.path(), case.clone()).unwrap();
    for observed in [
        json!({"status":"invalid","code":"owner.invalid"}),
        json!({"status":"ok","value":{"$serde_json::private::RawValue":case["expected"]["value"].to_string()}}),
    ] {
        let report = execute(&corpus, &mut Reply(observed));
        assert_eq!(report.records[0].result, ResultKind::Error);
        assert_eq!(report.errors[0].phase, Phase::Exchange);
        assert!(!report.qualified);
        check_report(root.path(), &Report::from_json(&report.to_json()).unwrap()).unwrap();
    }
    let mut mismatch = case["expected"].clone();
    mismatch["value"]["usedPickers"] = json!(1);
    let report = execute(&corpus, &mut Reply(mismatch));
    assert_eq!(report.records[0].result, ResultKind::Fail);
    assert!(!report.qualified && report.errors.is_empty());
    check_report(root.path(), &report).unwrap();
    let report = execute(&corpus, &mut Reply(case["expected"].clone()));
    let saved = serde_json::to_value(&report).unwrap();
    for kind in [
        "qualified",
        "result",
        "operation",
        "hash",
        "capabilities",
        "observed",
        "private-count",
        "private-bool",
        "duplicate",
    ] {
        let mut bad = saved.clone();
        match kind {
            "qualified" => bad["qualified"] = json!(false),
            "result" => bad["records"][0]["result"] = json!("fail"),
            "operation" => bad["records"][0]["operation"] = json!("run-native-client"),
            "hash" => bad["corpusHash"] = json!("0".repeat(64)),
            "capabilities" => bad["capabilities"]["contractVersion"] = json!("0.1.0-draft.17"),
            "observed" => bad["records"][0]["observed"]["value"]["usedPickers"] = json!(1),
            "private-count" => {
                bad["records"][0]["observed"]["value"]["usedPickers"] =
                    json!({"$serde_json::private::Number":"0"})
            }
            "private-bool" => {
                bad["records"][0]["observed"]["value"]["results"][0]["reply"]["ok"] =
                    json!({"$serde_json::private::RawValue":"false"})
            }
            "duplicate" => {}
            _ => unreachable!(),
        }
        let mut text = bad.to_string();
        if kind == "duplicate" {
            text = text.replacen("{", "{\"qualified\":false,", 1);
        }
        assert!(
            Report::from_json(&text)
                .and_then(|r| check_report(root.path(), &r))
                .is_err(),
            "{kind}"
        );
    }
    let mut bytes = std::fs::read(root.path().join("cases.json")).unwrap();
    bytes.push(b' ');
    std::fs::write(root.path().join("cases.json"), bytes).unwrap();
    assert!(check_report(root.path(), &report).is_err());
}

#[test]
fn native_owner_input_and_projection_budgets_count_compact_encoded_bytes() {
    let root = tempfile::tempdir().unwrap();
    let mut case = fixture();
    case["input"]["evaluation"]["model"] = json!(" ".repeat(240000));
    case["input"]["roots"] = json!([{"id":"r","manifest":"{}","files":[{"name":"morphir-ir.json","encoding":"utf8","source":""}]}]);
    let current = serde_json::to_vec(&case["input"]).unwrap().len();
    case["input"]["roots"][0]["files"][0]["source"] = json!(" ".repeat(491520 - current));
    assert_eq!(serde_json::to_vec(&case["input"]).unwrap().len(), 491520);
    small_corpus(root.path(), case.clone()).unwrap();
    let source = case["input"]["roots"][0]["files"][0]["source"]
        .as_str()
        .unwrap()
        .to_owned();
    case["input"]["roots"][0]["files"][0]["source"] = json!(format!("{source} "));
    assert!(small_corpus(root.path(), case).is_err());
    let case = fixture();
    let corpus = small_corpus(root.path(), case.clone()).unwrap();
    let mut value = case["expected"]["value"].clone();
    value["calls"] = json!([""]);
    let current = serde_json::to_vec(&value).unwrap().len();
    value["calls"] = json!([" ".repeat(MAX_VALUE_BYTES - current)]);
    assert_eq!(serde_json::to_vec(&value).unwrap().len(), MAX_VALUE_BYTES);
    let at_limit = execute(&corpus, &mut Reply(json!({"status":"ok","value":value})));
    assert_eq!(at_limit.records[0].result, ResultKind::Fail);
    check_report(root.path(), &at_limit).unwrap();
    value["calls"][0] = json!(format!("{} ", value["calls"][0].as_str().unwrap()));
    let over_limit = execute(&corpus, &mut Reply(json!({"status":"ok","value":value})));
    assert_eq!(over_limit.records[0].result, ResultKind::Error);
    check_report(root.path(), &over_limit).unwrap();
    let mut forged = at_limit;
    forged.records[0].observed = Some(Observation::Ok { value });
    assert!(check_report(root.path(), &Report::from_json(&forged.to_json()).unwrap()).is_err());
}

#[test]
fn native_owner_fractional_infrastructure_counts_cannot_round_to_integers() {
    let root = tempfile::tempdir().unwrap();
    let corpus = small_corpus(root.path(), fixture()).unwrap();
    let report = execute(&corpus, &mut Reply(fixture()["expected"].clone()));
    let source = report
        .to_json()
        .replace("\"usedPickers\":0", "\"usedPickers\":1.00000000000000001");
    assert!(Report::from_json(&source).is_err());
    let source = std::fs::read_to_string(root.path().join("cases.json"))
        .unwrap()
        .replace("\"usedPickers\":0", "\"usedPickers\":1.00000000000000001");
    std::fs::write(root.path().join("cases.json"), source).unwrap();
    assert!(load(root.path()).is_err());
}
