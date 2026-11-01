//! Synthetic observations test adjudication and plan selection, not guest
//! implementation support.
use super::*;

fn kit_path() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/mep/mck/guest-generic-json.json")
}
fn kit() -> Kit {
    load_kit(&kit_path()).unwrap()
}
fn document(kit: &Kit) -> &Document {
    let super::super::Document::Generic(document) = &kit.document else {
        unreachable!()
    };
    document
}
fn kit_value() -> Value {
    serde_json::from_str(include_str!(
        "../../../../spec/mep/mck/guest-generic-json.json"
    ))
    .unwrap()
}

/// A flags guest. `ir` is its frontend and backend IR claim; `model` adds the
/// `0.2.0-draft.1` JSON tuples at 4.0.0.
fn claim(ir: Value, model: bool) -> Value {
    let mut caps = json!({
        "frontend":{"compile":true,"languages":[{"id":"morphir-fixture-flags","fileExtensions":[".flags"]}],"irVersions":ir},
        "backend":{"generate":true,"targets":["morphir-fixture-flags"],"irVersions":ir},
    });
    let mut protocols = json!(["0.1"]);
    if model {
        caps["modelTransport"] = json!({"tuples":[json_tuple(COMPILE,"4.0.0"),json_tuple(GENERATE,"4.0.0")],"limits":{"maxEncodedBytes":67108864,"maxDecodedBytes":50331648,"maxDepth":1024,"maxNodes":16777216},"guarantees":[]});
        protocols = json!(["0.2.0-draft.1", "0.1"]);
    }
    json!({"claimsVersion":"0.1.0-draft.2","protocolVersions":protocols,"extension":{"id":"independent-synthetic-guest","name":"Independent synthetic observations","version":"1.2.3"},"capabilities":caps})
}

fn respond(document: &Document, id: &str, request: &Value, describe: &Value) -> Value {
    let (base, version) = parse(id);
    let flags = &document.languages["morphir-fixture-flags"].documents[0];
    let artifacts = json!({"success":true,"diagnostics":[],"artifacts":[{"path":flags.uri,"content":flags.text,"binary":false}]});
    let result = match base {
        "describe" | "describe-immutable" => describe.clone(),
        "initialize" => {
            let mut caps = describe["capabilities"].clone();
            caps.as_object_mut().unwrap().remove("modelTransport");
            json!({"protocolVersion":"0.1","extension":describe["extension"],"capabilities":caps})
        }
        "model-initialize" => {
            let mut caps = describe["capabilities"].clone();
            caps["modelTransport"] = request["params"]["modelTransport"].clone();
            json!({"protocolVersion":"0.2.0-draft.1","extension":describe["extension"],"capabilities":caps})
        }
        "compile" | "roundtrip" | "roundtrip-independent" => {
            json!({"success":true,"diagnostics":[{"severity":"info","message":"synthetic"}],"ir":document.expected_ir_versions[version.unwrap()]})
        }
        "compile-model" | "roundtrip-model" | "roundtrip-model-independent" => {
            json!({"success":true,"diagnostics":[],"model":model(document, version.unwrap())})
        }
        "generate" | "generate-independent" | "generate-model" | "generate-model-independent" => {
            artifacts
        }
        "malformed-source" => {
            json!({"success":false,"diagnostics":[{"severity":"error","code":"fixture.syntax","message":"synthetic"}]})
        }
        "shutdown" | "model-shutdown" => json!({}),
        _ => {
            let code = match base {
                "unknown-method" => -32601,
                "after-shutdown" => -32014,
                _ => -32602,
            };
            return json!({"jsonrpc":"2.0","id":request["id"],"error":{"code":code,"message":"synthetic refusal"}});
        }
    };
    json!({"jsonrpc":"2.0","id":request["id"],"result":result})
}

