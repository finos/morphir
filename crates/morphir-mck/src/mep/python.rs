//! Independent JSON Library profile in the shared executable guest suite.
//! Expected IR and artifacts are frozen corpus data, never implementation codecs.
use super::*;

pub(super) const PROFILE: &str = "python-json-library-v1";
pub(super) const CASES: &[&str] = &[
    "describe",
    "before-initialize",
    "bad-protocol-initialize",
    "initialize",
    "initialized-silent",
    "unknown-notification-silent",
    "duplicate-initialize",
    "id-u64-max",
    "id-string",
    "id-empty-string",
    "compile-json-vthree",
    "generate-json-vthree",
    "roundtrip-json-vthree",
    "compile-json-vfour",
    "generate-json-vfour",
    "roundtrip-json-vfour",
    "compile-model-vthree",
    "generate-model-vthree",
    "roundtrip-model-vthree",
    "compile-model-vfour",
    "generate-model-vfour",
    "roundtrip-model-vfour",
    "compile-model-repeat",
    "generate-independent-vthree",
    "generate-independent-vfour",
    "bad-digest",
    "bad-length",
    "bad-base64",
    "bad-json",
    "bad-version",
    "bad-ir-version",
    "tuple-mismatch",
    "tuple-operation",
    "unknown-critical",
    "unsupported-ion",
    "unsupported-ion-evidence",
    "unsupported-guarantee",
    "unsupported-distribution",
    "unsupported-application",
    "invalid-params",
    "malformed-source",
    "types-only-functions",
    "recover-after-refusals",
    "unknown-method",
    "describe-immutable",
    "shutdown",
    "after-shutdown",
    "exit",
    "legacy-initialize",
    "legacy-initialized-silent",
    "legacy-model-refused",
    "legacy-compile-vthree",
    "legacy-generate-vthree",
    "legacy-compile-vfour",
    "legacy-generate-vfour",
    "legacy-shutdown",
    "legacy-exit",
    "narrow-initialize",
    "narrow-initialized-silent",
    "narrow-generate-refused",
    "narrow-version-refused",
    "narrow-compile",
    "narrow-shutdown",
    "narrow-exit",
    "bounded-initialize",
    "bounded-initialized-silent",
    "bounded-model-refused",
    "bounded-request-cannot-widen",
    "bounded-recovery-ping",
    "bounded-shutdown",
    "bounded-exit",
    "decoded-initialize",
    "decoded-initialized-silent",
    "decoded-model-refused",
    "decoded-shutdown",
    "decoded-exit",
    "depth-initialize",
    "depth-initialized-silent",
    "depth-model-refused",
    "depth-shutdown",
    "depth-exit",
    "nodes-initialize",
    "nodes-initialized-silent",
    "nodes-model-refused",
    "nodes-shutdown",
    "nodes-exit",
    "wide-initialize",
    "wide-initialized-silent",
    "wide-generate",
    "wide-shutdown",
    "wide-exit",
];

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct Document {
    contract_version: semver::Version,
    profile: String,
    mep_version: String,
    source: Value,
    expected_ir_versions: BTreeMap<String, Value>,
    expected_artifacts: BTreeMap<String, String>,
}

pub(super) fn load(value: Value) -> Result<Document, String> {
    let document: Document = serde_json::from_value(value).map_err(|e| e.to_string())?;
    require(
        document.contract_version == semver::Version::parse(CONTRACT).unwrap()
            && document.profile == PROFILE
            && document.mep_version == "0.2.0-draft.1"
            && document.source["languageId"] == "python"
            && document.source["options"]["typesOnly"] == false
            && document
                .expected_ir_versions
                .keys()
                .map(String::as_str)
                .collect::<Vec<_>>()
                == ["3.0.0", "4.0.0"]
            && document
                .expected_artifacts
                .keys()
                .map(String::as_str)
                .collect::<Vec<_>>()
                == ["main.py"]
            && document
                .expected_artifacts
                .values()
                .all(|text| !text.is_empty()),
        "unsupported or incomplete Python JSON guest kit",
    )?;
    for (version, ir) in &document.expected_ir_versions {
        let major = if version == "3.0.0" { 3 } else { 4 };
        require(ir["formatVersion"] == major, "fixed IR version mismatch")?;
    }
    Ok(document)
}

