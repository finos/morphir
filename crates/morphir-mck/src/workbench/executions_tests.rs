use super::*;
use serde_json::{Value, json};

const DRAFT: &str = "0.1.0-draft.14";

fn operation() -> Operation {
    serde_json::from_value(json!("reduce-execution")).unwrap()
}

fn capabilities() -> Value {
    json!({"suite":"workbench","contractVersion":DRAFT,
        "binding":"fixed-transcript","language":"test",
        "operations":["reduce-execution"],"formats":["json"]})
}

fn projection() -> Value {
    let identity = json!({"hostId":"host","sessionId":"session","providerId":"provider",
        "executionId":"execution","snapshotId":"snapshot"});
    json!({"identity":identity,"receipt":{"contractVersion":"0.2.0-draft.1",
        "identity":identity,"sequence":0,"state":"submitted","cancelRequested":false,
        "outcomes":null},"connected":true,"cancelAction":"send","observations":[]})
}

fn observation(value: Value) -> Observation {
    Observation::parse(json!({"status":"ok","value":value})).unwrap()
}

#[test]
fn executions_exact_draft_supports_only_reduce_execution_and_json() {
    let op = operation();
    let caps = capabilities();
    Capabilities::parse(caps.clone(), DRAFT).unwrap();
    for version in [
        VERSION,
        ADMISSION_VERSION,
        INVOCATION_VERSION,
        OUTPUT_VERSION,
        OUTCOMES_VERSION,
    ] {
        let mut old = caps.clone();
        old["contractVersion"] = json!(version);
        assert!(Capabilities::parse(old, version).is_err());
    }
    for operation in [
        "decode-value",
        "validate-value",
        "validate-invocations",
        "validate-output",
        "validate-outcomes",
    ] {
        let mut bad = caps.clone();
        bad["operations"] = json!([operation]);
        assert!(Capabilities::parse(bad, DRAFT).is_err());
    }
    let mut ion = caps.clone();
    ion["formats"] = json!(["json", "ion-text"]);
    assert!(Capabilities::parse(ion, DRAFT).is_err());
    for field in ["operations", "formats"] {
        let mut empty = caps.clone();
        empty[field] = json!([]);
        assert!(Capabilities::parse(empty, DRAFT).is_err(), "{field}");
    }
    for version in ["0.1.0-draft.15", "0.1.0-draft.14+local", "v0.1.0-draft.14"] {
        let mut bad = caps.clone();
        bad["contractVersion"] = json!(version);
        assert!(Capabilities::parse(bad, version).is_err());
    }
    observation(projection()).validate_for(op).unwrap();
    assert!(
        observation(projection())
            .validate_for(Operation::ValidateOutcomes)
            .is_err()
    );
}

#[test]
fn executions_projection_rejects_forged_identity_view_and_closed_inventory() {
    let op = operation();
    let valid = projection();
    observation(valid.clone()).validate_for(op).unwrap();
    for field in [
        "hostId",
        "sessionId",
        "providerId",
        "executionId",
        "snapshotId",
    ] {
        let mut invalid = valid.clone();
        invalid["receipt"]["identity"][field] = json!("other");
        assert!(observation(invalid).validate_for(op).is_err());
    }
    let view = json!({"sequence":0,"state":"submitted","cancelRequested":false,
        "connected":true,"cancelAction":"send"});
    let mut valid = valid;
    valid["observations"] = json!([{"op":"cancel-action","status":"local","view":view}]);
    observation(valid.clone()).validate_for(op).unwrap();
    for field in [
        "sequence",
        "state",
        "cancelRequested",
        "connected",
        "cancelAction",
    ] {
        let mut forged = valid.clone();
        forged["observations"][0]["view"][field] = match field {
            "sequence" => json!(1),
            "state" => json!("running"),
            "cancelRequested" => json!(true),
            "connected" => json!(false),
            _ => json!("pending"),
        };
        assert!(observation(forged).validate_for(op).is_err(), "{field}");
    }
    for value in [
        json!({"unexpected":true}),
        json!({"identity":null}),
        json!({"type":"unit"}),
    ] {
        assert!(observation(value).validate_for(op).is_err());
    }
    let mut code = valid.clone();
    code["observations"][0]["code"] = json!("workbench.execution_receipt");
    assert!(observation(code).validate_for(op).is_err());
    let mut missing = valid;
    missing["observations"][0]["status"] = json!("invalid");
    missing["observations"][0]["op"] = json!("observe");
    assert!(observation(missing).validate_for(op).is_err());
}