fn report(kit: &Kit, describe: &Value) -> Value {
    let document = document(kit);
    let identity =
        Identity::capture(&std::env::current_exe().unwrap(), &[], &[kit_path()]).unwrap();
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
    let mut index = 0;
    while let Some(id) = kit.plan(&report.records).get(index).cloned() {
        index += 1;
        let request = request(document, &id, &report.records).unwrap();
        let observed = if is_exit(&id) {
            json!({"exitSuccess":true,"stdoutClosed":true})
        } else if id.ends_with("silent") {
            json!({"silent":true})
        } else {
            respond(document, &id, &request, describe)
        };
        report.records.push(Record {
            case_id: id,
            request,
            observed,
        });
    }
    serde_json::to_value(report).unwrap()
}
fn case_index(report: &Value, case: &str) -> usize {
    report["records"]
        .as_array()
        .unwrap()
        .iter()
        .position(|r| r["caseId"] == case)
        .unwrap_or_else(|| panic!("missing {case}"))
}

#[test]
fn plan_follows_the_claim_and_starts_with_describe() {
    let kit = kit();
    assert_eq!(kit.plan(&[]), ["describe"]);
    let legacy = report(&kit, &claim(json!(["3"]), false));
    let cases = legacy["records"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["caseId"].as_str().unwrap())
        .collect::<Vec<_>>();
    assert!(cases.contains(&"roundtrip-vthree"));
    assert!(
        !cases
            .iter()
            .any(|c| c.ends_with("-vfour") || c.starts_with("model-"))
    );
    let model = report(&kit, &claim(json!(["3", "4.0.0"]), true));
    for case in [
        "roundtrip-vthree",
        "roundtrip-independent-vthree",
        "roundtrip-vfour",
        "roundtrip-model-vfour",
        "roundtrip-model-independent-vfour",
        "compile-model-vfour",
        "generate-model-independent-vfour",
        "bad-digest",
        "model-exit",
    ] {
        case_index(&model, case);
    }
    assert!(
        !model["records"]
            .as_array()
            .unwrap()
            .iter()
            .any(|r| r["caseId"] == "compile-model-vthree")
    );
}

#[test]
fn selection_requires_a_language_and_a_shared_ir_version() {
    let kit = kit();
    let document = document(&kit);
    let mut split = claim(json!(["3", "4"]), false);
    split["capabilities"]["backend"]["irVersions"] = json!(["4"]);
    assert_eq!(select(document, &split).unwrap().versions, ["4.0.0"]);
    let mut none = claim(json!(["3"]), false);
    none["capabilities"]["backend"]["irVersions"] = json!(["4"]);
    assert!(select(document, &none).is_err());
    let mut foreign = claim(json!(["3"]), false);
    foreign["capabilities"]["frontend"]["languages"][0]["id"] = json!("cobol");
    assert!(select(document, &foreign).is_err());
    let mut target = claim(json!(["3"]), false);
    target["capabilities"]["backend"]["targets"] = json!(["python"]);
    assert!(
        select(document, &target).is_err(),
        "a frontend alone does not select"
    );
}