fn tuple(operation: &str, version: &str) -> Value {
    json!({"operation":operation,"profile":"morphir-ir","codec":"morphir-json","envelopeVersion":"0.1.0-draft.1","irVersion":version})
}
fn support() -> Value {
    let tuples = [COMPILE, GENERATE]
        .into_iter()
        .flat_map(|op| ["3.0.0", "4.0.0"].map(|v| tuple(op, v)))
        .collect::<Vec<_>>();
    json!({"tuples":tuples,"limits":{"maxEncodedBytes":1000000,"maxDecodedBytes":750000,"maxDepth":128,"maxNodes":100000},"guarantees":[]})
}
fn offer(id: &str) -> Value {
    let mut value = support();
    match id {
        "narrow-initialize" => value["tuples"] = json!([tuple(COMPILE, "3.0.0")]),
        "bounded-initialize" => value["limits"]["maxEncodedBytes"] = json!(128),
        "decoded-initialize" => value["limits"]["maxDecodedBytes"] = json!(96),
        "depth-initialize" => value["limits"]["maxDepth"] = json!(2),
        "nodes-initialize" => value["limits"]["maxNodes"] = json!(2),
        "wide-initialize" => {
            value["limits"] = json!({"maxEncodedBytes":16777216,"maxDecodedBytes":12582912,"maxDepth":256,"maxNodes":200000})
        }
        _ => {}
    }
    value
}
fn version(id: &str) -> &'static str {
    if id.contains("vthree") || id == "narrow-compile" {
        "3.0.0"
    } else {
        "4.0.0"
    }
}
fn observed<'a>(records: &'a [Record], id: &str) -> Result<&'a Value, String> {
    rpc_result(
        records
            .iter()
            .find(|r| r.case_id == id)
            .ok_or_else(|| format!("missing {id}"))?,
    )
}
fn model(document: &Document, version: &str) -> Value {
    let bytes = serde_json::to_vec(&document.expected_ir_versions[version]).unwrap();
    json!({"envelopeVersion":"0.1.0-draft.1","modelId":"urn:morphir:mck:python","revision":"independent-1","irVersion":version,"profile":"morphir-ir","payload":payload(&bytes,"morphir-json")})
}
fn compile(document: &Document, version: &str, model: bool) -> Value {
    let mut value = document.source.clone();
    value["options"]["irVersion"] = json!(version);
    if model {
        value["output"] = tuple(COMPILE, version);
    }
    value
}
fn generate(model: Value, version: &str) -> Value {
    json!({"model":model,"input":tuple(GENERATE,version),"target":"python","contextDigest":"c".repeat(64)})
}

