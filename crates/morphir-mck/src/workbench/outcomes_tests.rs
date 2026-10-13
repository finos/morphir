use super::*;
use serde_json::{Value, json};

fn operation() -> Operation {
    serde_json::from_value(json!("validate-outcomes")).unwrap()
}

fn envelope() -> Value {
    json!({"contractVersion":"0.1.0-draft.5", "calls":[
        {"id":"first", "outcome":{"status":"returned", "value":{"type":"int","value":"42"}}}
    ],"cleanup":null,"extensions":null})
}

#[test]
fn terminal_operation_is_exact_draft_and_has_its_own_projection() {
    let operation = operation();
    let caps = json!({"suite":"workbench","contractVersion":"0.1.0-draft.5",
        "binding":"fixture","language":"test", "operations":["decode-value","validate-value",
        "validate-invocations","validate-output","validate-outcomes"],"formats":["json","ion-text"]});
    let admitted = Capabilities::parse(caps.clone(), "0.1.0-draft.5").unwrap();
    assert!(admitted.supports(operation, Format::Json));
    for version in [
        VERSION,
        ADMISSION_VERSION,
        INVOCATION_VERSION,
        OUTPUT_VERSION,
    ] {
        let mut old = caps.clone();
        old["contractVersion"] = json!(version);
        assert!(Capabilities::parse(old, version).is_err());
    }
    let returned = Observation::parse(json!({"status":"ok","value":envelope()})).unwrap();
    returned.validate_for(operation).unwrap();
    assert!(returned.validate_for(Operation::ValidateOutput).is_err());
    let bare =
        Observation::parse(json!({"status":"ok","value":{"type":"int","value":"42"}})).unwrap();
    assert!(bare.validate_for(operation).is_err());
}

#[test]
fn terminal_projection_preserves_primary_and_cleanup_and_rejects_contradictions() {
    let operation = operation();
    let mut value = envelope();
    value["calls"][0]["outcome"] = json!({"status":"failed", "failure":{
        "stage":"invoke","code":"provider.crash","message":"Invocation failed"}});
    value["cleanup"] =
        json!({"stage":"cleanup","code":"provider.dispose","message":"Disposal failed"});
    let admitted = Observation::parse(json!({"status":"ok","value":value})).unwrap();
    admitted.validate_for(operation).unwrap();
    let mut swapped = value.clone();
    swapped["calls"][0]["outcome"]["failure"]["code"] = json!("provider.dispose");
    let other = Observation::parse(json!({"status":"ok","value":swapped})).unwrap();
    assert!(!admitted.matches(&other, operation).unwrap());
    let mut contradictory = value.clone();
    contradictory["calls"][0]["outcome"]["value"] = json!({"type":"int","value":"42"});
    let invalid = Observation::parse(json!({"status":"ok","value":contradictory})).unwrap();
    assert!(invalid.validate_for(operation).is_err());
    let mut cleanup = value.clone();
    cleanup["cleanup"]["stage"] = json!("invoke");
    let invalid = Observation::parse(json!({"status":"ok","value":cleanup})).unwrap();
    assert!(invalid.validate_for(operation).is_err());
}

struct Replay {
    replies: std::collections::VecDeque<Value>,
    requests: Vec<Value>,
}

impl Testee for Replay {
    fn exchange(&mut self, request: &Value) -> Result<Value, String> {
        self.requests.push(request.clone());
        self.replies
            .pop_front()
            .ok_or_else(|| "unexpected request".into())
    }
}

#[test]
fn terminal_corpus_retains_history_and_report_operation_evidence() {
    let root =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/workbench/mck/draft.5");
    let old = load(&root.join("../draft.4")).unwrap();
    let corpus = load(&root).unwrap();
    assert_eq!(corpus.case_count(), 377);
    for (before, after) in old.cases.iter().zip(&corpus.cases) {
        assert_eq!(before.id, after.id);
        assert_eq!(before.operation(), after.operation());
        assert_eq!(before.format, after.format);
        assert_eq!(before.input, after.input);
        assert_eq!(before.expected, after.expected);
    }
    assert_eq!(
        corpus
            .cases
            .iter()
            .filter(|c| c.operation() == operation())
            .count(),
        86
    );
    for format in [Format::Json, Format::IonText] {
        for successful in [true, false] {
            assert!(corpus.cases.iter().any(|c| c.operation() == operation()
                && c.format == format
                && matches!(c.expected, Observation::Ok { .. }) == successful));
        }
    }
    let caps = json!({"suite":"workbench","contractVersion":OUTCOMES_VERSION,
        "binding":"fixture","language":"test",
        "operations":["decode-value","validate-value","validate-invocations","validate-output","validate-outcomes"],
        "formats":["json","ion-text"]});
    // Fixed replay checks report evidence. It does not qualify an implementation.
    let mut replay = Replay {
        replies: std::iter::once(caps)
            .chain(
                corpus
                    .cases
                    .iter()
                    .map(|c| serde_json::to_value(&c.expected).unwrap()),
            )
            .collect(),
        requests: vec![],
    };
    let report = execute(&corpus, &mut replay);
    assert!(report.qualified);
    check_report(&root, &report).unwrap();
    assert!(
        replay
            .requests
            .iter()
            .all(|r| r.get("expected").is_none() && r.get("caseId").is_none())
    );
    let index = corpus
        .cases
        .iter()
        .position(|c| c.id == "terminal-exact-int-json")
        .unwrap();
    for replacement in [json!("validate-output"), json!("validate-invocations")] {
        let mut forged = serde_json::to_value(&report).unwrap();
        forged["records"][index]["operation"] = replacement;
        assert!(check_report(&root, &Report::from_json(&forged.to_string()).unwrap()).is_err());
    }
    let mut forged = serde_json::to_value(&report).unwrap();
    forged["records"][index]["observed"]["value"]["calls"][0]["outcome"]["value"]["value"] =
        json!("43");
    assert!(check_report(&root, &Report::from_json(&forged.to_string()).unwrap()).is_err());
}

#[test]
fn terminal_projection_preserves_order_and_enforces_utf16_and_reserved_codes() {
    let mut value = envelope();
    value["calls"][0]["outcome"] = json!({"status":"failed", "failure":{
        "stage":"invoke","code":"x".repeat(128),"message":"😀".repeat(256)}});
    value["calls"]
        .as_array_mut()
        .unwrap()
        .push(json!({"id":"second","outcome":{"status":"cancelled"}}));
    let admitted = Observation::parse(json!({"status":"ok","value":value})).unwrap();
    admitted.validate_for(operation()).unwrap();
    for (field, replacement) in [
        ("code", json!("😀".repeat(65))),
        ("message", json!("😀".repeat(257))),
        ("code", json!("execution.cancelled")),
        ("code", json!("sdk.division_by_zero")),
    ] {
        let mut invalid = value.clone();
        invalid["calls"][0]["outcome"]["failure"][field] = replacement;
        assert!(
            Observation::parse(json!({"status":"ok","value":invalid}))
                .unwrap()
                .validate_for(operation())
                .is_err()
        );
    }
    let mut reordered = value.clone();
    reordered["calls"].as_array_mut().unwrap().reverse();
    assert!(
        !admitted
            .matches(
                &Observation::parse(json!({"status":"ok","value":reordered})).unwrap(),
                operation()
            )
            .unwrap()
    );
    let mut duplicate = value.clone();
    duplicate["calls"][1]["id"] = json!("first");
    assert!(
        Observation::parse(json!({"status":"ok","value":duplicate}))
            .unwrap()
            .validate_for(operation())
            .is_err()
    );
}
