use super::*;
use serde_json::json;

#[test]
fn native_client_negotiates_only_its_exact_json_operation() {
    let caps = json!({"suite":"workbench","contractVersion":"0.1.0-draft.9",
        "binding":"production-client","language":"typescript",
        "operations":["run-native-client"],"formats":["json"]});
    Capabilities::parse(caps.clone(), "0.1.0-draft.9").unwrap();
    for (field, value) in [
        ("operations", json!([])),
        ("operations", json!(["validate-native-reply"])),
        ("formats", json!(["ion-text"])),
        ("contractVersion", json!("0.1.0-draft.9+local")),
    ] {
        let mut bad = caps.clone();
        bad[field] = value;
        assert!(Capabilities::parse(bad, "0.1.0-draft.9").is_err());
    }
}

#[test]
fn native_client_corpus_uses_fixed_opaque_scenarios_and_recomputed_reports() {
    let root =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/workbench/mck/draft.9");
    let corpus = load(&root).unwrap();
    assert_eq!(corpus.case_count(), 48);
    struct Replay {
        replies: std::collections::VecDeque<serde_json::Value>,
    }
    impl Testee for Replay {
        fn exchange(&mut self, request: &serde_json::Value) -> Result<serde_json::Value, String> {
            assert!(request.get("expected").is_none() && request.get("caseId").is_none());
            self.replies.pop_front().ok_or("exhausted".into())
        }
    }
    let caps = json!({"suite":"workbench","contractVersion":"0.1.0-draft.9","binding":"transcript",
        "language":"test","operations":["run-native-client"],"formats":["json"]});
    let mut replay = Replay {
        replies: std::iter::once(caps)
            .chain(
                corpus
                    .cases
                    .iter()
                    .map(|c| serde_json::to_value(&c.expected).unwrap()),
            )
            .collect(),
    };
    let report = execute(&corpus, &mut replay);
    assert!(report.qualified, "{:?}", report.errors);
    check_report(&root, &report).unwrap();
}

