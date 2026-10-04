use super::*;
use serde_json::{Value, json};

struct Fake {
    replies: Vec<Result<Value, String>>,
    requests: Vec<Value>,
}
impl Testee for Fake {
    fn exchange(&mut self, request: &Value) -> Result<Value, String> {
        self.requests.push(request.clone());
        self.replies.remove(0)
    }
}
fn source(cases: Value) -> tempfile::TempDir {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(
        root.path().join("cases.json"),
        serde_json::to_vec(&json!({
            "formatVersion": VERSION, "cases":cases
        }))
        .unwrap(),
    )
    .unwrap();
    root
}
fn one() -> Value {
    json!([{"id":"int-exact","format":"json","input":{"type":"int","value":"09007199254740993"},
        "expected":{"status":"ok","value":{"type":"int","value":"9007199254740993"}}}])
}
fn caps() -> Value {
    json!({"suite":"workbench","contractVersion":VERSION,"binding":"fixture","language":"test",
        "operations":["decode-value"],"formats":["json","ion-text"]})
}
fn fake(observation: Value) -> Fake {
    Fake {
        replies: vec![Ok(caps()), Ok(observation)],
        requests: vec![],
    }
}

#[test]
fn workbench_expected_results_never_reach_adapter() {
    let root = source(one());
    let kit = load(root.path()).unwrap();
    let mut adapter =
        fake(json!({"status":"ok","value":{"type":"int","value":"9007199254740993"}}));
    let report = execute(&kit, &mut adapter);
    assert!(report.qualified);
    assert_eq!(adapter.requests.len(), 2);
    assert!(
        adapter
            .requests
            .iter()
            .all(|r| r.get("expected").is_none() && r.get("caseId").is_none())
    );
    check_report(root.path(), &report).unwrap();
}

#[test]
fn workbench_wrong_observation_fails_and_forged_verdict_is_rejected() {
    let root = source(one());
    let mut adapter =
        fake(json!({"status":"ok","value":{"type":"int","value":"9007199254740992"}}));
    let mut report = execute(&load(root.path()).unwrap(), &mut adapter);
    assert_eq!(report.records[0].result, ResultKind::Fail);
    assert!(!report.qualified);
    report.records[0].result = ResultKind::Pass;
    report.qualified = true;
    assert!(check_report(root.path(), &report).is_err());
}

#[test]
fn workbench_missing_claim_skips_without_decode() {
    let root = source(one());
    let mut capability = caps();
    capability["formats"] = json!(["ion-text"]);
    let mut adapter = Fake {
        replies: vec![Ok(capability)],
        requests: vec![],
    };
    let report = execute(&load(root.path()).unwrap(), &mut adapter);
    assert_eq!(report.records[0].result, ResultKind::Unsupported);
    assert!(!report.qualified);
    assert_eq!(adapter.requests.len(), 1);
    check_report(root.path(), &report).unwrap();
}

#[test]
fn workbench_wrong_draft_duplicate_claims_and_malformed_observations_fail() {
    let root = source(one());
    let kit = load(root.path()).unwrap();
    for field in ["contractVersion", "formats"] {
        let mut capability = caps();
        capability[field] = if field == "formats" {
            json!(["json", "json"])
        } else {
            json!("0.1.0-draft.2")
        };
        let mut adapter = Fake {
            replies: vec![Ok(capability)],
            requests: vec![],
        };
        let report = execute(&kit, &mut adapter);
        assert!(!report.qualified);
        assert!(!report.errors.is_empty());
        check_report(root.path(), &report).unwrap();
    }
    for malformed in [
        json!({"status":"ok","value":12}),
        json!({"status":"invalid","code":""}),
        json!({"status":"invalid","code":"bad","extra":true}),
    ] {
        let report = execute(&kit, &mut fake(malformed));
        assert!(!report.qualified);
        assert!(!report.errors.is_empty());
        check_report(root.path(), &report).unwrap();
    }
}