#[test]
fn executions_acknowledged_connected_view_cannot_claim_unavailable_cancellation() {
    let mut value = projection();
    value["receipt"]["sequence"] = json!(1);
    value["receipt"]["cancelRequested"] = json!(true);
    value["cancelAction"] = json!("unavailable");
    assert!(
        observation(value.clone())
            .validate_for(operation())
            .is_err()
    );
    value["cancelAction"] = json!("pending");
    observation(value).validate_for(operation()).unwrap();
}

#[test]
fn executions_projection_bounds_observations_and_utf16_and_admits_nested_terminal_values() {
    let op = operation();
    let mut value = projection();
    value["identity"]["executionId"] = json!("😀".repeat(64));
    value["receipt"]["identity"] = value["identity"].clone();
    observation(value.clone()).validate_for(op).unwrap();
    value["identity"]["executionId"] = json!("😀".repeat(65));
    value["receipt"]["identity"] = value["identity"].clone();
    assert!(observation(value).validate_for(op).is_err());

    let mut value = projection();
    let local = json!({"op":"cancel-action","status":"local","view":{
        "sequence":0,"state":"submitted","cancelRequested":false,"connected":true,"cancelAction":"send"}});
    value["observations"] = json!(vec![local.clone(); 64]);
    observation(value.clone()).validate_for(op).unwrap();
    value["observations"].as_array_mut().unwrap().push(local);
    assert!(observation(value).validate_for(op).is_err());

    let mut terminal = projection();
    terminal["receipt"]["sequence"] = json!(2);
    terminal["receipt"]["state"] = json!("terminal");
    terminal["cancelAction"] = json!("already-terminal");
    let fields = json!([{"name":"z","value":{"type":"int","value":"9007199254740993"}},
        {"name":"a","value":{"type":"unit"}}]);
    terminal["receipt"]["outcomes"] = json!({"contractVersion":"0.1.0-draft.5",
        "calls":[{"id":"c","outcome":{"status":"returned","value":{"type":"record","fields":fields}}}],
        "cleanup":{"stage":"cleanup","code":"dispose.failed","message":"cleanup failed"},"extensions":null});
    observation(terminal.clone()).validate_for(op).unwrap();
    let mut reordered = terminal.clone();
    reordered["receipt"]["outcomes"]["calls"][0]["outcome"]["value"]["fields"]
        .as_array_mut()
        .unwrap()
        .reverse();
    assert!(
        observation(terminal.clone())
            .matches(&observation(reordered), op)
            .unwrap()
    );
    for field in ["code", "message"] {
        let mut invalid = terminal.clone();
        invalid["receipt"]["outcomes"]["cleanup"][field] = json!("😀".repeat(257));
        assert!(observation(invalid).validate_for(op).is_err());
    }
    let mut invalid = terminal.clone();
    invalid["receipt"]["outcomes"]["calls"][0]["outcome"]["value"]["fields"][0]["value"]["value"] =
        json!("01");
    assert!(observation(invalid).validate_for(op).is_err());
    let mut swapped = terminal;
    swapped["receipt"]["outcomes"]["cleanup"]["stage"] = json!("invoke");
    assert!(observation(swapped).validate_for(op).is_err());
}

fn corpus_file(root: &std::path::Path, format: &str, input: Value) {
    std::fs::write(
        root.join("cases.json"),
        json!({"formatVersion":DRAFT,"cases":[
            {"id":"trace","operation":"reduce-execution","format":format,"input":input,
            "expected":{"status":"invalid","code":"workbench.invalid_execution_trace"}}
        ]})
        .to_string(),
    )
    .unwrap();
}

