use super::*;
use serde_json::{Value, json};

fn capabilities() -> Value {
    json!({"suite":"workbench","contractVersion":CAPABILITY_POLICY_VERSION,
        "binding":"policy-infrastructure-test","language":"test",
        "operations":["run-capability-policy"],"formats":["json"]})
}
#[test]
fn capability_policy_negotiates_only_exact_json_operation() {
    Capabilities::parse(capabilities(), CAPABILITY_POLICY_VERSION).unwrap();
    for (field, value) in [
        ("contractVersion", json!("0.1.0-draft.12+local")),
        ("contractVersion", json!(SELECTED_SCHEME_VERSION)),
        ("operations", json!(["run-selected-scheme"])),
        ("formats", json!(["ion-text"])),
    ] {
        let mut bad = capabilities();
        bad[field] = value;
        assert!(Capabilities::parse(bad, CAPABILITY_POLICY_VERSION).is_err());
    }
    let mut no_claim = capabilities();
    no_claim["operations"] = json!([]);
    Capabilities::parse(no_claim, CAPABILITY_POLICY_VERSION).unwrap();
}

fn fixture() -> Value {
    serde_json::from_str::<Value>(include_str!(
        "../../../../spec/workbench/mck/draft.12/cases.json"
    ))
    .unwrap()["cases"][0]
        .clone()
}
fn small_corpus(root: &std::path::Path, case: Value) -> Result<Corpus, String> {
    std::fs::write(
        root.join("cases.json"),
        json!({"formatVersion":CAPABILITY_POLICY_VERSION,"cases":[case]}).to_string(),
    )
    .unwrap();
    load(root)
}
struct Reply(Value);
impl Testee for Reply {
    fn exchange(&mut self, request: &Value) -> Result<Value, String> {
        assert!(request.get("expected").is_none() && request.get("caseId").is_none());
        if request["op"] == "capabilities" {
            Ok(capabilities())
        } else {
            assert_eq!(request["op"], "run-capability-policy");
            Ok(self.0.clone())
        }
    }
}
#[test]
fn capability_policy_fixed_inventory_runs_and_rechecks_without_decoding_sources() {
    let root =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/workbench/mck/draft.12");
    let corpus = load(&root).unwrap();
    assert_eq!(corpus.case_count(), 182);
    struct Replay(std::collections::VecDeque<Value>);
    impl Testee for Replay {
        fn exchange(&mut self, request: &Value) -> Result<Value, String> {
            assert!(request.get("expected").is_none() && request.get("caseId").is_none());
            self.0
                .pop_front()
                .ok_or("exhausted infrastructure replay".into())
        }
    }
    let mut replay = Replay(
        std::iter::once(capabilities())
            .chain(
                corpus
                    .cases
                    .iter()
                    .map(|c| serde_json::to_value(&c.expected).unwrap()),
            )
            .collect(),
    );
    let report = execute(&corpus, &mut replay);
    assert!(report.qualified, "{:?}", report.errors);
    check_report(&root, &Report::from_json(&report.to_json()).unwrap()).unwrap();
}
#[test]
fn capability_policy_literal_schema_closes_infrastructure_but_keeps_sources_opaque() {
    let root = tempfile::tempdir().unwrap();
    for kind in [
        "model-marker",
        "policy-marker",
        "call-marker",
        "unknown",
        "completion-marker",
        "adjacent",
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
            "call-marker" => {
                case["input"]["calls"][0]["id"] =
                    json!({"$serde_json::private::RawValue":"\"first\""})
            }
            "unknown" => case["input"]["manifest"] = json!({}),
            "completion-marker" => {
                case["input"]["completion"] =
                    json!({"format":"json","source":{"$serde_json::private::RawValue":"\"{}\""}})
            }
            "adjacent" => case["input"]["admission"]["contractVersion"] = json!("0.1.0-draft.2"),
            _ => unreachable!(),
        }
        assert!(small_corpus(root.path(), case).is_err(), "{kind}");
    }
    let mut opaque = fixture();
    opaque["input"]["model"] = json!("not decoded by runner");
    opaque["input"]["calls"][0]["inputs"]["source"] = json!("[");
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
fn capability_policy_report_recomputes_scope_policy_boundary_terminal_and_corpus_identity() {
    let root = tempfile::tempdir().unwrap();
    let case = fixture();
    let corpus = small_corpus(root.path(), case.clone()).unwrap();
    let report = execute(&corpus, &mut Reply(case["expected"].clone()));
    assert!(report.qualified);
    let saved = serde_json::to_value(&report).unwrap();
    for kind in [
        "scope",
        "policy",
        "boundary",
        "terminal",
        "qualified",
        "result",
        "hash",
        "private",
    ] {
        let mut bad = saved.clone();
        match kind {
            "scope" => {
                bad["records"][0]["observed"]["value"]["mode"] = json!("validate-completion")
            }
            "policy" => bad["records"][0]["observed"]["value"]["policy"] = json!("strict"),
            "boundary" => bad["records"][0]["observed"]["value"]["boundary"] = json!("{}"),
            "terminal" => {
                bad["records"][0]["observed"]["value"]["outcomes"]["calls"][0]["outcome"]["value"]
                    ["value"] = json!("41")
            }
            "qualified" => bad["qualified"] = json!(false),
            "result" => bad["records"][0]["result"] = json!("fail"),
            "hash" => bad["corpusHash"] = json!("0".repeat(64)),
            "private" => {
                bad["records"][0]["observed"]["value"]["outcomes"]["calls"][0]["outcome"]["value"] =
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
    let mut mismatch = case["expected"].clone();
    mismatch["value"]["outcomes"]["calls"][0]["outcome"]["value"]["value"] = json!("41");
    let failed = execute(&corpus, &mut Reply(mismatch));
    assert_eq!(failed.records[0].result, ResultKind::Fail);
    check_report(root.path(), &failed).unwrap();
    let malformed = execute(
        &corpus,
        &mut Reply(json!({"status":"invalid","code":"scheme.unbound"})),
    );
    assert_eq!(malformed.records[0].result, ResultKind::Error);
    check_report(root.path(), &malformed).unwrap();
    let mut bytes = std::fs::read(root.path().join("cases.json")).unwrap();
    bytes.push(b' ');
    std::fs::write(root.path().join("cases.json"), bytes).unwrap();
    assert!(check_report(root.path(), &report).is_err());
}

#[test]
fn capability_policy_terminal_and_projection_resources_are_infrastructure_gates() {
    let root = tempfile::tempdir().unwrap();
    let case = fixture();
    let corpus = small_corpus(root.path(), case.clone()).unwrap();
    for kind in [
        "duplicate-call",
        "nonterminal",
        "reserved-failure",
        "long-code",
        "oversized",
    ] {
        let mut value = case["expected"].clone();
        match kind {
            "duplicate-call" => {
                let c = value["value"]["outcomes"]["calls"][0].clone();
                value["value"]["outcomes"]["calls"]
                    .as_array_mut()
                    .unwrap()
                    .push(c);
            }
            "nonterminal" => {
                value["value"]["outcomes"]["calls"][0]["outcome"] = json!({"status":"running"})
            }
            "reserved-failure" => {
                value["value"]["outcomes"]["calls"][0]["outcome"] = json!({"status":"failed","failure":{"stage":"evaluate","code":"execution.cancelled","message":""}})
            }
            "long-code" => {
                value["value"]["boundary"] = Value::Null;
                value["value"]["outcomes"] = Value::Null;
                value["value"]["failure"] = json!({"stage":"plan","code":"😀".repeat(65)})
            }
            "oversized" => value["value"]["boundary"] = json!("x".repeat(MAX_VALUE_BYTES)),
            _ => unreachable!(),
        }
        let report = execute(&corpus, &mut Reply(value));
        assert_eq!(report.records[0].result, ResultKind::Error, "{kind}");
        check_report(root.path(), &report).unwrap();
    }
    let mut oversized = fixture();
    oversized["input"]["model"] = json!("é".repeat(262144));
    oversized["input"]["calls"][0]["inputs"]["source"] = json!("é".repeat(262144));
    assert!(small_corpus(root.path(), oversized).is_err());
}