#[test]
fn workbench_invalid_corpus_never_becomes_an_executable_kit() {
    for cases in [json!([]), json!([one()[0].clone(), one()[0].clone()])] {
        assert!(load(source(cases).path()).is_err());
    }
    let root = source(one());
    std::fs::write(
        root.path().join("cases.json"),
        "{\"formatVersion\":\"0.1.0-draft.1\",\"formatVersion\":\"0.1.0-draft.1\",\"cases\":[]}",
    )
    .unwrap();
    assert!(load(root.path()).is_err());
}

#[test]
fn workbench_report_rejects_missing_duplicate_changed_and_fabricated_records() {
    let root = source(one());
    let report = execute(
        &load(root.path()).unwrap(),
        &mut fake(one()[0]["expected"].clone()),
    );
    let mut bad = report.clone();
    bad.records.clear();
    assert!(check_report(root.path(), &bad).is_err());
    let mut bad = report.clone();
    bad.records.push(bad.records[0].clone());
    assert!(check_report(root.path(), &bad).is_err());
    let mut bad = report.clone();
    bad.corpus_hash = "0".repeat(64);
    assert!(check_report(root.path(), &bad).is_err());
    let mut bad = report.clone();
    bad.records[0].observed = None;
    assert!(check_report(root.path(), &bad).is_err());
    let mut bad = report.clone();
    bad.errors.push(Failure {
        phase: Phase::Shutdown,
        message: "failed cleanup".into(),
    });
    assert!(check_report(root.path(), &bad).is_err());
    bad.qualified = false;
    check_report(root.path(), &bad).unwrap();
}

#[test]
fn workbench_record_field_order_is_ignored_recursively_and_list_order_is_not() {
    let a = json!({"type":"record","fields":[{"name":"b","value":{"type":"int","value":"2"}},
        {"name":"a","value":{"type":"list","items":[{"type":"int","value":"1"},{"type":"int","value":"2"}]}}]});
    let mut b = a.clone();
    b["fields"].as_array_mut().unwrap().reverse();
    assert_eq!(projection(&a).unwrap(), projection(&b).unwrap());
    b["fields"][0]["value"]["items"]
        .as_array_mut()
        .unwrap()
        .reverse();
    assert_ne!(projection(&a).unwrap(), projection(&b).unwrap());
    let duplicate = json!({"type":"record","fields":[{"name":"x","value":{"type":"unit"}},
        {"name":"x","value":{"type":"unit"}}]});
    assert!(projection(&duplicate).is_err());
}

#[test]
fn workbench_model_errors_are_top_level_codec_values_only() {
    assert!(projection(&json!({"type":"model-error","code":"sdk.division_by_zero"})).is_ok());
    assert!(projection(&json!({"type":"model-error","code":"provider.crash"})).is_err());
    assert!(
        projection(
            &json!({"type":"list","items":[{"type":"model-error","code":"sdk.division_by_zero"}]})
        )
        .is_err()
    );
}

#[test]
fn workbench_report_wire_requires_nullable_members() {
    let root = source(one());
    let report = execute(
        &load(root.path()).unwrap(),
        &mut fake(one()[0]["expected"].clone()),
    );
    let mut value = serde_json::to_value(&report).unwrap();
    value.as_object_mut().unwrap().remove("capabilities");
    assert!(Report::from_json(&value.to_string()).is_err());
    let mut value = serde_json::to_value(&report).unwrap();
    value["records"][0]
        .as_object_mut()
        .unwrap()
        .remove("observed");
    assert!(Report::from_json(&value.to_string()).is_err());
}

#[test]
fn workbench_lost_transport_does_not_become_a_domain_rejection() {
    let root = source(one());
    let mut adapter = Fake {
        replies: vec![Ok(caps()), Err("adapter connection lost".into())],
        requests: vec![],
    };
    let report = execute(&load(root.path()).unwrap(), &mut adapter);
    assert!(!report.qualified);
    assert_eq!(report.errors[0].phase, Phase::Exchange);
    assert_eq!(report.records[0].result, ResultKind::Error);
    assert!(report.records[0].observed.is_none());
    check_report(root.path(), &report).unwrap();
}

