use super::*;
use serde_json::json;

#[test]
fn worksheet_capabilities_are_exact_and_operation_scoped() {
    let caps = json!({"suite":"workbench","contractVersion":"0.1.0-draft.27","binding":"test","language":"test","operations":["worksheet-evaluate","worksheet-validate"],"formats":["json"]});
    Capabilities::parse(caps.clone(), "0.1.0-draft.27").unwrap();
    for operation in ["worksheet-evaluate", "worksheet-validate"] {
        let mut scoped = caps.clone();
        scoped["operations"] = json!([operation]);
        Capabilities::parse(scoped, "0.1.0-draft.27").unwrap();
    }
    for change in [
        json!({"formats":["ion-text"]}),
        json!({"operations":["decode-value"]}),
        json!({"contractVersion":"0.1.0-draft.27+build"}),
    ] {
        let mut bad = caps.clone();
        for (key, value) in change.as_object().unwrap() {
            bad[key] = value.clone();
        }
        assert!(Capabilities::parse(bad, "0.1.0-draft.27").is_err());
    }
}

fn report() -> serde_json::Value {
    json!({"profile":"morphir/workbench/worksheet","contractVersion":"0.1.0-draft.1","source":{"id":"worksheet-source","revision":4,"text":"(+ 1 2)"},"observations":[{"id":"form-0","range":{"start":0,"end":7},"expression":"(+ 1 2)","preview":"3","outcome":{"status":"returned","value":{"type":"int","value":"3"}}}],"completion":{"status":"returned","value":{"type":"unit"}},"diagnostic":null})
}

#[test]
fn worksheet_projection_checks_ranges_capture_and_terminal_payloads() {
    let good = report();
    super::worksheet::projection(&good, Operation::WorksheetEvaluate).unwrap();
    for pointer in [
        "/observations/0/range/end",
        "/observations/0/expression",
        "/observations/0/id",
        "/completion/value/type",
    ] {
        let mut bad = good.clone();
        *bad.pointer_mut(pointer).unwrap() = json!("forged");
        assert!(super::worksheet::projection(&bad, Operation::WorksheetEvaluate).is_err());
    }
    let mut unicode = good.clone();
    unicode["source"]["text"] = json!("😀x");
    unicode["observations"][0]["range"] = json!({"start":1,"end":3});
    unicode["observations"][0]["expression"] = json!("x");
    assert!(super::worksheet::projection(&unicode, Operation::WorksheetEvaluate).is_err());
}

struct Fixed {
    operations: Vec<&'static str>,
    answers: std::collections::VecDeque<serde_json::Value>,
}
impl Testee for Fixed {
    fn exchange(&mut self, request: &serde_json::Value) -> Result<serde_json::Value, String> {
        assert!(request.get("expected").is_none() && request.get("caseId").is_none());
        if request["op"] == "capabilities" {
            Ok(
                json!({"suite":"workbench","contractVersion":"0.1.0-draft.27","binding":"infrastructure-only","language":"test","operations":self.operations,"formats":["json"]}),
            )
        } else {
            self.answers
                .pop_front()
                .ok_or("unexpected adapter request".into())
        }
    }
}
fn kit(scope: &str) -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../spec/workbench/mck/draft.27")
        .join(scope)
}
fn fixed(scope: &str, operations: Vec<&'static str>) -> Fixed {
    let value: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(kit(scope).join("cases.json")).unwrap())
            .unwrap();
    Fixed {
        operations,
        answers: value["cases"]
            .as_array()
            .unwrap()
            .iter()
            .map(|case| case["expected"].clone())
            .collect(),
    }
}
#[test]
fn worksheet_fixed_corpora_are_independent_and_scoped() {
    for (scope, operations) in [
        ("", vec!["worksheet-evaluate", "worksheet-validate"]),
        ("evaluate", vec!["worksheet-evaluate"]),
        ("validate", vec!["worksheet-validate"]),
    ] {
        let corpus = load(&kit(scope)).unwrap();
        assert_eq!(
            corpus.case_count(),
            match scope {
                "" => 108,
                "evaluate" => 46,
                "validate" => 62,
                _ => unreachable!(),
            }
        );
        let report = execute(&corpus, &mut fixed(scope, operations));
        assert!(report.qualified, "{scope}: {:?}", report.errors);
        check_report(&kit(scope), &Report::from_json(&report.to_json()).unwrap()).unwrap();
        for pointer in [
            "/records/2/observed/value/source/revision",
            "/records/2/observed/value/observations/0/range/end",
            "/records/2/observed/value/observations/0/outcome/value/value",
        ] {
            let mut forged: serde_json::Value = serde_json::from_str(&report.to_json()).unwrap();
            if let Some(value) = forged.pointer_mut(pointer) {
                *value = json!(999);
                assert!(
                    Report::from_json(&forged.to_string())
                        .and_then(|r| check_report(&kit(scope), &r))
                        .is_err()
                );
            }
        }
    }
    let corpus = load(&kit("")).unwrap();
    let report = execute(&corpus, &mut fixed("evaluate", vec!["worksheet-evaluate"]));
    assert!(
        !report.qualified,
        "single operation cannot qualify the complete kit"
    );
}
#[test]
fn worksheet_terminal_context_and_shared_value_budgets_are_checked() {
    let mut bad = report();
    bad["completion"] = json!({"status":"cancelled"});
    assert!(super::worksheet::projection(&bad, Operation::WorksheetEvaluate).is_err());
    let mut bad = report();
    bad["observations"][0]["outcome"] =
        json!({"status":"returned","value":{"type":"text","units":vec![97;100000]}});
    assert!(super::worksheet::projection(&bad, Operation::WorksheetEvaluate).is_err());
    let mut bad = report();
    bad["observations"][0]["outcome"] = json!({"status":"returned","value":{"type":"custom","owner":"invented","tag":"rational","items":[]}});
    assert!(super::worksheet::projection(&bad, Operation::WorksheetEvaluate).is_err());
}
#[test]
fn worksheet_raw_inputs_remain_opaque_and_wrong_operation_refuses() {
    let raw = json!({"request":"{\"source\":\"one\",\"source\":\"two\"}"});
    super::worksheet::validate_input(&raw, Operation::WorksheetEvaluate).unwrap();
    assert!(super::worksheet::validate_input(&raw, Operation::WorksheetValidate).is_err());
    assert!(
        super::worksheet::validate_input(
            &json!({"request":"{}","report":"{}"}),
            Operation::WorksheetEvaluate
        )
        .is_err()
    );
}

