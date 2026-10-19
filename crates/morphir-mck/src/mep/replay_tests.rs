use super::*;

fn kit() -> Kit {
    load_kit(
        &Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/mep/mck/guest-moonbit-bool.json"),
    )
    .unwrap()
}

fn model(kit: &Kit) -> Value {
    let root = metadata::synthetic_model(&kit.document.expected_ir);
    let bytes = root.encode_as(ion_rs::v1_0::Binary).unwrap();
    json!({"envelopeVersion":"0.1.0-draft.1","modelId":"urn:morphir:mck:synthetic","revision":"independent-revision","irVersion":"4.0.0","profile":"morphir-model","payload":payload(&bytes,"ion-binary")})
}

fn generated_result(kit: &Kit, request: &Value) -> Value {
    let model = request["params"].get("model");
    let rich = model.is_some_and(|m| m["profile"] == "morphir-model");
    let source = if rich {
        Some(Element::read_one(decode_payload(&model.unwrap()["payload"]).unwrap()).unwrap())
    } else {
        None
    };
    let expected = if rich {
        &kit.document.expected_artifacts
    } else {
        &kit.document.expected_json_artifacts
    };
    let mut artifacts = expected
        .iter()
        .map(|(name, text)| json!({"path":name,"content":text,"binary":false}))
        .collect::<Vec<_>>();
    if let Some(model) = model {
        artifacts.push(json!({"path":if rich{"mep/source-model.ionb"}else{"mep/source-model.json"},"binary":true,"content":model["payload"]["content"]}));
        artifacts.push(
            json!({"path":"mep/source-envelope.json","binary":false,"content":model.to_string()}),
        );
    }
    let symbols = if let Some(root) = source {
        metadata::synthetic_symbols(&root, &kit.document.expected_ir)
    } else {
        metadata::synthetic_plain_symbols(&kit.document.plain_ir)
    };
    artifacts.push(json!({"path":"symbols.10n","binary":true,"content":STANDARD.encode(symbols.encode_as(ion_rs::v1_0::Binary).unwrap())}));
    json!({"success":true,"artifacts":artifacts,"diagnostics":[]})
}