#[test]
fn workbench_spawn_failure_still_produces_checkable_evidence() {
    let root = source(one());
    let options = RunOptions {
        adapter: root.path().join("absent-adapter").into_os_string(),
        adapter_args: vec![],
        limits: crate::transport::Limits::DEFAULT,
    };
    let report = run(root.path(), &options).unwrap();
    assert!(!report.qualified);
    assert_eq!(report.errors[0].phase, Phase::Spawn);
    assert_eq!(report.records.len(), 1);
    check_report(root.path(), &report).unwrap();
}

#[test]
fn workbench_invalid_rejection_is_an_observation_and_decimal_payload_is_preserved() {
    let cases = json!([
        {"id":"rejected","format":"json","input":{"type":"float64","bits":"18446744073709551616"},
            "expected":{"status":"invalid","code":"execution.float_bits"}},
        {"id":"decimal","format":"json","input":{"type":"decimal","coefficient":"10","exponent":-33},
            "expected":{"status":"ok","value":{"type":"decimal","coefficient":"10","exponent":-33}}}
    ]);
    let root = source(cases.clone());
    let mut adapter = Fake {
        replies: vec![
            Ok(caps()),
            Ok(cases[0]["expected"].clone()),
            Ok(cases[1]["expected"].clone()),
        ],
        requests: vec![],
    };
    let report = execute(&load(root.path()).unwrap(), &mut adapter);
    assert!(report.qualified);
    check_report(root.path(), &report).unwrap();
}

#[test]
fn workbench_canonical_projection_rejects_impossible_success_goldens() {
    for value in [
        json!({"type":"int","value":"00"}),
        json!({"type":"int","value":"-0"}),
        json!({"type":"float64","bits":"0001"}),
        json!({"type":"float64","bits":"18446744073709551616"}),
        json!({"type":"decimal","coefficient":"-00","exponent":0}),
        json!({"type":"decimal","coefficient":"1","exponent":-33}),
        json!({"type":"decimal","coefficient":"1","exponent":-33.0}),
        json!({"type":"decimal","coefficient":"10","exponent":10000}),
    ] {
        assert!(projection(&value).is_err(), "{value}");
        let mut cases = one();
        cases[0]["expected"]["value"] = value;
        assert!(load(source(cases).path()).is_err());
    }
    for value in [
        json!({"type":"int","value":"-1"}),
        json!({"type":"float64","bits":"18446744073709551615"}),
        json!({"type":"decimal","coefficient":"10","exponent":-33}),
        json!({"type":"decimal","coefficient":"0","exponent":-10000}),
    ] {
        assert!(projection(&value).is_ok(), "{value}");
    }
}

#[test]
fn workbench_aggregate_projection_budget_and_utf16_identities_are_enforced() {
    let oversized = json!({"type":"tuple","items":[
        {"type":"text","units":vec![65;50_000]},
        {"type":"text","units":vec![65;50_000]}]});
    assert!(projection(&oversized).is_err());
    let name = "\u{1f642}".repeat(600);
    let value = json!({"type":"custom","owner":name,"tag":"x","items":[]});
    assert!(projection(&value).is_err());
}

#[test]
fn workbench_reader_bounds_consumption_even_when_stream_outgrows_metadata() {
    let bytes = corpus::read_bounded(std::io::Cursor::new(vec![b' '; 64]), 8);
    assert!(bytes.is_err());
    assert_eq!(
        corpus::read_bounded(std::io::Cursor::new(b"abc"), 8).unwrap(),
        b"abc"
    );
}

#[test]
fn workbench_published_corpus_has_json_ion_and_success_rejection_cases() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/workbench/mck");
    let corpus = load(&root).unwrap();
    assert!(corpus.case_count() > 0);
    for format in [Format::Json, Format::IonText] {
        assert!(
            corpus
                .cases
                .iter()
                .any(|c| c.format == format && matches!(c.expected, Observation::Ok { .. }))
        );
        assert!(
            corpus
                .cases
                .iter()
                .any(|c| c.format == format && matches!(c.expected, Observation::Invalid { .. }))
        );
    }
}