#[test]
fn complete_observations_are_replayed_and_tampering_fails() {
    let kit = kit();
    let original = report(&kit, &claim(json!(["3", "4"]), true));
    check_report(&kit, &original).unwrap();
    for (case, pointer, value) in [
        (
            "compile-vthree",
            "/observed/result/ir/formatVersion",
            json!(4),
        ),
        (
            "roundtrip-vfour",
            "/observed/result/ir/distribution/Library/def/modules/main/Public/values/ready/Public/ExpressionBody/outputType",
            json!({"Unit":{}}),
        ),
        (
            "compile-vfour",
            "/observed/result/diagnostics/0/severity",
            json!("error"),
        ),
        (
            "generate-vthree",
            "/observed/result/artifacts/0/path",
            json!("../main.flags"),
        ),
        (
            "generate-vfour",
            "/observed/result/artifacts/0/path",
            json!("main.txt"),
        ),
        (
            "compile-model-vfour",
            "/observed/result/model/payload/sha256",
            json!("0".repeat(64)),
        ),
        (
            "roundtrip-independent-vthree",
            "/observed/result/ir/formatVersion",
            json!(4),
        ),
        (
            "roundtrip-model-vfour",
            "/observed/result/success",
            json!(false),
        ),
        (
            "roundtrip-model-independent-vfour",
            "/observed/result/model/irVersion",
            json!("3.0.0"),
        ),
        (
            "model-initialize",
            "/observed/result/capabilities/modelTransport/limits/maxEncodedBytes",
            json!(1000001),
        ),
        (
            "initialize",
            "/observed/result/extension/version",
            json!("9.9.9"),
        ),
        ("malformed-source", "/observed/result/success", json!(true)),
        ("unknown-method", "/observed/error/code", json!(-32602)),
        ("after-shutdown", "/observed/error/code", json!(-32601)),
        ("bad-digest", "/observed/error/code", json!(-32601)),
        ("initialized-silent", "/observed/silent", json!(false)),
        ("exit", "/observed/stdoutClosed", json!(false)),
    ] {
        let mut changed = original.clone();
        let index = case_index(&original, case);
        *changed["records"][index].pointer_mut(pointer).unwrap() = value;
        assert!(
            check_report(&kit, &changed).is_err(),
            "accepted {case} {pointer}"
        );
    }
    // A report cannot drop a case that its own recorded claim selects.
    let mut shorter = original.clone();
    let index = case_index(&original, "roundtrip-vthree");
    shorter["records"].as_array_mut().unwrap().remove(index);
    assert!(check_report(&kit, &shorter).is_err());
    // A narrower claim in a stored report needs the full plan of that claim.
    let mut narrowed = original.clone();
    narrowed["records"][0]["observed"]["result"]["capabilities"]["frontend"]["irVersions"] =
        json!(["3"]);
    assert!(check_report(&kit, &narrowed).is_err());
}

#[test]
fn ir_equivalence_has_only_the_stated_rules() {
    let kit = kit();
    let document = document(&kit);
    let v3 = &document.expected_ir_versions["3.0.0"];
    let mut reordered = v3.clone();
    let values = reordered
        .pointer_mut("/distribution/3/modules/0/1/value/values")
        .unwrap()
        .as_array_mut()
        .unwrap();
    values.reverse();
    assert_ne!(&reordered, v3);
    assert!(same_ir(&reordered, v3));
    let v4 = &document.expected_ir_versions["4.0.0"];
    let pointer = "/distribution/Library/def/modules/main/Public/values/ready/Public/ExpressionBody/outputType";
    let mut long = v4.clone();
    *long.pointer_mut(pointer).unwrap() = json!({"Reference":{"fqname":"morphir/SDK:basics#bool"}});
    assert!(same_ir(&long, v4));
    *long.pointer_mut(pointer).unwrap() =
        json!({"Reference":{"fqname":"morphir/SDK:basics#bool","args":[]}});
    assert!(same_ir(&long, v4));
    for wrong in [
        json!({"Unit":{}}),
        json!("morphir/SDK:basics#int"),
        json!({"Reference":{"fqname":"morphir/SDK:basics#bool","args":["a"]}}),
    ] {
        let mut changed = v4.clone();
        *changed.pointer_mut(pointer).unwrap() = wrong;
        assert!(!same_ir(&changed, v4));
    }
    // The short form applies only at the IR 4 type positions of a value.
    let mut package = v4.clone();
    *package
        .pointer_mut("/distribution/Library/packageName")
        .unwrap() = json!({"Reference":{"fqname":"mck/generic"}});
    assert!(!same_ir(&package, v4), "package name must be a string");
    let mut body = v4.clone();
    *body
        .pointer_mut(
            "/distribution/Library/def/modules/main/Public/values/ready/Public/ExpressionBody/body",
        )
        .unwrap() = json!({"Reference":{"fqname":"mck/generic:main#ready"}});
    let mut short_body = v4.clone();
    *short_body
        .pointer_mut(
            "/distribution/Library/def/modules/main/Public/values/ready/Public/ExpressionBody/body",
        )
        .unwrap() = json!("mck/generic:main#ready");
    assert!(
        !same_ir(&body, &short_body),
        "a value body is not a type position"
    );
    let mut input_short = v4.clone();
    let inputs = "/distribution/Library/def/modules/main/Public/values/ready/Public/ExpressionBody/inputTypes";
    *input_short.pointer_mut(inputs).unwrap() = json!({"flag":"morphir/SDK:basics#bool"});
    let mut input_long = v4.clone();
    *input_long.pointer_mut(inputs).unwrap() =
        json!({"flag":{"Reference":{"fqname":"morphir/SDK:basics#bool"}}});
    assert!(
        same_ir(&input_long, &input_short),
        "input types are type positions"
    );
    let mut documented = v3.clone();
    *documented
        .pointer_mut("/distribution/3/modules/0/1/value/values/0/1/value/doc")
        .unwrap() = json!("changed");
    assert!(!same_ir(&documented, v3), "documentation still compares");
}

