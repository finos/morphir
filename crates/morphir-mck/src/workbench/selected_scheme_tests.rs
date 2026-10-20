use super::*;
use serde_json::{Value, json};

fn capabilities() -> Value {
    json!({"suite":"workbench","contractVersion":"0.1.0-draft.11",
        "binding":"selected-plan-test","language":"test",
        "operations":["run-selected-scheme"],"formats":["json"]})
}

#[test]
fn selected_scheme_negotiates_only_the_exact_json_witness_operation() {
    Capabilities::parse(capabilities(), "0.1.0-draft.11").unwrap();
    for (field, value) in [
        ("contractVersion", json!("0.1.0-draft.11+local")),
        ("contractVersion", json!("0.1.0-draft.12")),
        ("operations", json!(["run-admission-policy"])),
        ("formats", json!(["ion-text"])),
    ] {
        let mut bad = capabilities();
        bad[field] = value;
        assert!(Capabilities::parse(bad, "0.1.0-draft.11").is_err());
    }
    assert!(Capabilities::parse(capabilities(), "0.1.0-draft.18").is_err());
    let mut unsupported = capabilities();
    unsupported["operations"] = json!([]);
    Capabilities::parse(unsupported, "0.1.0-draft.11").unwrap();
}

fn fixture() -> Value {
    serde_json::from_str::<Value>(include_str!(
        "../../../../spec/workbench/mck/draft.11/cases.json"
    ))
    .unwrap()["cases"][0]
        .clone()
}

struct Reply(Value);
impl Testee for Reply {
    fn exchange(&mut self, request: &Value) -> Result<Value, String> {
        assert!(request.get("expected").is_none() && request.get("caseId").is_none());
        Ok(if request["op"] == "capabilities" {
            capabilities()
        } else {
            assert_eq!(request["op"], "run-selected-scheme");
            self.0.clone()
        })
    }
}

fn small_corpus(root: &std::path::Path, case: Value) -> Result<Corpus, String> {
    std::fs::write(
        root.join("cases.json"),
        json!({"formatVersion":"0.1.0-draft.11","cases":[case]}).to_string(),
    )
    .unwrap();
    load(root)
}

#[test]
fn selected_scheme_fixed_unused_hole_witness_runs_and_report_rechecks() {
    let root = tempfile::tempdir().unwrap();
    let corpus = small_corpus(root.path(), fixture()).unwrap();
    let report = execute(&corpus, &mut Reply(fixture()["expected"].clone()));
    assert!(
        report.qualified(),
        "{:?}",
        report
            .as_historical()
            .expect("historical report fixture")
            .errors
    );
    check_report(root.path(), &Report::from_json(&report.to_json()).unwrap()).unwrap();
}

#[test]
fn selected_scheme_entire_fixed_witness_inventory_recomputes_without_source_decoding() {
    let root =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/workbench/mck/draft.11");
    let corpus = load(&root).unwrap();
    assert_eq!(corpus.case_count(), 37);
    struct Replay(std::collections::VecDeque<Value>);
    impl Testee for Replay {
        fn exchange(&mut self, request: &Value) -> Result<Value, String> {
            assert!(request.get("expected").is_none() && request.get("caseId").is_none());
            self.0.pop_front().ok_or("exhausted replay".into())
        }
    }
    let mut adapter = Replay(
        std::iter::once(capabilities())
            .chain(
                corpus
                    .as_historical()
                    .expect("historical corpus fixture")
                    .cases
                    .iter()
                    .map(|c| serde_json::to_value(&c.expected).unwrap()),
            )
            .collect(),
    );
    let report = execute(&corpus, &mut adapter);
    assert!(
        report.qualified(),
        "{:?}",
        report
            .as_historical()
            .expect("historical report fixture")
            .errors
    );
    check_report(&root, &Report::from_json(&report.to_json()).unwrap()).unwrap();
}

#[test]
fn selected_scheme_corpus_is_closed_before_typed_conversion_and_keeps_sources_opaque() {
    let root = tempfile::tempdir().unwrap();
    for kind in [
        "model-marker",
        "policy-marker",
        "profile",
        "version",
        "suffix",
        "unknown",
        "runtime",
        "value-marker",
    ] {
        let mut case = fixture();
        match kind {
            "model-marker" => {
                case["input"]["model"] = json!({"$serde_json::private::RawValue":"\"model\""})
            }
            "policy-marker" => {
                case["input"]["admission"]["policy"] =
                    json!({"$serde_json::private::RawValue":"\"permissive\""})
            }
            "profile" => case["input"]["admission"]["profile"] = json!("other"),
            "version" => case["input"]["admission"]["contractVersion"] = json!("0.1.0-draft.2"),
            "suffix" => {
                case["input"]["admission"]["contractVersion"] = json!("0.1.0-draft.1+local")
            }
            "unknown" => case["input"]["manifest"] = json!({}),
            "runtime" => case["input"]["runtime"] = json!("native"),
            "value-marker" => {
                case["expected"]["value"]["values"][0] =
                    json!({"$serde_json::private::RawValue":"{\"type\":\"int\",\"value\":\"42\"}"})
            }
            _ => unreachable!(),
        }
        assert!(small_corpus(root.path(), case).is_err(), "{kind}");
    }
    let mut opaque = fixture();
    opaque["input"]["model"] = json!("not parsed by the runner");
    opaque["input"]["inputs"]["source"] = json!("[");
    small_corpus(root.path(), opaque).unwrap();
    let text = std::fs::read_to_string(root.path().join("cases.json"))
        .unwrap()
        .replacen(
            "\"runtime\":\"scheme\"",
            "\"runtime\":\"scheme\",\"runtime\":\"scheme\"",
            1,
        );
    std::fs::write(root.path().join("cases.json"), text).unwrap();
    assert!(load(root.path()).is_err());
}

