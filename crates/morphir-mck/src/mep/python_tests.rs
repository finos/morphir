//! Synthetic observations test adjudication, not guest implementation support.
use super::*;

fn kit() -> Kit {
    load_kit(
        &Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/mep/mck/guest-python-json.json"),
    )
    .unwrap()
}
fn document(kit: &Kit) -> &Document {
    let super::super::Document::Python(document) = &kit.document else {
        unreachable!()
    };
    document
}
fn capabilities() -> Value {
    let mut transport = support();
    transport["limits"] = json!({"maxEncodedBytes":12582912,"maxDecodedBytes":8388608,"maxDepth":128,"maxNodes":100000});
    json!({"frontend":{"compile":true,"languages":[{"id":"python","fileExtensions":[".py"]}],"irVersions":["3","4"]},"backend":{"generate":true,"targets":["python"],"irVersions":["3","4"]},"modelTransport":transport})
}
fn artifacts(document: &Document) -> Value {
    json!({"success":true,"diagnostics":[],"artifacts":document.expected_artifacts.iter().map(|(p,c)| json!({"path":p,"content":c})).collect::<Vec<_>>()})
}
fn report(kit: &Kit) -> Value {
    let document = document(kit);
    let exe = std::env::current_exe().unwrap();
    let identity = Identity::capture(
        &exe,
        &[],
        &[Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/mep/mck/guest-python-json.json")],
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
    let extension = json!({"id":"morphir-python","name":"Independent synthetic Python observations","version":"0.5.0"});
    for id in CASES {
        let request = request(document, id, &report.records).unwrap();
        let observed = if is_exit(id) {
            json!({"exitSuccess":true,"stdoutClosed":true})
        } else if id.ends_with("silent") {
            json!({"silent":true})
        } else {
            let mut response = json!({"jsonrpc":"2.0","id":request["id"]});
            let result = if *id == "describe" || *id == "describe-immutable" {
                Some(
                    json!({"claimsVersion":"0.1.0-draft.2","protocolVersions":["0.1","0.2.0-draft.1"],"extension":extension,"capabilities":capabilities()}),
                )
            } else if (*id == "initialize" || id.ends_with("-initialize"))
                && *id != "bad-protocol-initialize"
                && *id != "before-initialize"
                && *id != "duplicate-initialize"
            {
                let mut caps = capabilities();
                if *id == "legacy-initialize" {
                    caps.as_object_mut().unwrap().remove("modelTransport");
                } else {
                    let mut selected = offer(id);
                    for (key, value) in selected["limits"].as_object_mut().unwrap() {
                        *value = json!(
                            value
                                .as_u64()
                                .unwrap()
                                .min(caps["modelTransport"]["limits"][key].as_u64().unwrap())
                        );
                    }
                    caps["modelTransport"] = selected;
                }
                Some(
                    json!({"protocolVersion":if *id=="legacy-initialize" {"0.1"}else{"0.2.0-draft.1"},"extension":extension,"capabilities":caps}),
                )
            } else if id.starts_with("generate-")
                || id.starts_with("legacy-generate-")
                || *id == "wide-generate"
            {
                Some(artifacts(document))
            } else if id.starts_with("compile-")
                || id.starts_with("roundtrip-")
                || id.starts_with("legacy-compile-")
                || *id == "narrow-compile"
                || *id == "recover-after-refusals"
            {
                let v = version(id);
                let mut result = json!({"success":true,"modules":["main"],"diagnostics":[]});
                if request["method"] == COMPILE {
                    result["model"] = model(document, v);
                } else {
                    result["ir"] = document.expected_ir_versions[v].clone();
                    result["irVersion"] = json!(v);
                }
                Some(result)
            } else if [
                "malformed-source",
                "types-only-functions",
                "unsupported-distribution",
                "unsupported-application",
            ]
            .contains(id)
            {
                Some(
                    json!({"success":false,"diagnostics":[{"severity":"error","code":"PY004","message":"Independent refusal"}]}),
                )
            } else if (*id != "after-shutdown" && id.ends_with("shutdown"))
                || [
                    "id-u64-max",
                    "id-string",
                    "id-empty-string",
                    "bounded-recovery-ping",
                ]
                .contains(id)
            {
                Some(Value::Null)
            } else {
                None
            };
            if let Some(result) = result {
                response["result"] = result;
            } else {
                response["error"] = json!({"code":match *id {"before-initialize"|"after-shutdown"=>-32014,"bad-protocol-initialize"=>-32011,"duplicate-initialize"=>-32600,"legacy-model-refused"|"narrow-generate-refused"=>-32013,"unknown-method"=>-32601,_=>-32602},"message":"Independent refusal"});
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
fn complete_python_observations_are_replayed_and_tampering_fails() {
    let kit = kit();
    let original = report(&kit);
    check_report(&kit, &original).unwrap();
    for (case, pointer, value) in [
        ("id-u64-max", "/observed/id", json!("18446744073709551615")),
        ("id-string", "/observed/id", json!(1)),
        ("id-empty-string", "/observed/id", json!(null)),
        (
            "initialize",
            "/observed/result/capabilities/modelTransport/limits/maxEncodedBytes",
            json!(1000001),
        ),
        (
            "wide-initialize",
            "/observed/result/capabilities/modelTransport/limits/maxDecodedBytes",
            json!(12582912),
        ),
        (
            "compile-model-vfour",
            "/observed/result/model/payload/sha256",
            json!("0".repeat(64)),
        ),
        (
            "compile-json-vthree",
            "/observed/result/ir/formatVersion",
            json!(4),
        ),
        (
            "compile-json-vfour",
            "/observed/result/ir/distribution/Library/def/modules/main/Public/values/identity/Public/ExpressionBody/body",
            json!({"Literal":{"BoolLiteral":true}}),
        ),
        (
            "generate-model-vfour",
            "/observed/result/artifacts/0/content",
            json!("def identity(flag): return True"),
        ),
        (
            "generate-json-vthree",
            "/observed/result/artifacts/0/path",
            json!("other.py"),
        ),
        ("unsupported-ion", "/observed/error/code", json!(-32601)),
        ("bad-length", "/observed/error/message", json!(null)),
        ("initialized-silent", "/observed/silent", json!(false)),
        ("exit", "/observed/stdoutClosed", json!(false)),
    ] {
        let mut changed = original.clone();
        let index = CASES.iter().position(|id| *id == case).unwrap();
        *changed["records"][index].pointer_mut(pointer).unwrap() = value;
        assert!(
            check_report(&kit, &changed).is_err(),
            "accepted {case} {pointer}"
        );
    }
    for key in ["profile", "corpusSha256", "suite"] {
        let mut changed = original.clone();
        changed[key] = json!("wrong");
        assert!(check_report(&kit, &changed).is_err(), "accepted {key}");
    }
    let mut changed = original.clone();
    changed["records"].as_array_mut().unwrap().pop();
    assert!(check_report(&kit, &changed).is_err());
    let mut changed = original;
    changed["records"].as_array_mut().unwrap().swap(10, 11);
    assert!(check_report(&kit, &changed).is_err());
}

#[test]
fn valid_hash_cannot_hide_constant_identity_body() {
    let kit = kit();
    let document = document(&kit);
    let mut wrong = document.expected_ir_versions["4.0.0"].clone();
    wrong["distribution"]["Library"]["def"]["modules"]["main"]["Public"]["values"]["identity"]["Public"]
        ["ExpressionBody"]["body"] = json!({"Literal":{"BoolLiteral":true}});
    let mut envelope = model(document, "4.0.0");
    envelope["payload"] = payload(&serde_json::to_vec(&wrong).unwrap(), "morphir-json");
    assert!(
        validate_compiled(document, &envelope, "4.0.0")
            .unwrap_err()
            .contains("semantic IR")
    );
}

#[test]
fn python_profile_rejects_incomplete_version_and_artifact_expectations() {
    let original: Value = serde_json::from_str(include_str!(
        "../../../../spec/mep/mck/guest-python-json.json"
    ))
    .unwrap();
    for (field, key) in [
        ("expectedIrVersions", "3.0.0"),
        ("expectedIrVersions", "4.0.0"),
        ("expectedArtifacts", "main.py"),
    ] {
        let mut incomplete = original.clone();
        incomplete[field].as_object_mut().unwrap().remove(key);
        assert!(load(incomplete).is_err());
    }
}

#[test]
fn frozen_ir_and_distribution_refusals_are_valid_contract_documents() {
    let kit = kit();
    let document = document(&kit);
    for (version, schema) in [
        (
            "3.0.0",
            include_str!("../../../../website/static/schemas/morphir-ir-v3.json"),
        ),
        (
            "4.0.0",
            include_str!("../../../../website/static/schemas/morphir-ir-v4.json"),
        ),
    ] {
        let schema: Value = serde_json::from_str(schema).unwrap();
        let validator = jsonschema::options().build(&schema).unwrap();
        validator
            .validate(&document.expected_ir_versions[version])
            .unwrap();
        if version == "4.0.0" {
            for case in ["unsupported-distribution", "unsupported-application"] {
                let request = request(document, case, &[]).unwrap();
                validator.validate(&request["params"]["ir"]).unwrap();
            }
        }
    }
}

#[test]
fn malformed_base64_vector_preserves_other_payload_boundaries() {
    let kit = kit();
    let document = document(&kit);
    let valid = model(document, "4.0.0");
    let request = request(document, "bad-base64", &[]).unwrap();
    let actual = &request["params"]["model"]["payload"];
    assert_eq!(
        actual["content"].as_str().unwrap().len(),
        valid["payload"]["content"].as_str().unwrap().len()
    );
    for field in ["codec", "layout", "decodedByteLength", "sha256"] {
        assert_eq!(actual[field], valid["payload"][field], "changed {field}");
    }
    assert!(
        STANDARD
            .decode(actual["content"].as_str().unwrap())
            .is_err()
    );
}

#[test]
fn semantic_ir_version_vector_keeps_tuple_and_envelope_admitted() {
    let kit = kit();
    let request = request(document(&kit), "bad-ir-version", &[]).unwrap();
    let params = &request["params"];
    assert_eq!(params["input"], tuple(GENERATE, "3.0.0"));
    assert_eq!(params["model"]["irVersion"], "3.0.0");
    let bytes = decode_payload(&params["model"]["payload"]).unwrap();
    let ir = crate::json::strict::parse_exact(std::str::from_utf8(&bytes).unwrap()).unwrap();
    assert_eq!(ir["formatVersion"], 4);
}