#[test]
fn workbench_changed_golden_bytes_invalidate_prior_evidence() {
    let root = source(one());
    let corpus = load(root.path()).unwrap();
    let report = execute(&corpus, &mut fake(one()[0]["expected"].clone()));
    let mut cases = one();
    cases[0]["expected"]["value"]["value"] = json!("2");
    std::fs::write(
        root.path().join("cases.json"),
        serde_json::to_vec(&json!({"formatVersion":VERSION,"cases":cases})).unwrap(),
    )
    .unwrap();
    assert!(check_report(root.path(), &report).is_err());
    // The corpus admitted before the change keeps its original fixed expectation.
    assert!(execute(&corpus, &mut fake(one()[0]["expected"].clone())).qualified);
}

#[test]
fn workbench_output_encoded_size_and_total_retained_observations_are_bounded() {
    let big_int = json!({"type":"int","value":"1".repeat(10_000)});
    let too_large = json!({"type":"tuple","items":vec![big_int.clone();110]});
    assert!(projection(&too_large).is_err());

    struct Repeating {
        observation: Value,
        requests: usize,
    }
    impl Testee for Repeating {
        fn exchange(&mut self, _: &Value) -> Result<Value, String> {
            self.requests += 1;
            Ok(if self.requests == 1 {
                caps()
            } else {
                self.observation.clone()
            })
        }
    }
    let cases = Value::Array(
        (0..32)
            .map(|i| {
                let mut case = one()[0].clone();
                case["id"] = json!(format!("case-{i}"));
                case
            })
            .collect(),
    );
    let root = source(cases);
    let mut adapter = Repeating {
        observation: json!({"status":"ok","value":{"type":"tuple","items":vec![big_int;70]}}),
        requests: 0,
    };
    let report = execute(&load(root.path()).unwrap(), &mut adapter);
    assert!(!report.qualified);
    assert!(report.errors.iter().any(|e| e.phase == Phase::Exchange));
    assert!(adapter.requests < 33);
    assert!(report.to_json().len() <= MAX_REPORT_BYTES);
    check_report(root.path(), &report).unwrap();
}

fn admission_source() -> tempfile::TempDir {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"), serde_json::to_vec(&json!({
        "formatVersion":"0.1.0-draft.2", "cases":[{
            "id":"declared-int", "operation":"validate-value", "format":"json",
            "input":{"value":{"type":"int","value":"0007"},"type":{"type":"int"},"definitions":[]},
            "expected":{"status":"ok","value":{"type":"int","value":"7"}}
        }]
    })).unwrap()).unwrap();
    root
}
fn admission_caps() -> Value {
    json!({"suite":"workbench","contractVersion":"0.1.0-draft.2","binding":"fixture","language":"test",
        "operations":["decode-value","validate-value"],"formats":["json","ion-text"]})
}
#[test]
fn workbench_admission_negotiates_exact_draft_and_dispatches_without_goldens() {
    let root = admission_source();
    let corpus = load(root.path()).unwrap();
    let mut adapter = Fake {
        replies: vec![
            Ok(admission_caps()),
            Ok(json!({"status":"ok","value":{"type":"int","value":"7"}})),
        ],
        requests: vec![],
    };
    let report = execute(&corpus, &mut adapter);
    assert!(report.qualified);
    assert_eq!(adapter.requests[0]["contractVersion"], "0.1.0-draft.2");
    assert_eq!(adapter.requests[1]["op"], "validate-value");
    assert!(adapter.requests.iter().all(|r| r.get("expected").is_none()
        && r.get("id").is_none()
        && r.get("caseId").is_none()));
    assert_eq!(
        serde_json::to_value(&report).unwrap()["records"][0]["operation"],
        "validate-value"
    );
    check_report(root.path(), &report).unwrap();
    let mut forged = serde_json::to_value(&report).unwrap();
    forged["records"][0]["operation"] = json!("decode-value");
    assert!(
        check_report(
            root.path(),
            &Report::from_json(&forged.to_string()).unwrap()
        )
        .is_err()
    );
}
#[test]
fn workbench_admission_requires_operation_inventory_and_exact_caps() {
    let root = admission_source();
    let corpus = load(root.path()).unwrap();
    let mut adapter = Fake {
        replies: vec![Ok(caps())],
        requests: vec![],
    };
    let report = execute(&corpus, &mut adapter);
    assert!(!report.qualified);
    assert_eq!(report.errors[0].phase, Phase::Capabilities);
    check_report(root.path(), &report).unwrap();
    let mut doc: Value =
        serde_json::from_slice(&std::fs::read(root.path().join("cases.json")).unwrap()).unwrap();
    doc["cases"][0].as_object_mut().unwrap().remove("operation");
    std::fs::write(root.path().join("cases.json"), doc.to_string()).unwrap();
    assert!(load(root.path()).is_err());
}
#[test]
fn workbench_admission_success_cannot_be_an_output_error() {
    let root = admission_source();
    let mut doc: Value =
        serde_json::from_slice(&std::fs::read(root.path().join("cases.json")).unwrap()).unwrap();
    doc["cases"][0]["expected"] =
        json!({"status":"ok","value":{"type":"model-error","code":"sdk.division_by_zero"}});
    std::fs::write(root.path().join("cases.json"), doc.to_string()).unwrap();
    assert!(load(root.path()).is_err());
}