#[test]
fn selected_scheme_observed_domain_failures_differ_from_missing_capability_and_exchange_errors() {
    let root = tempfile::tempdir().unwrap();
    let mut case = fixture();
    case["expected"] = json!({"status":"ok","value":{"policy":"permissive","runtime":"scheme","boundary":null,"values":null,"failure":{"stage":"plan","code":"execution.wrong_arity"}}});
    let corpus = small_corpus(root.path(), case.clone()).unwrap();
    let domain = execute(&corpus, &mut Reply(case["expected"].clone()));
    assert!(
        domain.qualified()
            && domain
                .as_historical()
                .expect("historical report fixture")
                .errors
                .is_empty()
    );
    check_report(root.path(), &domain).unwrap();
    struct Unclaimed;
    impl Testee for Unclaimed {
        fn exchange(&mut self, request: &Value) -> Result<Value, String> {
            assert_eq!(
                request["op"], "capabilities",
                "unclaimed operation must not execute"
            );
            let mut caps = capabilities();
            caps["operations"] = json!([]);
            Ok(caps)
        }
    }
    let missing = execute(&corpus, &mut Unclaimed);
    assert_eq!(
        missing
            .as_historical()
            .expect("historical report fixture")
            .records[0]
            .result,
        ResultKind::Unsupported
    );
    assert!(
        !missing.qualified()
            && missing
                .as_historical()
                .expect("historical report fixture")
                .errors
                .is_empty()
    );
    check_report(root.path(), &missing).unwrap();
    let malformed = execute(
        &corpus,
        &mut Reply(json!({"status":"invalid","code":"execution.wrong_arity"})),
    );
    assert_eq!(
        malformed
            .as_historical()
            .expect("historical report fixture")
            .records[0]
            .result,
        ResultKind::Error
    );
    assert_eq!(
        malformed
            .as_historical()
            .expect("historical report fixture")
            .errors[0]
            .phase,
        Phase::Exchange
    );
    check_report(root.path(), &malformed).unwrap();
}

#[test]
fn selected_scheme_success_and_failure_evidence_have_closed_disjoint_shapes() {
    let root = tempfile::tempdir().unwrap();
    let case = fixture();
    let corpus = small_corpus(root.path(), case.clone()).unwrap();
    for kind in [
        "no-values",
        "two-values",
        "plan-boundary",
        "evaluate-no-boundary",
        "pending",
        "failure-code-marker",
    ] {
        let mut observed = case["expected"].clone();
        match kind {
            "no-values" => observed["value"]["values"] = json!([]),
            "two-values" => {
                observed["value"]["values"] =
                    json!([{"type":"int","value":"42"},{"type":"int","value":"42"}])
            }
            "plan-boundary" => {
                observed["value"]["values"] = Value::Null;
                observed["value"]["failure"] =
                    json!({"stage":"plan","code":"execution.wrong_type"});
            }
            "evaluate-no-boundary" => {
                observed["value"]["boundary"] = Value::Null;
                observed["value"]["values"] = Value::Null;
                observed["value"]["failure"] = json!({"stage":"evaluate","code":"scheme.unbound"});
            }
            "pending" => observed["status"] = json!("pending"),
            "failure-code-marker" => {
                observed["value"]["boundary"] = Value::Null;
                observed["value"]["values"] = Value::Null;
                observed["value"]["failure"] = json!({"stage":"plan","code":{"$serde_json::private::RawValue":"\"execution.wrong_type\""}});
            }
            _ => unreachable!(),
        }
        let report = execute(&corpus, &mut Reply(observed));
        assert_eq!(
            report
                .as_historical()
                .expect("historical report fixture")
                .records[0]
                .result,
            ResultKind::Error,
            "{kind}"
        );
        check_report(root.path(), &report).unwrap();
    }
}