#[test]
fn document_uris_are_relative_to_the_source_folder() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("kit.json");
    for uri in [
        "src/main.py",
        "/work/main.py",
        "file:///main.py",
        "../main.py",
        "a//main.py",
        "./main.py",
        "C:/main.py",
        "a\\main.py",
    ] {
        for set in ["documents", "malformed"] {
            let mut value = kit_value();
            value["languages"]["python"][set][0]["uri"] = json!(uri);
            std::fs::write(&path, value.to_string()).unwrap();
            assert!(load_kit(&path).is_err(), "accepted {set} {uri}");
        }
    }
    let mut nested = kit_value();
    nested["languages"]["python"]["documents"][0]["uri"] = json!("acme/rules.py");
    std::fs::write(&path, nested.to_string()).unwrap();
    load_kit(&path).unwrap();
}

#[test]
fn kit_requires_both_ir_versions_and_a_language() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("kit.json");
    let mut missing = kit_value();
    missing["expectedIrVersions"]
        .as_object_mut()
        .unwrap()
        .remove("3.0.0");
    let mut changed = vec![missing];
    for (pointer, value) in [
        ("/expectedIrVersions/4.0.0/formatVersion", json!(3)),
        ("/languages", json!({})),
        ("/languages/python/malformed", json!([])),
        ("/contextDigest", json!("C".repeat(64))),
        ("/contractVersion", json!("0.1.0-draft.2")),
    ] {
        let mut kit = kit_value();
        *kit.pointer_mut(pointer).unwrap() = value;
        changed.push(kit);
    }
    for value in changed {
        std::fs::write(&path, value.to_string()).unwrap();
        assert!(load_kit(&path).is_err());
    }
}

#[test]
fn claims_use_a_supported_format() {
    let kit = kit();
    let describe = |claim: Value| {
        let mut record = Record {
            case_id: "describe".into(),
            request: request(document(&kit), "describe", &[]).unwrap(),
            observed: Value::Null,
        };
        record.observed = json!({"jsonrpc":"2.0","id":1,"result":claim});
        compare(document(&kit), &record, &[])
    };
    let current = claim(json!(["3"]), false);
    describe(current.clone()).unwrap();
    let mut draft_one = current.clone();
    draft_one.as_object_mut().unwrap().remove("claimsVersion");
    draft_one["statementVersion"] = json!("0.1.0-draft.1");
    draft_one["critical"] = json!(["statementVersion"]);
    describe(draft_one.clone()).unwrap();
    let mut both = current.clone();
    both["statementVersion"] = json!("0.1.0-draft.1");
    let mut future = current.clone();
    future["claimsVersion"] = json!("0.1.0-draft.3");
    let mut garbage = current.clone();
    garbage["claimsVersion"] = json!("garbage");
    let mut renamed = draft_one.clone();
    renamed["critical"] = json!(["claimsVersion"]);
    let mut unknown = current.clone();
    unknown["critical"] = json!(["capabilities.future"]);
    for claim in [both, future, garbage, renamed, unknown] {
        assert!(describe(claim.clone()).is_err(), "accepted {claim}");
    }
}