pub(super) fn request(document: &Document, id: &str, records: &[Record]) -> Result<Value, String> {
    let v = version(id);
    let (method, params) = match id {
        "describe" | "describe-immutable" => (
            "morphir.extension.describe",
            json!({"protocolVersions":["0.2.0-draft.1","0.1"]}),
        ),
        "bad-protocol-initialize" => (
            "morphir.initialize",
            json!({"protocolVersions":["0.2.0-draft.2"],"host":{"name":"morphir-mck","version":env!("CARGO_PKG_VERSION")},"modelTransport":support()}),
        ),
        "legacy-initialize" => (
            "morphir.initialize",
            json!({"protocolVersions":["0.1"],"host":{"name":"morphir-mck","version":env!("CARGO_PKG_VERSION")}}),
        ),
        "initialize"
        | "duplicate-initialize"
        | "narrow-initialize"
        | "bounded-initialize"
        | "decoded-initialize"
        | "depth-initialize"
        | "nodes-initialize"
        | "wide-initialize" => (
            "morphir.initialize",
            json!({"protocolVersions":["0.2.0-draft.1"],"host":{"name":"morphir-mck","version":env!("CARGO_PKG_VERSION")},"modelTransport":offer(id)}),
        ),
        id if id.ends_with("initialized-silent") => ("morphir.initialized", json!({})),
        "unknown-notification-silent" | "unknown-method" => ("morphir.mck.unknown", json!({})),
        "id-u64-max"
        | "id-string"
        | "id-empty-string"
        | "after-shutdown"
        | "bounded-recovery-ping" => ("morphir.ping", json!({})),
        "before-initialize"
        | "compile-json-vthree"
        | "compile-json-vfour"
        | "legacy-compile-vthree"
        | "legacy-compile-vfour" => ("morphir.frontend.compile", compile(document, v, false)),
        "roundtrip-json-vthree"
        | "roundtrip-json-vfour"
        | "roundtrip-model-vthree"
        | "roundtrip-model-vfour" => {
            let generated_id = id.replace("roundtrip", "generate");
            let result = observed(records, &generated_id)?;
            let text = result["artifacts"][0]["content"]
                .as_str()
                .ok_or("generated source missing")?;
            let mut p = compile(document, v, id.contains("model"));
            p["sources"]["documents"][0]["text"] = json!(text);
            (
                if id.contains("model") {
                    COMPILE
                } else {
                    "morphir.frontend.compile"
                },
                p,
            )
        }
        "compile-model-vthree"
        | "compile-model-vfour"
        | "compile-model-repeat"
        | "recover-after-refusals"
        | "narrow-compile"
        | "narrow-version-refused" => (COMPILE, compile(document, v, true)),
        "generate-json-vthree"
        | "generate-json-vfour"
        | "legacy-generate-vthree"
        | "legacy-generate-vfour" => {
            let compile_id = id.replace("generate", "compile");
            (
                "morphir.backend.generate",
                json!({"ir":observed(records,&compile_id)?["ir"],"target":"python"}),
            )
        }
        "generate-model-vthree" | "generate-model-vfour" => {
            let compile_id = id.replace("generate", "compile");
            (
                GENERATE,
                generate(observed(records, &compile_id)?["model"].clone(), v),
            )
        }
        "generate-independent-vthree"
        | "generate-independent-vfour"
        | "wide-generate"
        | "legacy-model-refused"
        | "narrow-generate-refused" => (GENERATE, generate(model(document, v), v)),
        "bounded-model-refused"
        | "bounded-request-cannot-widen"
        | "decoded-model-refused"
        | "depth-model-refused"
        | "nodes-model-refused" => {
            let mut p = generate(model(document, v), v);
            if id == "bounded-request-cannot-widen" {
                p["modelTransport"] = support();
            }
            (GENERATE, p)
        }
        "bad-digest"
        | "bad-length"
        | "bad-base64"
        | "bad-json"
        | "bad-version"
        | "bad-ir-version"
        | "tuple-mismatch"
        | "tuple-operation"
        | "unknown-critical"
        | "unsupported-ion"
        | "unsupported-ion-evidence"
        | "unsupported-guarantee" => {
            let mut p = generate(model(document, v), v);
            match id {
                "bad-digest" => p["model"]["payload"]["sha256"] = json!("0".repeat(64)),
                "bad-length" => p["model"]["payload"]["decodedByteLength"] = json!(0),
                "bad-base64" => p["model"]["payload"]["content"] = json!("%%%="),
                "bad-json" => p["model"]["payload"] = payload(b"{", "morphir-json"),
                "bad-version" => p["model"]["envelopeVersion"] = json!("0.1.0-draft.2"),
                "bad-ir-version" => p["model"]["irVersion"] = json!("3.0.0"),
                "tuple-mismatch" => p["input"]["codec"] = json!("ion-binary"),
                "tuple-operation" => p["input"]["operation"] = json!(COMPILE),
                "unknown-critical" => p["model"]["critical"] = json!(["payload.future"]),
                "unsupported-ion" => {
                    p["input"]["codec"] = json!("ion-binary");
                    p["input"]["profile"] = json!("morphir-model");
                    p["model"]["profile"] = json!("morphir-model");
                    p["model"]["payload"] = payload(
                        include_bytes!("../../../../spec/mep/mck/fixtures/rich-model.ionb"),
                        "ion-binary",
                    );
                }
                "unsupported-ion-evidence" => {
                    p["model"]["evidence"] = json!([{"guarantee":"urn:morphir:mck:optional","modelId":p["model"]["modelId"],"modelRevision":p["model"]["revision"],"contextDigest":"c".repeat(64),"scope":"urn:morphir:mck:package","producer":"urn:morphir:mck:fixture","evidence":payload(include_bytes!("../../../../spec/mep/mck/fixtures/rich-model.ionb"),"ion-binary")}])
                }
                "unsupported-guarantee" => {
                    p["requiredGuarantees"] = json!([{"guarantee":"urn:morphir:mck:unavailable","scope":"urn:morphir:mck:package"}])
                }
                _ => unreachable!(),
            }
            (GENERATE, p)
        }
        "unsupported-distribution" | "unsupported-application" => {
            let ir = if id == "unsupported-distribution" {
                json!({"formatVersion":4,"distribution":{"Specs":{"packageName":"mck/python","dependencies":{},"spec":{"modules":{}}}}})
            } else {
                json!({"formatVersion":4,"distribution":{"Application":{"packageName":"mck/python","dependencies":{},"def":{"modules":{}},"entryPoints":{}}}})
            };
            (
                "morphir.backend.generate",
                json!({"ir":ir,"target":"python"}),
            )
        }
        "invalid-params" => (COMPILE, json!([])),
        "malformed-source" | "types-only-functions" => {
            let mut p = compile(document, v, true);
            if id == "malformed-source" {
                p["sources"]["documents"][0]["text"] = json!("def broken(:\n");
            } else {
                p["options"]["typesOnly"] = json!(true);
            }
            (COMPILE, p)
        }
        id if id.ends_with("shutdown") => ("morphir.shutdown", json!({})),
        id if is_exit(id) => ("morphir.exit", json!({})),
        _ => return Err(format!("unknown Python guest case {id}")),
    };
    let mut request = json!({"method":method,"params":params});
    if !id.ends_with("silent") && !is_exit(id) {
        request["id"] = match id {
            "id-u64-max" => json!(u64::MAX),
            "id-string" => json!("mck-λ-identity"),
            "id-empty-string" => json!(""),
            _ => json!(format!("mck:{id}")),
        };
    }
    Ok(request)
}