#[test]
fn workbench_admission_published_corpus_has_independent_operation_format_inventory() {
    let root =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/workbench/mck/draft.2");
    let corpus = load(&root).unwrap();
    assert_eq!(corpus.case_count(), 162);
    assert_eq!(
        corpus
            .cases
            .iter()
            .filter(|c| c.operation() == Operation::DecodeValue)
            .count(),
        64
    );
    for format in [Format::Json, Format::IonText] {
        for successful in [true, false] {
            assert!(
                corpus
                    .cases
                    .iter()
                    .any(|c| c.operation() == Operation::ValidateValue
                        && c.format == format
                        && matches!(c.expected, Observation::Ok { .. }) == successful)
            );
        }
    }
    // A fake adapter sends the fixed observations solely to exercise report evidence admission;
    // it is not an implementation qualification or a source for corpus goldens.
    let mut adapter = Fake {
        replies: std::iter::once(Ok(admission_caps()))
            .chain(
                corpus
                    .cases
                    .iter()
                    .map(|c| Ok(serde_json::to_value(&c.expected).unwrap())),
            )
            .collect(),
        requests: vec![],
    };
    let report = execute(&corpus, &mut adapter);
    assert!(report.qualified);
    check_report(&root, &report).unwrap();
    let mut changed = report.clone();
    changed.records[64].operation = Some(Operation::DecodeValue);
    assert!(check_report(&root, &changed).is_err());
    let mut changed = serde_json::to_value(&report).unwrap();
    changed["records"][64]
        .as_object_mut()
        .unwrap()
        .remove("operation");
    assert!(check_report(&root, &Report::from_json(&changed.to_string()).unwrap()).is_err());
}
#[test]
fn workbench_admission_unsupported_operation_never_reaches_adapter() {
    let root = admission_source();
    let mut caps = admission_caps();
    caps["operations"] = json!(["decode-value"]);
    let mut adapter = Fake {
        replies: vec![Ok(caps)],
        requests: vec![],
    };
    let report = execute(&load(root.path()).unwrap(), &mut adapter);
    assert_eq!(report.records[0].result, ResultKind::Unsupported);
    assert_eq!(adapter.requests.len(), 1);
    check_report(root.path(), &report).unwrap();
}
#[test]
fn workbench_admission_corpus_envelope_and_legacy_inventory_are_closed() {
    for mutate in [0, 1, 2, 3] {
        let root = admission_source();
        let mut doc: Value =
            serde_json::from_slice(&std::fs::read(root.path().join("cases.json")).unwrap())
                .unwrap();
        match mutate {
            0 => {
                doc["cases"][0]["input"]["output"] = json!(true);
            }
            1 => {
                doc["cases"][0]["format"] = json!("ion-text");
            }
            2 => {
                doc["cases"][0]["input"]["value"] = json!("x".repeat(1024 * 1024));
            }
            _ => {
                doc["cases"][0]["operation"] = json!("unknown");
            }
        }
        std::fs::write(root.path().join("cases.json"), doc.to_string()).unwrap();
        assert!(load(root.path()).is_err());
    }
    let mut cases = one();
    cases[0]["operation"] = json!("decode-value");
    assert!(load(source(cases).path()).is_err());
}
#[test]
fn workbench_admission_capability_and_success_forgery_is_rejected() {
    let root = admission_source();
    let corpus = load(root.path()).unwrap();
    let mut adapter = Fake {
        replies: vec![
            Ok(admission_caps()),
            Ok(json!({"status":"ok","value":{"type":"model-error","code":"sdk.division_by_zero"}})),
        ],
        requests: vec![],
    };
    let report = execute(&corpus, &mut adapter);
    assert!(!report.qualified);
    assert_eq!(report.errors[0].phase, Phase::Exchange);
    check_report(root.path(), &report).unwrap();
    let mut adapter = Fake {
        replies: vec![
            Ok(admission_caps()),
            Ok(json!({"status":"ok","value":{"type":"int","value":"7"}})),
        ],
        requests: vec![],
    };
    let mut report = execute(&corpus, &mut adapter);
    report.capabilities.as_mut().unwrap().contract_version = VERSION.into();
    assert!(check_report(root.path(), &report).is_err());
}

