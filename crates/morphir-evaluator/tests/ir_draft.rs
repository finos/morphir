use morphir_evaluator::ir_draft::{IrEvaluationReport, IrEvaluationRequest};
use serde_json::{Value, json};

fn fixed_request() -> Value {
    serde_json::from_str(include_str!(
        "../../../spec/ir/semantics/v3/cases/evaluation/five-cases.request.json"
    ))
    .unwrap()
}

#[test]
fn draft_ir_request_evaluates_five_fixed_v3_cases() {
    let request = IrEvaluationRequest::from_value(fixed_request()).unwrap();
    let expected: IrEvaluationReport = serde_json::from_str(include_str!(
        "../../../spec/ir/semantics/v3/cases/evaluation/five-cases.report.json"
    ))
    .unwrap();
    assert_eq!(request.evaluate(), expected);
}

#[test]
fn draft_ir_preflight_rejects_wrong_version_and_arguments() {
    for (pointer, replacement, code) in [
        ("/version", json!(2), "UNSUPPORTED_EVALUATION_VERSION"),
        (
            "/calls/0/arguments/0/type",
            json!(["Unit", {}]),
            "ARGUMENT_TYPE_MISMATCH",
        ),
        (
            "/calls/0/arguments/0/value/value",
            json!("1.5"),
            "VALUE_CODEC_ERROR",
        ),
        (
            "/calls/0/entrypoint",
            json!("morphir/ir-specification:morphir/validation/arity#missing"),
            "UNKNOWN_ENTRYPOINT",
        ),
        ("/limits/fuel", json!(0), "INVALID_LIMITS"),
        ("/calls/0/id", json!(""), "INVALID_CALLS"),
        ("/provider", json!("rego"), "INVALID_IR_PROGRAM"),
        (
            "/program/distribution/distribution/2",
            json!([]),
            "MISSING_DEPENDENCY",
        ),
        (
            "/program/distribution/distribution/2/0/1/modules/0/1/values/0/1/value/output",
            json!(["Unit", {}]),
            "MISSING_DEPENDENCY",
        ),
        (
            "/program/distribution/distribution/3/modules/12/1/value/values/2/1/value/value/outputType",
            json!(["Function", {}, ["Unit", {}], ["Unit", {}]]),
            "UNSUPPORTED_RETURN_CODEC",
        ),
    ] {
        let mut request = fixed_request();
        *request.pointer_mut(pointer).unwrap() = replacement;
        assert_eq!(
            IrEvaluationRequest::from_value(request).unwrap_err().code,
            code,
            "{pointer}"
        );
    }
}

#[test]
fn draft_ir_request_enforces_byte_depth_and_call_bounds() {
    let oversized = vec![b' '; morphir_evaluator::ir_draft::MAX_REQUEST_BYTES + 1];
    assert_eq!(
        IrEvaluationRequest::from_slice(&oversized)
            .unwrap_err()
            .code,
        "REQUEST_TOO_LARGE"
    );

    let mut too_many = fixed_request();
    let call = too_many["calls"][0].clone();
    too_many["calls"] = json!(
        (0..65)
            .map(|index| {
                let mut numbered = call.clone();
                numbered["id"] = json!(format!("call-{index}"));
                numbered
            })
            .collect::<Vec<_>>()
    );
    assert_eq!(
        IrEvaluationRequest::from_value(too_many)
            .err()
            .unwrap()
            .code,
        "INVALID_CALLS"
    );

    let mut too_deep = fixed_request();
    let mut nested = json!(null);
    for _ in 0..65 {
        nested = json!([nested]);
    }
    too_deep["extra"] = nested;
    let encoded = serde_json::to_vec(&too_deep).unwrap();
    assert_eq!(
        IrEvaluationRequest::from_slice(&encoded)
            .err()
            .unwrap()
            .code,
        "REQUEST_TOO_DEEP"
    );
}

#[test]
fn draft_ir_runtime_budget_error_is_a_coded_report() {
    let mut request = fixed_request();
    request["calls"] = json!([request["calls"][0].clone()]);
    request["limits"]["fuel"] = json!(1);
    let report = IrEvaluationRequest::from_value(request).unwrap().evaluate();
    assert_eq!(report.results[0].status, "error");
    assert_eq!(report.results[0].code.as_deref(), Some("FUEL_EXHAUSTED"));
    assert_eq!(
        report.results[0].message.as_deref(),
        Some("Evaluation fuel exhausted")
    );
}