#[test]
fn executions_corpus_keeps_negative_inputs_opaque_and_rejects_wrong_format_or_operation() {
    let root = tempfile::tempdir().unwrap();
    for input in [
        json!(null),
        json!(7),
        json!("bad"),
        json!([]),
        json!({"malformed":true}),
    ] {
        corpus_file(root.path(), "json", input);
        load(root.path()).unwrap();
    }
    corpus_file(root.path(), "ion-text", json!("null"));
    assert!(load(root.path()).is_err());
    corpus_file(root.path(), "json", json!("x".repeat(MAX_VALUE_BYTES)));
    assert!(load(root.path()).is_err());
    corpus_file(root.path(), "json", json!(null));
    let path = root.path().join("cases.json");
    let original: Value = serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
    for operation in [json!("decode-value"), json!(null)] {
        let mut invalid = original.clone();
        invalid["cases"][0]["operation"] = operation;
        std::fs::write(&path, invalid.to_string()).unwrap();
        assert!(load(root.path()).is_err());
    }
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
fn executions_fixed_corpus_replay_recomputes_report_evidence_and_does_not_leak_expectations() {
    let root =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/workbench/mck/draft.14");
    let corpus = load(&root).unwrap();
    assert_eq!(corpus.case_count(), 170);
    assert!(
        corpus
            .cases
            .iter()
            .all(|case| case.operation() == operation() && case.format == Format::Json)
    );
    // Replay exercises the shared verdict and report boundary only. It is not
    // an adapter implementation and does not qualify execution-reducer behavior.
    let mut replay = Replay {
        replies: std::iter::once(capabilities())
            .chain(
                corpus
                    .cases
                    .iter()
                    .map(|case| serde_json::to_value(&case.expected).unwrap()),
            )
            .collect(),
        requests: vec![],
    };
    let report = execute(&corpus, &mut replay);
    assert!(
        report.qualified,
        "{} {:?}",
        report.summary_line(),
        report.errors
    );
    check_report(&root, &report).unwrap();
    assert!(
        replay
            .requests
            .iter()
            .all(|request| request.get("expected").is_none() && request.get("caseId").is_none())
    );
    assert_eq!(replay.requests[0]["contractVersion"], DRAFT);
    assert!(
        replay.requests[1..]
            .iter()
            .all(|request| request["op"] == "reduce-execution" && request["format"] == "json")
    );
    let index = corpus
        .cases
        .iter()
        .position(|case| matches!(case.expected, Observation::Ok { .. }))
        .unwrap();
    let saved = serde_json::to_value(&report).unwrap();
    for mutation in [
        "sequence",
        "identity",
        "operation",
        "capabilities",
        "qualified",
        "observations",
    ] {
        let mut forged = saved.clone();
        match mutation {
            "sequence" => {
                forged["records"][index]["observed"]["value"]["receipt"]["sequence"] =
                    json!(2147483647)
            }
            "identity" => {
                forged["records"][index]["observed"]["value"]["identity"]["executionId"] =
                    json!("other")
            }
            "operation" => forged["records"][index]["operation"] = json!("validate-outcomes"),
            "capabilities" => forged["capabilities"]["contractVersion"] = json!(OUTCOMES_VERSION),
            "qualified" => forged["qualified"] = json!(false),
            "observations" => {
                forged["records"][index]["observed"]["value"]["observations"] = json!([])
            }
            _ => unreachable!(),
        }
        // The first successful trace may itself have no actions. Substitute an
        // unknown output member so the observation mutation always changes it.
        if mutation == "observations" {
            forged["records"][index]["observed"]["value"]["extra"] = json!(true);
        }
        assert!(
            Report::from_json(&forged.to_string())
                .and_then(|report| check_report(&root, &report))
                .is_err(),
            "{mutation}"
        );
    }
    let observed_index = corpus
        .cases
        .iter()
        .position(|case| {
            matches!(&case.expected, Observation::Ok { value }
            if value["observations"].as_array().is_some_and(|items| items.iter().any(|item|
                item["op"] == "observe" && item["status"] == "advanced")))
        })
        .unwrap();
    let mut forged = saved;
    let observations = forged["records"][observed_index]["observed"]["value"]["observations"]
        .as_array_mut()
        .unwrap();
    let advanced = observations
        .iter_mut()
        .find(|item| item["op"] == "observe" && item["status"] == "advanced")
        .unwrap();
    advanced["status"] = json!("replay");
    assert!(check_report(&root, &Report::from_json(&forged.to_string()).unwrap()).is_err());
}

#[test]
fn executions_malformed_adapter_projection_is_an_exchange_error_and_valid_difference_fails() {
    let root = tempfile::tempdir().unwrap();
    let write = |expected: Value| {
        std::fs::write(
            root.path().join("cases.json"),
            json!({"formatVersion":DRAFT,"cases":[{"id":"fixed","operation":"reduce-execution",
            "format":"json","input":null,"expected":expected}]})
            .to_string(),
        )
        .unwrap()
    };
    write(json!({"status":"ok","value":projection()}));
    let corpus = load(root.path()).unwrap();
    let mut malformed = Replay {
        replies: [
            capabilities(),
            json!({"status":"ok","value":{"type":"unit"}}),
        ]
        .into(),
        requests: vec![],
    };
    let report = execute(&corpus, &mut malformed);
    assert_eq!(report.records[0].result, ResultKind::Error);
    assert_eq!(report.errors[0].phase, Phase::Exchange);
    assert!(!report.qualified);
    check_report(root.path(), &report).unwrap();

    let mut different = projection();
    different["connected"] = json!(false);
    different["cancelAction"] = json!("disconnected");
    let mut replay = Replay {
        replies: [capabilities(), json!({"status":"ok","value":different})].into(),
        requests: vec![],
    };
    let report = execute(&corpus, &mut replay);
    assert_eq!(report.records[0].result, ResultKind::Fail);
    assert!(report.errors.is_empty());
    assert!(!report.qualified);
    check_report(root.path(), &report).unwrap();
}

#[test]
fn execution_projection_refuses_job_identity_aliases_and_previous_receipt_version() {
    let current = projection();
    for path in ["identity", "receipt"] {
        let mut old = current.clone();
        let identity = if path == "identity" {
            &mut old["identity"]
        } else {
            &mut old["receipt"]["identity"]
        };
        let object = identity.as_object_mut().unwrap();
        let id = object.remove("executionId").unwrap();
        object.insert("jobId".into(), id);
        assert!(observation(old).validate_for(operation()).is_err());
    }
    let mut duplicate = current.clone();
    duplicate["identity"]["jobId"] = json!("old");
    assert!(observation(duplicate).validate_for(operation()).is_err());
    let mut old_version = current;
    old_version["receipt"]["contractVersion"] = json!("0.1.0-draft.1");
    assert!(observation(old_version).validate_for(operation()).is_err());
}

#[test]
fn execution_corpus_preserves_exact_opaque_negative_inputs() {
    let root = tempfile::tempdir().unwrap();
    for token in [
        "1.00000000000000001",
        r#"{"$serde_json::private::RawValue":"7"}"#,
        r#"{"$serde_json::private::Number":"1"}"#,
        r#"{"$serde_json::private::RawValue":false}"#,
    ] {
        let input = format!(r#"{{"initial":{{"sequence":{token}}}}}"#);
        let text = format!(
            r#"{{"formatVersion":"{DRAFT}","cases":[{{"id":"opaque","operation":"reduce-execution","format":"json","input":{input},"expected":{{"status":"invalid","code":"workbench.invalid_execution_trace"}}}}]}}"#
        );
        std::fs::write(root.path().join("cases.json"), text).unwrap();
        let corpus = load(root.path()).unwrap();
        assert_eq!(corpus.cases[0].input.to_string(), input, "{token}");
    }
}

#[test]
fn execution_corpus_refuses_literal_private_marker_expectations() {
    let root = tempfile::tempdir().unwrap();
    let marker = json!({"$serde_json::private::RawValue":projection().to_string()});
    std::fs::write(
        root.path().join("cases.json"),
        json!({"formatVersion":DRAFT,"cases":[{
        "id":"marker","operation":"reduce-execution","format":"json","input":null,
        "expected":{"status":"ok","value":marker}}]})
        .to_string(),
    )
    .unwrap();
    assert!(load(root.path()).is_err());
}

#[test]
fn execution_saved_report_refuses_literal_private_marker_projections() {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(
        root.path().join("cases.json"),
        json!({"formatVersion":DRAFT,"cases":[{
        "id":"marker","operation":"reduce-execution","format":"json","input":null,
        "expected":{"status":"ok","value":projection()}}]})
        .to_string(),
    )
    .unwrap();
    let corpus = load(root.path()).unwrap();
    let mut replay = Replay {
        replies: [capabilities(), json!({"status":"ok","value":projection()})].into(),
        requests: vec![],
    };
    let report = execute(&corpus, &mut replay);
    assert!(report.qualified);
    let mut saved: Value = serde_json::from_str(&report.to_json()).unwrap();
    saved["records"][0]["observed"]["value"] =
        json!({"$serde_json::private::RawValue":projection().to_string()});
    assert!(Report::from_json(&saved.to_string()).is_err());
}