#[test]
fn workbench_explicit_null_operation_cannot_relax_legacy_or_admission_contracts() {
    for root in [source(one()), admission_source()] {
        let mut doc: Value =
            serde_json::from_slice(&std::fs::read(root.path().join("cases.json")).unwrap())
                .unwrap();
        doc["cases"][0]["operation"] = Value::Null;
        std::fs::write(root.path().join("cases.json"), doc.to_string()).unwrap();
        assert!(load(root.path()).is_err());
    }
    let root = source(one());
    let report = execute(
        &load(root.path()).unwrap(),
        &mut fake(one()[0]["expected"].clone()),
    );
    let mut wire = serde_json::to_value(report).unwrap();
    wire["records"][0]["operation"] = Value::Null;
    assert!(Report::from_json(&wire.to_string()).is_err());
}

#[test]
fn workbench_admission_draft_bounds_compact_ion_inputs_without_changing_legacy() {
    for draft in [VERSION, ADMISSION_VERSION] {
        let root = tempfile::tempdir().unwrap();
        let mut case = json!({"id":"escaped-ion","format":"ion-text","input":"\"".repeat(700_000),"expected":{"status":"invalid","code":"workbench.invalid_ion"}});
        if draft == ADMISSION_VERSION {
            case["operation"] = json!("decode-value");
        }
        std::fs::write(
            root.path().join("cases.json"),
            json!({"formatVersion":draft,"cases":[case]}).to_string(),
        )
        .unwrap();
        assert_eq!(load(root.path()).is_ok(), draft == VERSION);
    }
}