#[test]
fn selected_scheme_failure_codes_use_bounded_utf16_identities() {
    let root = tempfile::tempdir().unwrap();
    let case = fixture();
    let corpus = small_corpus(root.path(), case).unwrap();
    let observation = json!({"status":"ok","value":{"policy":"permissive","runtime":"scheme","boundary":null,"values":null,"failure":{"stage":"plan","code":"😀".repeat(65)}}});
    let report = execute(&corpus, &mut Reply(observation));
    assert_eq!(
        report
            .as_historical()
            .expect("historical report fixture")
            .records[0]
            .result,
        ResultKind::Error
    );
    check_report(root.path(), &report).unwrap();
}

#[test]
fn selected_scheme_report_recomputes_policy_boundary_value_and_corpus_evidence() {
    let root = tempfile::tempdir().unwrap();
    let case = fixture();
    let corpus = small_corpus(root.path(), case.clone()).unwrap();
    let mut mismatch = case["expected"].clone();
    mismatch["value"]["values"][0]["value"] = json!("41");
    let failed = execute(&corpus, &mut Reply(mismatch));
    assert_eq!(
        failed
            .as_historical()
            .expect("historical report fixture")
            .records[0]
            .result,
        ResultKind::Fail
    );
    assert!(
        failed
            .as_historical()
            .expect("historical report fixture")
            .errors
            .is_empty()
    );
    check_report(root.path(), &failed).unwrap();
    let report = execute(&corpus, &mut Reply(case["expected"].clone()));
    let saved = serde_json::to_value(&report).unwrap();
    for kind in [
        "policy",
        "boundary",
        "value",
        "qualified",
        "result",
        "hash",
        "operation",
        "private",
    ] {
        let mut bad = saved.clone();
        match kind {
            "policy" => bad["records"][0]["observed"]["value"]["policy"] = json!("strict"),
            "boundary" => bad["records"][0]["observed"]["value"]["boundary"] = json!("{}"),
            "value" => bad["records"][0]["observed"]["value"]["values"][0]["value"] = json!("41"),
            "qualified" => bad["qualified"] = json!(false),
            "result" => bad["records"][0]["result"] = json!("fail"),
            "hash" => bad["corpusHash"] = json!("0".repeat(64)),
            "operation" => bad["records"][0]["operation"] = json!("run-native-owner"),
            "private" => {
                bad["records"][0]["observed"]["value"]["values"][0] =
                    json!({"$serde_json::private::RawValue":"{\"type\":\"int\",\"value\":\"42\"}"})
            }
            _ => unreachable!(),
        }
        assert!(
            Report::from_json(&bad.to_string())
                .and_then(|r| check_report(root.path(), &r))
                .is_err(),
            "{kind}"
        );
    }
    assert!(Report::from_json(&report.to_json().replacen("{", "{\"qualified\":true,", 1)).is_err());
    let mut bytes = std::fs::read(root.path().join("cases.json")).unwrap();
    bytes.push(b' ');
    std::fs::write(root.path().join("cases.json"), bytes).unwrap();
    assert!(check_report(root.path(), &report).is_err());
}

#[test]
fn selected_scheme_bounds_compact_input_and_each_retained_projection() {
    let root = tempfile::tempdir().unwrap();
    let mut case = fixture();
    case["input"]["model"] = json!("é".repeat(245000));
    let current = serde_json::to_vec(&case["input"]).unwrap().len();
    case["input"]["model"] = json!(format!(
        "{}{}",
        case["input"]["model"].as_str().unwrap(),
        " ".repeat(491520 - current)
    ));
    assert_eq!(serde_json::to_vec(&case["input"]).unwrap().len(), 491520);
    small_corpus(root.path(), case.clone()).unwrap();
    case["input"]["model"] = json!(format!("{} ", case["input"]["model"].as_str().unwrap()));
    assert!(small_corpus(root.path(), case).is_err());
    let case = fixture();
    let corpus = small_corpus(root.path(), case.clone()).unwrap();
    let mut observed = case["expected"].clone();
    observed["value"]["boundary"] = json!("");
    let overhead = serde_json::to_vec(&observed["value"]).unwrap().len();
    observed["value"]["boundary"] = json!(" ".repeat(MAX_VALUE_BYTES - overhead));
    let at_limit = execute(&corpus, &mut Reply(observed.clone()));
    assert_eq!(
        at_limit
            .as_historical()
            .expect("historical report fixture")
            .records[0]
            .result,
        ResultKind::Fail
    );
    check_report(root.path(), &at_limit).unwrap();
    observed["value"]["boundary"] = json!(format!(
        "{} ",
        observed["value"]["boundary"].as_str().unwrap()
    ));
    let over_limit = execute(&corpus, &mut Reply(observed.clone()));
    assert_eq!(
        over_limit
            .as_historical()
            .expect("historical report fixture")
            .records[0]
            .result,
        ResultKind::Error
    );
    check_report(root.path(), &over_limit).unwrap();
    let mut forged = at_limit;
    forged
        .as_historical_mut()
        .expect("historical report fixture")
        .records[0]
        .observed = Some(Observation::parse(observed).unwrap());
    assert!(check_report(root.path(), &Report::from_json(&forged.to_json()).unwrap()).is_err());
}