fn fixture() -> serde_json::Value {
    serde_json::from_str::<serde_json::Value>(include_str!(
        "../../../../spec/workbench/mck/draft.9/cases.json"
    ))
    .unwrap()["cases"][0]
        .clone()
}
fn small_corpus(root: &std::path::Path, case: serde_json::Value) -> Result<Corpus, String> {
    std::fs::write(
        root.join("cases.json"),
        json!({"formatVersion":"0.1.0-draft.9","cases":[case]}).to_string(),
    )
    .unwrap();
    load(root)
}
fn caps() -> serde_json::Value {
    json!({"suite":"workbench","contractVersion":"0.1.0-draft.9","binding":"transcript","language":"test","operations":["run-native-client"],"formats":["json"]})
}
struct Reply(serde_json::Value);
impl Testee for Reply {
    fn exchange(&mut self, request: &serde_json::Value) -> Result<serde_json::Value, String> {
        assert!(request.get("expected").is_none() && request.get("caseId").is_none());
        Ok(if request["op"] == "capabilities" {
            caps()
        } else {
            self.0.clone()
        })
    }
}
#[test]
fn native_client_corpus_rejects_malformed_infrastructure_before_execution() {
    let root = tempfile::tempdir().unwrap();
    for kind in [
        "private-bool",
        "private-count",
        "unknown",
        "attempt",
        "invocation",
        "delivery",
        "double-delivery",
        "json-duplicate",
        "json-not-array",
    ] {
        let mut case = fixture();
        match kind {
            "private-bool" => {
                case["input"]["invocations"][0]["held"] =
                    json!({"$serde_json::private::RawValue":"false"})
            }
            "private-count" => {
                case["expected"]["value"]["consumed"] = json!({"$serde_json::private::Number":"2"})
            }
            "unknown" => case["input"]["authority"] = json!(true),
            "attempt" => case["input"]["actions"][1]["id"] = json!("init"),
            "invocation" => {
                case["input"]["invocations"][1]["id"] =
                    case["input"]["invocations"][0]["id"].clone()
            }
            "delivery" => case["input"]["actions"] = json!([{"op":"deliver","call":"absent"}]),
            "double-delivery" => {
                case["input"]["invocations"][0]["held"] = json!(true);
                let id = case["input"]["invocations"][0]["id"].clone();
                case["input"]["actions"] =
                    json!([{"op":"deliver","call":id},{"op":"deliver","call":id}]);
            }
            "json-duplicate" => {
                case["input"]["evaluation"]["inputs"]["source"] = json!("[{\"a\":1,\"a\":2}]")
            }
            "json-not-array" => case["input"]["evaluation"]["inputs"]["source"] = json!("{}"),
            _ => unreachable!(),
        }
        assert!(small_corpus(root.path(), case).is_err(), "{kind}");
    }
}
#[test]
fn native_client_input_budget_counts_encoded_utf8_bytes_exactly() {
    let root = tempfile::tempdir().unwrap();
    let mut case = fixture();
    case["input"]["evaluation"]["model"] = json!(" ".repeat(200_000));
    let current = serde_json::to_vec(&case["input"]).unwrap().len();
    let original = case["input"]["checkSource"].as_str().unwrap().to_owned();
    case["input"]["checkSource"] = json!(format!("{}{}", " ".repeat(491520 - current), original));
    assert_eq!(serde_json::to_vec(&case["input"]).unwrap().len(), 491520);
    small_corpus(root.path(), case.clone()).unwrap();
    case["input"]["checkSource"] = json!(format!(
        "{} ",
        case["input"]["checkSource"].as_str().unwrap()
    ));
    assert!(small_corpus(root.path(), case.clone()).is_err());
    case["input"]["evaluation"]["model"] = json!("\u{00E9}".repeat(250_000));
    assert!(small_corpus(root.path(), case).is_err());
}
#[test]
fn native_client_errors_and_mismatches_have_distinct_truthful_reports() {
    let root = tempfile::tempdir().unwrap();
    let case = fixture();
    let corpus = small_corpus(root.path(), case.clone()).unwrap();
    for observed in [
        json!({"status":"invalid","code":"native.client.invalid"}),
        json!({"status":"ok","value":{"$serde_json::private::RawValue":case["expected"]["value"].to_string()}}),
    ] {
        let report = execute(&corpus, &mut Reply(observed));
        assert!(!report.qualified);
        assert_eq!(report.records[0].result, ResultKind::Error);
        assert_eq!(report.errors[0].phase, Phase::Exchange);
        check_report(root.path(), &Report::from_json(&report.to_json()).unwrap()).unwrap();
    }
    let mut mismatch = case["expected"].clone();
    mismatch["value"]["consumed"] = json!(0);
    let report = execute(&corpus, &mut Reply(mismatch));
    assert!(!report.qualified && report.errors.is_empty());
    assert_eq!(report.records[0].result, ResultKind::Fail);
    check_report(root.path(), &report).unwrap();
    let report = execute(&corpus, &mut Reply(case["expected"].clone()));
    assert!(report.qualified);
    check_report(root.path(), &report).unwrap();
    let saved = serde_json::to_value(&report).unwrap();
    for kind in [
        "qualified",
        "result",
        "operation",
        "hash",
        "capabilities",
        "requests",
        "private",
    ] {
        let mut bad = saved.clone();
        match kind {
            "qualified" => bad["qualified"] = json!(false),
            "result" => bad["records"][0]["result"] = json!("fail"),
            "operation" => bad["records"][0]["operation"] = json!("validate-native-reply"),
            "hash" => bad["corpusHash"] = json!("0".repeat(64)),
            "capabilities" => bad["capabilities"]["contractVersion"] = json!("0.1.0-draft.8"),
            "requests" => bad["records"][0]["observed"]["value"]["requests"] = json!([]),
            "private" => {
                bad["records"][0]["observed"]["value"] =
                    json!({"$serde_json::private::RawValue":case["expected"]["value"].to_string()})
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
    assert!(
        Report::from_json(&report.to_json().replacen("{", "{\"qualified\":false,", 1)).is_err()
    );
    let mut bytes = std::fs::read(root.path().join("cases.json")).unwrap();
    bytes.push(b' ');
    std::fs::write(root.path().join("cases.json"), bytes).unwrap();
    assert!(check_report(root.path(), &report).is_err());
}

#[test]
fn native_client_projection_limit_applies_to_live_and_saved_evidence() {
    let root = tempfile::tempdir().unwrap();
    let case = fixture();
    let corpus = small_corpus(root.path(), case.clone()).unwrap();
    let mut value = case["expected"]["value"].clone();
    value["requests"] = json!([""]);
    let overhead = serde_json::to_vec(&value).unwrap().len();
    let padding = " ".repeat(MAX_VALUE_BYTES - overhead);
    value["requests"] = json!([padding]);
    assert_eq!(serde_json::to_vec(&value).unwrap().len(), MAX_VALUE_BYTES);
    Observation::Ok {
        value: value.clone(),
    }
    .validate_for(Operation::RunNativeClient)
    .unwrap();
    let at_limit = execute(&corpus, &mut Reply(json!({"status":"ok","value":value})));
    assert_eq!(at_limit.records[0].result, ResultKind::Fail);
    check_report(root.path(), &at_limit).unwrap();
    value["requests"][0] = json!(format!("{} ", value["requests"][0].as_str().unwrap()));
    assert!(
        Observation::Ok {
            value: value.clone()
        }
        .validate_for(Operation::RunNativeClient)
        .is_err()
    );
    let over_limit = execute(&corpus, &mut Reply(json!({"status":"ok","value":value})));
    assert_eq!(over_limit.records[0].result, ResultKind::Error);
    assert_eq!(over_limit.errors[0].phase, Phase::Exchange);
    check_report(root.path(), &over_limit).unwrap();
    let mut forged = at_limit;
    forged.records[0].observed = Some(Observation::Ok { value });
    let saved = Report::from_json(&forged.to_json()).unwrap();
    assert!(check_report(root.path(), &saved).is_err());
}