fn invocation_source() -> tempfile::TempDir {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"), json!({
        "formatVersion":"0.1.0-draft.3", "cases":[{
            "id":"invoke-int", "operation":"validate-invocations", "format":"json",
            "input":{"suite":{"profile":"morphir-invocations-v1","calls":[{"id":"c","entry":"demo:main#id","arguments":[{"type":"int","value":"007"}]}]},"manifest":{"entries":[{"name":"demo:main#id","inputs":[{"type":"int"}],"output":{"type":"int"}}],"definitions":[]}},
            "expected":{"status":"ok","value":{"profile":"morphir-invocations-v1","calls":[{"id":"c","entry":"demo:main#id","arguments":[{"type":"int","value":"7"}]}]}}
        }]
    }).to_string()).unwrap();
    root
}
fn invocation_caps() -> Value {
    json!({"suite":"workbench","contractVersion":"0.1.0-draft.3","binding":"fixture","language":"test","operations":["decode-value","validate-value","validate-invocations"],"formats":["json","ion-text"]})
}
#[test]
fn workbench_invocation_dispatch_and_report_context_are_bound() {
    let root = invocation_source();
    let corpus = load(root.path()).unwrap();
    let expected = serde_json::to_value(&corpus.cases[0].expected).unwrap();
    let mut adapter = Fake {
        replies: vec![Ok(invocation_caps()), Ok(expected)],
        requests: vec![],
    };
    let report = execute(&corpus, &mut adapter);
    assert!(report.qualified);
    assert_eq!(adapter.requests[1]["op"], "validate-invocations");
    assert!(
        adapter
            .requests
            .iter()
            .all(|r| r.get("expected").is_none() && r.get("caseId").is_none())
    );
    check_report(root.path(), &report).unwrap();
    let mut forged = serde_json::to_value(report).unwrap();
    forged["records"][0]["operation"] = json!("validate-value");
    assert!(
        check_report(
            root.path(),
            &Report::from_json(&forged.to_string()).unwrap()
        )
        .is_err()
    );
}
#[test]
fn workbench_invocation_projection_rejects_argument_errors_and_duplicate_calls() {
    let root = invocation_source();
    let corpus = load(root.path()).unwrap();
    for mutate in 0..4 {
        let mut observation = serde_json::to_value(&corpus.cases[0].expected).unwrap();
        match mutate {
            0 => {
                observation["value"]["calls"][0]["arguments"][0] =
                    json!({"type":"model-error","code":"sdk.division_by_zero"})
            }
            1 => {
                observation["value"]["calls"][0]["arguments"][0] = json!({"type":"list","items":[{"type":"model-error","code":"sdk.division_by_zero"}]})
            }
            2 => {
                let call = observation["value"]["calls"][0].clone();
                observation["value"]["calls"]
                    .as_array_mut()
                    .unwrap()
                    .push(call);
            }
            _ => observation["value"]["calls"][0]["arguments"][0]["value"] = json!("007"),
        }
        let mut adapter = Fake {
            replies: vec![Ok(invocation_caps()), Ok(observation)],
            requests: vec![],
        };
        let report = execute(&corpus, &mut adapter);
        assert!(!report.qualified);
        assert_eq!(report.errors[0].phase, Phase::Exchange);
        check_report(root.path(), &report).unwrap();
    }
}
#[test]
fn workbench_invocation_operation_is_rejected_by_older_drafts() {
    for version in [VERSION, ADMISSION_VERSION] {
        let mut caps = invocation_caps();
        caps["contractVersion"] = json!(version);
        assert!(Capabilities::parse(caps, version).is_err());
        let root = invocation_source();
        let mut doc: Value =
            serde_json::from_slice(&std::fs::read(root.path().join("cases.json")).unwrap())
                .unwrap();
        doc["formatVersion"] = json!(version);
        std::fs::write(root.path().join("cases.json"), doc.to_string()).unwrap();
        assert!(load(root.path()).is_err());
    }
}

