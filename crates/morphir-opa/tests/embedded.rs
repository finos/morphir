use morphir_evaluator::{EvaluationRequest, Evaluator};
use morphir_opa::RegoEvaluator;
use serde_json::{Value, json};

#[test]
fn embedded_host_roundtrips_the_same_request_and_report_without_files() {
    let wire = json!({
        "version":1,
        "provider":"rego",
        "program":{"kind":"source","language":"rego","modules":[
            {"path":"helper.rego","source":"package helper\nanswer := 42"},
            {"path":"main.rego","source":"package example\ntest_ok if { print(\"hello\"); input.answer == data.helper.answer }"}
        ]},
        "entrypoints":["data.example.test_ok"],
        "input":{"answer":42},
        "timeout_ms":1000
    });
    let request: EvaluationRequest = serde_json::from_value(wire.clone()).unwrap();
    assert_eq!(serde_json::to_value(&request).unwrap(), wire);
    let evaluator: &dyn Evaluator = &RegoEvaluator;
    let report = evaluator.evaluate(&request);
    assert!(!report.has_errors());
    let serialized = serde_json::to_value(&report).unwrap();
    assert_eq!(
        serialized,
        json!({"version":1,"provider":"rego","results":[
            {"entrypoint":"data.example.test_ok","status":"value","value":true}
        ]})
    );
    assert_eq!(report, serde_json::from_value(serialized).unwrap());
}

#[test]
fn errors_do_not_prevent_reporting_later_entrypoints() {
    let request: EvaluationRequest = serde_json::from_value(json!({
        "version":1,"provider":"rego",
        "program":{"kind":"source","language":"rego","modules":[
            {"path":"main.rego","source":"package example\nfail := 1 / 0\nok := true"}
        ]},
        "entrypoints":["data.example.fail","data.example.ok"],
        "input":{},"timeout_ms":1000
    }))
    .unwrap();
    let report: Value = serde_json::to_value(RegoEvaluator.evaluate(&request)).unwrap();
    assert_eq!(report["results"][0]["status"], "error");
    assert_eq!(report["results"][1]["value"], true);
}