#[test]
fn worksheet_shared_budget_spans_rows_and_nonfinite_values_are_unavailable() {
    let mut bad = report();
    bad["observations"][0]["outcome"] =
        json!({"status":"returned","value":{"type":"float64","bits":"9218868437227405312"}});
    assert!(super::worksheet::projection(&bad, Operation::WorksheetEvaluate).is_err());
    let mut rows = report();
    rows["source"]["text"] = json!("1\n2");
    rows["observations"] = json!([{"id":"form-0","range":{"start":0,"end":1},"expression":"1","preview":"text","outcome":{"status":"returned","value":{"type":"text","units":vec![97;60000]}}},{"id":"form-1","range":{"start":2,"end":3},"expression":"2","preview":"text","outcome":{"status":"returned","value":{"type":"text","units":vec![98;60000]}}}]);
    assert!(super::worksheet::projection(&rows, Operation::WorksheetEvaluate).is_err());
}

#[test]
fn worksheet_large_terminal_uses_report_budget_not_frozen_envelope_budget() {
    let mut large = report();
    large["observations"][0]["outcome"]["value"] = json!({"type":"list","items":vec![json!({"type":"int","value":"12345678901234567890"});25000]});
    let bytes = serde_json::to_vec(&large).unwrap().len();
    assert!(bytes > 1024 * 1024 && bytes < 2 * 1024 * 1024);
    super::worksheet::projection(&large, Operation::WorksheetValidate).unwrap();
    assert!(super::contract::projection(&large["observations"][0]["outcome"]["value"]).is_err());
    let envelope = json!({"contractVersion":"0.1.0-draft.5","calls":[{"id":"worksheet","outcome":large["observations"][0]["outcome"]}],"cleanup":null,"extensions":null});
    assert!(super::outcomes::projection(&envelope).is_err());
    large["observations"][0]["outcome"]["value"]["items"] = json!(vec![
        json!({"type":"int","value":"12345678901234567890"});
        50000
    ]);
    assert!(serde_json::to_vec(&large).unwrap().len() > 2 * 1024 * 1024);
    assert!(super::worksheet::projection(&large, Operation::WorksheetValidate).is_err());
}

#[test]
fn worksheet_compact_wrapper_budget_is_separate_from_raw_document_limits() {
    let good = json!({"request":"x".repeat(2 * 1024 * 1024),"report":"x".repeat(2 * 1024 * 1024)});
    super::worksheet::validate_input(&good, Operation::WorksheetValidate).unwrap();
    let fitting_escaped = json!({"request":"\0".repeat(699000),"report":"\0".repeat(699000)});
    assert!(serde_json::to_vec(&fitting_escaped).unwrap().len() < 8 * 1024 * 1024);
    super::worksheet::validate_input(&fitting_escaped, Operation::WorksheetValidate).unwrap();
    let escaped = json!({"request":"\0".repeat(720000),"report":"\0".repeat(720000)});
    let bytes = serde_json::to_vec(&escaped).unwrap().len();
    assert!(bytes > 8 * 1024 * 1024 && bytes < 9 * 1024 * 1024);
    assert!(super::worksheet::validate_input(&escaped, Operation::WorksheetValidate).is_err());
}