#[test]
fn workbench_invocation_projection_budgets_are_per_call_not_per_argument() {
    let root = invocation_source();
    let mut doc: Value =
        serde_json::from_slice(&std::fs::read(root.path().join("cases.json")).unwrap()).unwrap();
    let text = |n| json!({"type":"text","units":vec![0;n]});
    let call = json!({"id":"first","entry":"demo:main#id","arguments":[text(50_000),text(49_998)]});
    let mut second = call.clone();
    second["id"] = json!("second");
    doc["cases"][0]["expected"]["value"] =
        json!({"profile":"morphir-invocations-v1","calls":[call,second]});
    std::fs::write(root.path().join("cases.json"), doc.to_string()).unwrap();
    let corpus = load(root.path()).unwrap();
    let mut adapter = Fake {
        replies: vec![
            Ok(invocation_caps()),
            Ok(serde_json::to_value(&corpus.cases[0].expected).unwrap()),
        ],
        requests: vec![],
    };
    let report = execute(&corpus, &mut adapter);
    assert!(report.qualified);
    check_report(root.path(), &report).unwrap();
    doc["cases"][0]["expected"]["value"]["calls"][0]["arguments"][1] = text(49_999);
    std::fs::write(root.path().join("cases.json"), doc.to_string()).unwrap();
    assert!(load(root.path()).is_err());
}
#[test]
fn workbench_invocation_records_compare_by_name_but_calls_and_extensions_stay_ordered() {
    let root = invocation_source();
    let mut doc: Value =
        serde_json::from_slice(&std::fs::read(root.path().join("cases.json")).unwrap()).unwrap();
    let record = json!({"type":"record","fields":[{"name":"b","value":{"type":"int","value":"2"}},{"name":"a","value":{"type":"int","value":"1"}}]});
    let first = json!({"id":"first","entry":"demo:main#id","arguments":[record]});
    let mut second = first.clone();
    second["id"] = json!("second");
    doc["cases"][0]["expected"]["value"] = json!({"profile":"morphir-invocations-v1","calls":[first,second],"extensions":{"format":"ion-binary","bytes":[224,1,0,234,15]}});
    std::fs::write(root.path().join("cases.json"), doc.to_string()).unwrap();
    let corpus = load(root.path()).unwrap();
    for mutate in 0..3 {
        let mut observed = serde_json::to_value(&corpus.cases[0].expected).unwrap();
        match mutate {
            0 => {
                for call in observed["value"]["calls"].as_array_mut().unwrap() {
                    call["arguments"][0]["fields"]
                        .as_array_mut()
                        .unwrap()
                        .reverse();
                }
            }
            1 => observed["value"]["calls"].as_array_mut().unwrap().reverse(),
            _ => observed["value"]["extensions"]["bytes"]
                .as_array_mut()
                .unwrap()
                .reverse(),
        }
        let mut adapter = Fake {
            replies: vec![Ok(invocation_caps()), Ok(observed)],
            requests: vec![],
        };
        let report = execute(&corpus, &mut adapter);
        assert_eq!(report.qualified, mutate == 0);
        assert_eq!(
            report.records[0].result,
            if mutate == 0 {
                ResultKind::Pass
            } else {
                ResultKind::Fail
            }
        );
        check_report(root.path(), &report).unwrap();
    }
}
#[test]
fn workbench_invocation_published_corpus_is_fixed_and_complete() {
    let root =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/workbench/mck/draft.3");
    let corpus = load(&root).unwrap();
    assert_eq!(corpus.case_count(), 242);
    let counts = [
        Operation::DecodeValue,
        Operation::ValidateValue,
        Operation::ValidateInvocations,
    ]
    .map(|op| corpus.cases.iter().filter(|c| c.operation() == op).count());
    assert_eq!(counts, [64, 98, 80]);
    for format in [Format::Json, Format::IonText] {
        for successful in [true, false] {
            assert!(
                corpus
                    .cases
                    .iter()
                    .any(|c| c.operation() == Operation::ValidateInvocations
                        && c.format == format
                        && matches!(c.expected, Observation::Ok { .. }) == successful)
            );
        }
    }
    // Replaying fixed observations tests evidence, not an implementation or golden authoring.
    let mut adapter = Fake {
        replies: std::iter::once(Ok(invocation_caps()))
            .chain(
                corpus
                    .cases
                    .iter()
                    .map(|c| Ok(serde_json::to_value(&c.expected).unwrap())),
            )
            .collect(),
        requests: vec![],
    };
    let report = execute(&corpus, &mut adapter);
    assert!(report.qualified);
    check_report(&root, &report).unwrap();
}