fn capabilities(value: &Value) -> Result<(), String> {
    for operation in ["frontend", "backend"] {
        let capability = &value[operation];
        let versions = capability["irVersions"]
            .as_array()
            .ok_or("IR versions missing")?;
        for (short, full) in [("3", "3.0.0"), ("4", "4.0.0")] {
            require(
                versions.iter().any(|v| v == short || v == full),
                "operation excludes required IR version",
            )?;
        }
    }
    require(
        value["frontend"]["compile"] == true && value["backend"]["generate"] == true,
        "compile/generate capabilities missing",
    )?;
    require(
        value["frontend"]["languages"]
            .as_array()
            .is_some_and(|a| a.iter().any(|v| v["id"] == "python")),
        "Python frontend missing",
    )?;
    require(
        value["backend"]["targets"]
            .as_array()
            .is_some_and(|a| a.contains(&json!("python"))),
        "Python backend missing",
    )
}
fn same_tuples(actual: &Value, expected: &Value) -> Result<(), String> {
    let actual = actual.as_array().ok_or("complete tuples missing")?;
    let expected = expected.as_array().unwrap();
    require(
        actual.len() == expected.len()
            && expected
                .iter()
                .all(|e| actual.iter().filter(|v| *v == e).count() == 1),
        "complete tuples missing, duplicated or unoffered",
    )
}
fn valid_identity(value: &Value) -> Result<(), String> {
    require(
        value["id"] == "morphir-python"
            && value["name"].as_str().is_some_and(|s| !s.is_empty())
            && value["version"]
                .as_str()
                .is_some_and(|s| semver::Version::parse(s).is_ok()),
        "Python extension identity is incomplete",
    )
}