fn report(kit: &Kit) -> Value {
    let exe = std::env::current_exe().unwrap();
    let identity =
        Identity::capture(
            &exe,
            &[],
            &[Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../../spec/mep/mck/guest-moonbit-bool.json")],
        )
        .unwrap();
    let mut report = Report {
        contract_version: CONTRACT.into(),
        suite: "mep-guest".into(),
        profile: PROFILE.into(),
        corpus_sha256: kit.digest.clone(),
        identity,
        records: vec![],
        error: None,
        qualified: true,
    };
    let mut numeric_id = 0;
    let extension =
        json!({"id":"independent-synthetic","name":"Independent synthetic guest","version":"1"});
    for id in CASES {
        let request = request(kit, id, &report.records).unwrap();
        let observed = if is_exit(id) {
            numeric_id = 0;
            json!({"exitSuccess":true,"stdoutClosed":true})
        } else if id.ends_with("silent") {
            json!({"silent":true})
        } else {
            numeric_id += 1;
            let mut response = json!({"jsonrpc":"2.0","id":numeric_id});
            let result = match *id {
                "describe" | "describe-immutable" => Some(
                    json!({"claimsVersion":"0.1.0-draft.2","protocolVersions":["0.2.0-draft.1","0.1"],"extension":extension,"capabilities":{"modelTransport":support(),"backend":{"targets":["moonbit"],"irVersions":["4"]},"frontend":{"languages":[{"id":"moonbit"}],"irVersions":["4.0.0"]}}}),
                ),
                "initialize" | "narrow-initialize" | "bounded-initialize" => Some(
                    json!({"protocolVersion":"0.2.0-draft.1","extension":extension,"capabilities":{"modelTransport":request["params"]["modelTransport"],"backend":{"targets":["moonbit"],"irVersions":["4"]},"frontend":{"languages":[{"id":"moonbit"}],"irVersions":["4.0.0"]}}}),
                ),
                "legacy-initialize" => Some(
                    json!({"protocolVersion":"0.1","extension":extension,"capabilities":{"backend":{"generate":true,"targets":["moonbit"],"irVersions":["4"]}}}),
                ),
                "compile-ion" | "compile-repeat" | "recover-after-source" | "narrow-compile" => {
                    Some(
                        json!({"success":true,"modules":["main"],"diagnostics":[],"model":model(kit)}),
                    )
                }
                "generate-retained"
                | "generate-repeat"
                | "recover-after-digest"
                | "unknown-ion-retained"
                | "json-model-generate"
                | "legacy-json-generate"
                | "legacy-json" => Some(generated_result(kit, &request)),
                "malformed-source" | "lossy-json-refused" => Some(
                    json!({"success":false,"diagnostics":[{"severity":"error","code":if *id=="lossy-json-refused"{"data.lossy_conversion"}else{"syntax_error"},"message":"independent refusal"}]}),
                ),
                "shutdown"
                | "legacy-shutdown"
                | "narrow-shutdown"
                | "bounded-shutdown"
                | "bounded-recovery-ping" => Some(Value::Null),
                _ => None,
            };
            if let Some(result) = result {
                response["result"] = result;
            } else {
                response["error"] = json!({"code":match *id {"unknown-method"=>-32601,"legacy-model-refused"|"narrow-generate-refused"=>-32013,"after-shutdown"=>-32014,_=>-32602},"message":"independent refusal"});
            }
            response
        };
        report.records.push(Record {
            case_id: (*id).into(),
            request,
            observed,
        });
    }
    serde_json::to_value(report).unwrap()
}

#[test]
fn saved_report_is_recomputed_from_complete_independent_observations() {
    let kit = kit();
    let report = report(&kit);
    check_report(&kit, &report).unwrap();
    let index = |id: &str| CASES.iter().position(|case| *case == id).unwrap();
    let mut mutations = vec![];
    let mut changed = report.clone();
    changed["records"].as_array_mut().unwrap().pop();
    mutations.push(changed);
    let mut changed = report.clone();
    changed["records"].as_array_mut().unwrap().swap(4, 5);
    mutations.push(changed);
    let mut changed = report.clone();
    changed["corpusSha256"] = json!("0".repeat(64));
    mutations.push(changed);
    let mut changed = report.clone();
    changed["identity"]["runnerBinary"]["sha256"] = json!("0".repeat(64));
    mutations.push(changed);
    for (id, pointer, value) in [
        (
            "initialize",
            "/observed/result/capabilities/frontend/irVersions",
            json!(["3"]),
        ),
        (
            "legacy-initialize",
            "/observed/result/capabilities/backend/irVersions",
            json!(["3"]),
        ),
        (
            "initialize",
            "/observed/result/capabilities/modelTransport/limits/maxDecodedBytes",
            json!(750001),
        ),
        ("compile-ion", "/observed/id", json!(99)),
        (
            "compile-ion",
            "/observed/result/model/payload/sha256",
            json!("0".repeat(64)),
        ),
        ("compile-ion", "/observed/result/success", json!(false)),
        (
            "generate-retained",
            "/request/params/target",
            json!("other"),
        ),
        (
            "generate-retained",
            "/observed/result/artifacts/0/content",
            json!("changed artifact"),
        ),
        ("unknown-method", "/observed/error/message", json!(null)),
        ("initialized-silent", "/observed/silent", json!(false)),
        ("exit", "/observed/exitSuccess", json!(false)),
    ] {
        let mut changed = report.clone();
        *changed["records"][index(id)].pointer_mut(pointer).unwrap() = value;
        mutations.push(changed);
    }
    for (i, changed) in mutations.iter().enumerate() {
        assert!(changed["qualified"] == true);
        assert!(
            check_report(&kit, changed).is_err(),
            "tampered observation {i} passed"
        );
    }
}

#[test]
fn a_valid_digest_cannot_hide_wrong_compiled_semantics() {
    let kit = kit();
    let mut wrong = kit.document.expected_ir.clone();
    wrong["distribution"]["Library"]["def"]["modules"]["main"]["Public"]["values"]["is-ready"]["Public"]
        ["ExpressionBody"]["body"] = json!({"Literal":{"BoolLiteral":true}});
    let root = metadata::synthetic_model(&wrong);
    let bytes = root.encode_as(ion_rs::v1_0::Binary).unwrap();
    let mut model = model(&kit);
    model["payload"] = payload(&bytes, "ion-binary");
    assert!(
        validate_compiled(&kit, &model)
            .unwrap_err()
            .contains("semantic IR")
    );
}

#[test]
fn description_requires_complete_static_model_support() {
    let kit = kit();
    let record = Record {
        case_id: "describe".into(),
        request: json!({}),
        observed: json!({"jsonrpc":"2.0","id":1,"result":{"extension":{"id":"synthetic"},"capabilities":{}}}),
    };
    assert!(compare(&kit, &record, &[]).is_err());
}

#[test]
fn artifact_changes_during_a_run_prevent_qualification() {
    let kit = kit();
    let mut report: Report = serde_json::from_value(report(&kit)).unwrap();
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().join("guest-artifact");
    std::fs::write(&path, b"original artifact").unwrap();
    report
        .identity
        .files
        .push(FileIdentity::read(&path).unwrap());
    std::fs::write(path, b"changed artifact").unwrap();
    finalize(&kit, &mut report);
    assert!(!report.qualified);
    assert!(report.error.unwrap().contains("identity changed"));
}

#[test]
fn source_refusals_require_structured_error_diagnostics() {
    let kit = kit();
    for diagnostics in [
        json!([null]),
        json!(["bad"]),
        json!([{"code":"data.lossy_conversion"}]),
        json!([{"severity":"warning","message":"only warning"}]),
    ] {
        let record = Record {
            case_id: "malformed-source".into(),
            request: json!({}),
            observed: json!({"jsonrpc":"2.0","id":1,"result":{"success":false,"diagnostics":diagnostics}}),
        };
        assert!(compare(&kit, &record, &[]).is_err());
    }
}