pub(super) fn compare(
    document: &Document,
    record: &Record,
    previous: &[Record],
) -> Result<(), String> {
    let id = record.case_id.as_str();
    if id.ends_with("silent") {
        return require(
            record.observed == json!({"silent":true}),
            "notification emitted output",
        );
    }
    if is_exit(id) {
        return require(
            record.observed == json!({"exitSuccess":true,"stdoutClosed":true}),
            "unclean exit",
        );
    }
    crate::transport::session::validate_mep_response_id(&record.observed, &record.request["id"])
        .map_err(|e| e.to_string())?;
    let v = version(id);
    match id {
        "describe" => {
            let result = rpc_result(record)?;
            require(
                result["claimsVersion"] == "0.1.0-draft.2",
                "unsupported claims version",
            )?;
            require(
                result["protocolVersions"].as_array().is_some_and(|a| {
                    a.contains(&json!("0.1"))
                        && a.contains(&json!("0.2.0-draft.1"))
                        && !a.contains(&json!("0.2.0-draft.2"))
                }),
                "legacy and exact draft support missing",
            )?;
            valid_identity(&result["extension"])?;
            capabilities(&result["capabilities"])?;
            let claimed = &result["capabilities"]["modelTransport"];
            same_tuples(&claimed["tuples"], &support()["tuples"])?;
            require(
                claimed["guarantees"] == json!([]),
                "JSON profile must not claim preservation guarantees",
            )?;
            for (key, needed) in support()["limits"].as_object().unwrap() {
                require(
                    claimed["limits"][key]
                        .as_u64()
                        .is_some_and(|n| n >= needed.as_u64().unwrap() && n <= i32::MAX as u64),
                    "static model limit excludes the fixed profile",
                )?;
            }
            Ok(())
        }
        "describe-immutable" => require(
            rpc_result(record)? == observed(previous, "describe")?,
            "static description mutated",
        ),
        "initialize" | "narrow-initialize" | "bounded-initialize" | "decoded-initialize"
        | "depth-initialize" | "nodes-initialize" | "wide-initialize" | "legacy-initialize" => {
            let result = rpc_result(record)?;
            let description = observed(previous, "describe")?;
            capabilities(&result["capabilities"])?;
            require(
                result["extension"] == description["extension"],
                "initialized identity differs from description",
            )?;
            if id == "legacy-initialize" {
                return require(
                    result["protocolVersion"] == "0.1"
                        && result["capabilities"].get("modelTransport").is_none(),
                    "legacy negotiation admitted model transport",
                );
            }
            require(
                result["protocolVersion"] == "0.2.0-draft.1",
                "wrong model protocol version",
            )?;
            let mut expected = offer(id);
            for (key, value) in expected["limits"].as_object_mut().unwrap() {
                let claimed = description["capabilities"]["modelTransport"]["limits"][key]
                    .as_u64()
                    .ok_or("static limit missing")?;
                *value = json!(value.as_u64().unwrap().min(claimed));
            }
            let selected = &result["capabilities"]["modelTransport"];
            same_tuples(&selected["tuples"], &expected["tuples"])?;
            require(
                selected["limits"] == expected["limits"] && selected["guarantees"] == json!([]),
                "bilateral selected limits or guarantees differ",
            )
        }
        "compile-json-vthree"
        | "compile-json-vfour"
        | "roundtrip-json-vthree"
        | "roundtrip-json-vfour"
        | "legacy-compile-vthree"
        | "legacy-compile-vfour" => {
            let result = successful_compile(record)?;
            require(
                result["ir"] == document.expected_ir_versions[v],
                "JSON compilation differs from frozen semantic IR",
            )?;
            require(
                result["irVersion"] == v || result["irVersion"] == v[..1],
                "compile result IR version differs",
            )
        }
        "compile-model-vthree"
        | "compile-model-vfour"
        | "roundtrip-model-vthree"
        | "roundtrip-model-vfour"
        | "compile-model-repeat"
        | "recover-after-refusals"
        | "narrow-compile" => {
            let result = successful_compile(record)?;
            validate_compiled(document, &result["model"], v)?;
            if id == "compile-model-repeat" {
                require(
                    result["model"] == observed(previous, "compile-model-vfour")?["model"],
                    "repeated compilation changed model identity or bytes",
                )?;
            }
            Ok(())
        }
        "generate-json-vthree"
        | "generate-json-vfour"
        | "generate-model-vthree"
        | "generate-model-vfour"
        | "generate-independent-vthree"
        | "generate-independent-vfour"
        | "legacy-generate-vthree"
        | "legacy-generate-vfour"
        | "wide-generate" => validate_generated(document, rpc_result(record)?),
        "malformed-source"
        | "types-only-functions"
        | "unsupported-distribution"
        | "unsupported-application" => {
            let result = rpc_result(record)?;
            require(
                result["success"] == false
                    && result.get("model").is_none()
                    && result.get("ir").is_none()
                    && result.get("artifacts").is_none_or(|a| a == &json!([])),
                "refusal returned a model, IR or artifacts",
            )?;
            failure_diagnostics(result)
        }
        "before-initialize" | "after-shutdown" => expect_error(record, -32014),
        "bad-protocol-initialize" => expect_error(record, -32011),
        "duplicate-initialize" => expect_error(record, -32600),
        "legacy-model-refused" | "narrow-generate-refused" => expect_error(record, -32013),
        "unknown-method" => expect_error(record, -32601),
        "id-u64-max" | "id-string" | "id-empty-string" | "bounded-recovery-ping" => {
            rpc_result(record)?;
            Ok(())
        }
        id if id.ends_with("shutdown") => {
            rpc_result(record)?;
            Ok(())
        }
        _ => expect_error(record, -32602),
    }
}
fn successful_compile(record: &Record) -> Result<&Value, String> {
    let result = rpc_result(record)?;
    require(
        result["success"] == true
            && result["diagnostics"] == json!([])
            && result["modules"] == json!(["main"]),
        "compile is not a clean successful main module",
    )?;
    Ok(result)
}
fn validate_compiled(document: &Document, model: &Value, version: &str) -> Result<(), String> {
    require(
        model["envelopeVersion"] == "0.1.0-draft.1"
            && model["profile"] == "morphir-ir"
            && model["irVersion"] == version
            && model["payload"]["codec"] == "morphir-json",
        "compiled model tuple mismatch",
    )?;
    require(
        ["modelId", "revision"]
            .iter()
            .all(|key| model[key].as_str().is_some_and(|s| !s.is_empty())),
        "compiled logical identity missing",
    )?;
    if let Some(critical) = model.get("critical") {
        let known = [
            "envelopeVersion",
            "modelId",
            "revision",
            "irVersion",
            "profile",
            "payload",
            "payload.codec",
            "payload.layout",
            "payload.decodedByteLength",
            "payload.sha256",
            "payload.content",
            "evidence",
            "critical",
        ];
        require(
            critical.as_array().is_some_and(|a| {
                a.iter()
                    .all(|v| v.as_str().is_some_and(|s| known.contains(&s)))
            }),
            "compiled unknown critical member",
        )?;
    }
    require(
        model.get("evidence").is_none_or(|v| v == &json!([])),
        "JSON compilation must not invent guarantee evidence",
    )?;
    let bytes = decode_payload(&model["payload"])?;
    let text = std::str::from_utf8(&bytes).map_err(|e| e.to_string())?;
    let ir = crate::json::strict::parse_exact(text)?;
    let mut nodes = 0;
    fn bounded(value: &Value, depth: usize, nodes: &mut usize) -> Result<(), String> {
        *nodes += 1;
        require(
            depth < 128 && *nodes <= 100000,
            "JSON model structural limit exceeded",
        )?;
        match value {
            Value::Array(values) => {
                for value in values {
                    bounded(value, depth + 1, nodes)?;
                }
            }
            Value::Object(values) => {
                for value in values.values() {
                    bounded(value, depth + 1, nodes)?;
                }
            }
            _ => {}
        }
        Ok(())
    }
    bounded(&ir, 0, &mut nodes)?;
    require(
        ir == document.expected_ir_versions[version],
        "compiled JSON model differs from frozen semantic IR",
    )
}
fn validate_generated(document: &Document, result: &Value) -> Result<(), String> {
    require(
        result["success"] == true && result["diagnostics"] == json!([]),
        "generation failed or diagnosed",
    )?;
    let artifacts = result["artifacts"]
        .as_array()
        .ok_or("generated artifacts missing")?;
    let mut by_path = BTreeMap::new();
    for artifact in artifacts {
        let path = artifact["path"].as_str().ok_or("generated path missing")?;
        require(
            by_path.insert(path, artifact).is_none(),
            "duplicate generated path",
        )?;
    }
    require(
        by_path.keys().copied().collect::<Vec<_>>()
            == document
                .expected_artifacts
                .keys()
                .map(String::as_str)
                .collect::<Vec<_>>(),
        "generated artifact inventory differs",
    )?;
    for (path, text) in &document.expected_artifacts {
        let artifact = by_path[path.as_str()];
        require(
            artifact["content"] == *text && artifact.get("binary").is_none_or(|v| v == false),
            "generated source differs from frozen artifact",
        )?;
    }
    Ok(())
}

#[cfg(test)]
#[path = "python_tests.rs"]
mod tests;
