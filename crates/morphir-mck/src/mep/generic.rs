//! Generic JSON Library profile in the shared executable guest suite.
//! Any extension identity qualifies. The plan follows the guest's recorded
//! describe claim, so `report-check` rebuilds it from the report alone.
//! Outputs are compared by meaning: compiled IR under fixed equivalence rules,
//! generated files by a round trip through the guest's own frontend.
use super::*;

pub(super) const PROFILE: &str = "generic-json-library-v1";
const LEGACY_COMPILE: &str = "morphir.frontend.compile";
const LEGACY_GENERATE: &str = "morphir.backend.generate";
const MODEL_PROTOCOL: &str = "0.2.0-draft.1";
const VERSIONS: [&str; 2] = ["3.0.0", "4.0.0"];

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct Document {
    contract_version: semver::Version,
    profile: String,
    package: Value,
    context_digest: String,
    expected_ir_versions: BTreeMap<String, Value>,
    languages: BTreeMap<String, Language>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Language {
    documents: Vec<SourceDocument>,
    malformed: Vec<SourceDocument>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SourceDocument {
    uri: String,
    text: String,
}

/// A path relative to the source folder: no scheme, root, drive, backslash,
/// empty or dot segment, and no `src/` prefix.
fn relative_path(path: &str, allow_src: bool) -> bool {
    !path.is_empty()
        && !path.starts_with('/')
        && !path.contains(['\\', ':'])
        && path
            .split('/')
            .all(|segment| !segment.is_empty() && segment != "." && segment != "..")
        && (allow_src || path.split('/').next() != Some("src"))
}

pub(super) fn load(value: Value) -> Result<Document, String> {
    let document: Document = serde_json::from_value(value).map_err(|e| e.to_string())?;
    require(
        document.contract_version == semver::Version::parse(CONTRACT).unwrap()
            && document.profile == PROFILE
            && document.package["name"]
                .as_str()
                .is_some_and(|s| !s.is_empty())
            && document.package["exposedModules"]
                .as_array()
                .is_some_and(|m| !m.is_empty() && m.iter().all(Value::is_string))
            && document.package.as_object().is_some_and(|p| p.len() == 2)
            && document.context_digest.len() == 64
            && document
                .context_digest
                .bytes()
                .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
            && document
                .expected_ir_versions
                .keys()
                .map(String::as_str)
                .eq(VERSIONS)
            && !document.languages.is_empty(),
        "unsupported or incomplete generic JSON guest kit",
    )?;
    for (version, ir) in &document.expected_ir_versions {
        require(
            ir["formatVersion"] == if version == "3.0.0" { 3 } else { 4 },
            "fixed IR version mismatch",
        )?;
    }
    for (id, language) in &document.languages {
        require(!id.is_empty(), "language id missing")?;
        for set in [&language.documents, &language.malformed] {
            require(!set.is_empty(), "language source set is empty")?;
            let mut uris = std::collections::BTreeSet::new();
            for doc in set {
                require(
                    relative_path(&doc.uri, false),
                    "document URI must be relative to the source folder",
                )?;
                require(uris.insert(&doc.uri), "duplicate document URI")?;
            }
        }
    }
    Ok(document)
}

/// What the recorded describe claim selects. A pure function of the kit and
/// that one observation.
#[derive(Debug, PartialEq, Eq)]
pub(super) struct Selection {
    pub(super) language: String,
    pub(super) extensions: Vec<String>,
    pub(super) versions: Vec<&'static str>,
    pub(super) model_versions: Vec<&'static str>,
}

fn claims_version(list: &Value, full: &str) -> bool {
    list.as_array()
        .is_some_and(|a| a.iter().any(|v| v == full || v == &full[..1]))
}
fn json_tuple(operation: &str, version: &str) -> Value {
    json!({"operation":operation,"profile":"morphir-ir","codec":"morphir-json","envelopeVersion":"0.1.0-draft.1","irVersion":version})
}

pub(super) fn select(document: &Document, claim: &Value) -> Result<Selection, String> {
    let caps = &claim["capabilities"];
    let frontend = &caps["frontend"];
    let backend = &caps["backend"];
    require(
        frontend["compile"] == true && backend["generate"] == true,
        "compile/generate capabilities missing",
    )?;
    let claimed = frontend["languages"]
        .as_array()
        .cloned()
        .unwrap_or_default();
    let targets = backend["targets"].as_array().cloned().unwrap_or_default();
    let language = document
        .languages
        .keys()
        .find(|id| {
            claimed.iter().any(|l| l["id"] == id.as_str())
                && targets.iter().any(|t| t == id.as_str())
        })
        .ok_or("guest claims no kit language as both frontend language and backend target")?;
    let extensions = claimed
        .iter()
        .find(|l| l["id"] == language.as_str())
        .and_then(|l| l["fileExtensions"].as_array())
        .map(|e| {
            e.iter()
                .filter_map(|x| x.as_str().map(str::to_owned))
                .collect()
        })
        .unwrap_or_default();
    let versions = VERSIONS
        .into_iter()
        .filter(|v| {
            claims_version(&frontend["irVersions"], v) && claims_version(&backend["irVersions"], v)
        })
        .collect::<Vec<_>>();
    require(
        !versions.is_empty(),
        "guest claims no IR version 3 or 4 for both frontend and backend",
    )?;
    let model_versions = if claim["protocolVersions"]
        .as_array()
        .is_some_and(|a| a.contains(&json!(MODEL_PROTOCOL)))
    {
        let tuples = caps["modelTransport"]["tuples"]
            .as_array()
            .cloned()
            .unwrap_or_default();
        versions
            .iter()
            .copied()
            .filter(|v| {
                tuples.contains(&json_tuple(COMPILE, v))
                    && tuples.contains(&json_tuple(GENERATE, v))
            })
            .collect()
    } else {
        vec![]
    };
    Ok(Selection {
        language: language.clone(),
        extensions,
        versions,
        model_versions,
    })
}

fn suffix(version: &str) -> &'static str {
    if version == "3.0.0" {
        "vthree"
    } else {
        "vfour"
    }
}
/// Split a case id into its base and selected IR version.
fn parse(id: &str) -> (&str, Option<&'static str>) {
    if let Some(base) = id.strip_suffix("-vthree") {
        (base, Some("3.0.0"))
    } else if let Some(base) = id.strip_suffix("-vfour") {
        (base, Some("4.0.0"))
    } else {
        (id, None)
    }
}

fn selection(document: &Document, records: &[Record]) -> Result<Selection, String> {
    select(
        document,
        rpc_result(records.first().ok_or("describe observation missing")?)?,
    )
}

/// The complete case plan. Until a valid describe claim is recorded the plan is
/// only `describe`; its comparison then reports why nothing could be selected.
pub(super) fn plan(document: &Document, records: &[Record]) -> Vec<String> {
    let mut plan = vec!["describe".to_owned()];
    let Ok(selected) = selection(document, records) else {
        return plan;
    };
    plan.extend(
        [
            "initialize",
            "initialized-silent",
            "unknown-notification-silent",
        ]
        .map(str::to_owned),
    );
    for v in &selected.versions {
        for base in ["compile", "generate", "roundtrip", "generate-independent"] {
            plan.push(format!("{base}-{}", suffix(v)));
        }
    }
    plan.extend(
        [
            "malformed-source",
            "unknown-method",
            "describe-immutable",
            "shutdown",
            "after-shutdown",
            "exit",
        ]
        .map(str::to_owned),
    );
    if !selected.model_versions.is_empty() {
        plan.extend(["model-initialize", "model-initialized-silent"].map(str::to_owned));
        for v in &selected.model_versions {
            for base in [
                "compile-model",
                "generate-model",
                "generate-model-independent",
            ] {
                plan.push(format!("{base}-{}", suffix(v)));
            }
        }
        plan.extend(["bad-digest", "model-shutdown", "model-exit"].map(str::to_owned));
    }
    plan
}

fn limits() -> Value {
    json!({"maxEncodedBytes":1000000,"maxDecodedBytes":750000,"maxDepth":128,"maxNodes":100000})
}
fn offer(selected: &Selection) -> Value {
    let tuples = selected
        .model_versions
        .iter()
        .flat_map(|v| [json_tuple(COMPILE, v), json_tuple(GENERATE, v)])
        .collect::<Vec<_>>();
    json!({"tuples":tuples,"limits":limits(),"guarantees":[]})
}
fn host() -> Value {
    json!({"name":"morphir-mck","version":env!("CARGO_PKG_VERSION")})
}
fn observed<'a>(records: &'a [Record], id: &str) -> Result<&'a Value, String> {
    rpc_result(
        records
            .iter()
            .find(|r| r.case_id == id)
            .ok_or_else(|| format!("missing {id}"))?,
    )
}
fn compile_params(
    document: &Document,
    language: &str,
    documents: Vec<Value>,
    version: &str,
    model: bool,
) -> Value {
    let mut params = json!({
        "languageId": language,
        "sources": {"documents": documents},
        "package": document.package,
        "options": {"typesOnly": false, "irVersion": version},
        "contextDigest": document.context_digest,
    });
    if model {
        params["output"] = json_tuple(COMPILE, version);
    }
    params
}
fn source_documents(language: &str, set: &[SourceDocument]) -> Vec<Value> {
    set.iter()
        .map(|d| json!({"uri":d.uri,"languageId":language,"version":1,"text":d.text}))
        .collect()
}
fn matches_extension(path: &str, extensions: &[String]) -> bool {
    extensions.is_empty() || extensions.iter().any(|e| path.ends_with(e.as_str()))
}
fn model(document: &Document, version: &str) -> Value {
    let bytes = serde_json::to_vec(&document.expected_ir_versions[version]).unwrap();
    json!({"envelopeVersion":"0.1.0-draft.1","modelId":"urn:morphir:mck:generic","revision":"independent-1","irVersion":version,"profile":"morphir-ir","payload":payload(&bytes,"morphir-json")})
}
fn generate_model(model: Value, language: &str, version: &str, digest: &str) -> Value {
    json!({"model":model,"input":json_tuple(GENERATE,version),"target":language,"contextDigest":digest})
}

pub(super) fn request(document: &Document, id: &str, records: &[Record]) -> Result<Value, String> {
    let (base, version) = parse(id);
    let (method, params) = if base == "describe" {
        (
            "morphir.extension.describe",
            json!({"protocolVersions":[MODEL_PROTOCOL,"0.1"]}),
        )
    } else {
        let selected = selection(document, records)?;
        let language = selected.language.as_str();
        let v = version.unwrap_or(selected.versions[0]);
        match base {
            "describe-immutable" => (
                "morphir.extension.describe",
                json!({"protocolVersions":[MODEL_PROTOCOL,"0.1"]}),
            ),
            "initialize" => (
                "morphir.initialize",
                json!({"protocolVersions":["0.1"],"host":host()}),
            ),
            "model-initialize" => (
                "morphir.initialize",
                json!({"protocolVersions":[MODEL_PROTOCOL],"host":host(),"modelTransport":offer(&selected)}),
            ),
            "initialized-silent" | "model-initialized-silent" => ("morphir.initialized", json!({})),
            "unknown-notification-silent" | "unknown-method" => ("morphir.mck.unknown", json!({})),
            "after-shutdown" => ("morphir.ping", json!({})),
            "compile" | "compile-model" => (
                if base == "compile" {
                    LEGACY_COMPILE
                } else {
                    COMPILE
                },
                compile_params(
                    document,
                    language,
                    source_documents(language, &document.languages[language].documents),
                    v,
                    base == "compile-model",
                ),
            ),
            "malformed-source" => (
                LEGACY_COMPILE,
                compile_params(
                    document,
                    language,
                    source_documents(language, &document.languages[language].malformed),
                    v,
                    false,
                ),
            ),
            "generate" => (
                LEGACY_GENERATE,
                json!({"ir":observed(records,&format!("compile-{}",suffix(v)))?["ir"],"target":language}),
            ),
            "generate-independent" => (
                LEGACY_GENERATE,
                json!({"ir":document.expected_ir_versions[v],"target":language}),
            ),
            "roundtrip" => {
                let generated = observed(records, &format!("generate-{}", suffix(v)))?;
                let documents = generated["artifacts"]
                    .as_array()
                    .ok_or("generated artifacts missing")?
                    .iter()
                    .filter(|a| {
                        a["path"]
                            .as_str()
                            .is_some_and(|p| matches_extension(p, &selected.extensions))
                    })
                    .map(|a| {
                        json!({"uri":a["path"],"languageId":language,"version":1,"text":a["content"]})
                    })
                    .collect();
                (
                    LEGACY_COMPILE,
                    compile_params(document, language, documents, v, false),
                )
            }
            "generate-model" => (
                GENERATE,
                generate_model(
                    observed(records, &format!("compile-model-{}", suffix(v)))?["model"].clone(),
                    language,
                    v,
                    &document.context_digest,
                ),
            ),
            "generate-model-independent" | "bad-digest" => {
                let v = version.unwrap_or(selected.model_versions[0]);
                let mut p =
                    generate_model(model(document, v), language, v, &document.context_digest);
                if base == "bad-digest" {
                    p["model"]["payload"]["sha256"] = json!("0".repeat(64));
                }
                (GENERATE, p)
            }
            "shutdown" | "model-shutdown" => ("morphir.shutdown", json!({})),
            "exit" | "model-exit" => ("morphir.exit", json!({})),
            _ => return Err(format!("unknown generic guest case {id}")),
        }
    };
    let mut request = json!({"method":method,"params":params});
    if !id.ends_with("silent") && !is_exit(id) {
        request["id"] = json!(next_id(records));
    }
    Ok(request)
}

/// Numeric request ids, counted from 1 in each guest process. Identity echo of
/// other id forms is outside this profile.
fn next_id(records: &[Record]) -> u64 {
    let start = records
        .iter()
        .rposition(|r| is_exit(&r.case_id))
        .map_or(0, |i| i + 1);
    records[start..]
        .iter()
        .filter(|r| !r.case_id.ends_with("silent"))
        .count() as u64
        + 1
}

/// Equivalence for compiled IR. Only three rules apply: JSON object member
/// order; the order of the IR 3 `modules`, `types` and `values` name-keyed
/// lists; and the IR 4 short form of a `Reference` without arguments.
pub(super) fn canonical(value: &Value) -> Value {
    match value {
        Value::Array(items) => Value::Array(items.iter().map(canonical).collect()),
        Value::Object(fields) => {
            if fields.len() == 1
                && let Some(Value::Object(reference)) = fields.get("Reference")
                && reference.get("fqname").is_some_and(Value::is_string)
                && reference.keys().all(|k| k == "fqname" || k == "args")
                && reference.get("args").is_none_or(|a| a == &json!([]))
            {
                return reference["fqname"].clone();
            }
            let mut out = serde_json::Map::new();
            for (key, item) in fields {
                let mut item = canonical(item);
                if matches!(key.as_str(), "modules" | "types" | "values")
                    && let Value::Array(entries) = &mut item
                    && entries
                        .iter()
                        .all(|e| e.as_array().is_some_and(|pair| pair.len() == 2))
                {
                    entries.sort_by_key(|e| e[0].to_string());
                }
                out.insert(key.clone(), item);
            }
            Value::Object(out)
        }
        _ => value.clone(),
    }
}
fn same_ir(actual: &Value, expected: &Value) -> bool {
    canonical(actual) == canonical(expected)
}

fn diagnostics_without_error(result: &Value) -> Result<(), String> {
    let diagnostics = result["diagnostics"]
        .as_array()
        .ok_or("diagnostics must be an array")?;
    for diagnostic in diagnostics {
        require(
            diagnostic["message"].is_string()
                && diagnostic["severity"]
                    .as_str()
                    .is_some_and(|s| matches!(s, "warning" | "info" | "hint")),
            "successful result has an error or malformed diagnostic",
        )?;
    }
    Ok(())
}
fn successful_compile<'a>(record: &'a Record, version: &str) -> Result<&'a Value, String> {
    let result = rpc_result(record)?;
    require(result["success"] == true, "compile did not succeed")?;
    diagnostics_without_error(result)?;
    if let Some(reported) = result.get("irVersion") {
        require(
            reported == version || reported == &version[..1],
            "compile result IR version differs",
        )?;
    }
    Ok(result)
}
fn validate_generated(result: &Value, selected: &Selection) -> Result<(), String> {
    require(result["success"] == true, "generation did not succeed")?;
    diagnostics_without_error(result)?;
    let artifacts = result["artifacts"]
        .as_array()
        .filter(|a| !a.is_empty())
        .ok_or("generated artifacts missing")?;
    let mut paths = std::collections::BTreeSet::new();
    for artifact in artifacts {
        let path = artifact["path"].as_str().ok_or("generated path missing")?;
        require(relative_path(path, true), "generated path is not relative")?;
        require(paths.insert(path), "duplicate generated path")?;
        require(
            artifact["content"].is_string() && artifact.get("binary").is_none_or(|b| b == false),
            "generated artifact must be text",
        )?;
    }
    require(
        paths
            .iter()
            .any(|p| matches_extension(p, &selected.extensions)),
        "no generated file has a claimed file extension of the language",
    )
}
fn validate_model(document: &Document, model: &Value, version: &str) -> Result<(), String> {
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
    require(
        model.get("evidence").is_none_or(|v| v == &json!([]))
            && model.get("critical").is_none_or(|v| v == &json!([])),
        "JSON compilation must not add evidence or critical members",
    )?;
    let bytes = decode_payload(&model["payload"])?;
    let ir =
        crate::json::strict::parse_exact(std::str::from_utf8(&bytes).map_err(|e| e.to_string())?)?;
    require(
        same_ir(&ir, &document.expected_ir_versions[version]),
        "compiled JSON model differs from the fixed semantic IR",
    )
}
fn valid_identity(value: &Value) -> Result<(), String> {
    require(
        value["id"].as_str().is_some_and(|s| !s.is_empty())
            && value["name"].as_str().is_some_and(|s| !s.is_empty())
            && value["version"]
                .as_str()
                .is_some_and(|s| semver::Version::parse(s).is_ok()),
        "extension identity is incomplete",
    )
}
fn same_tuples(actual: &Value, expected: &Value) -> Result<(), String> {
    let actual = actual.as_array().ok_or("selected tuples missing")?;
    let expected = expected.as_array().unwrap();
    require(
        actual.len() == expected.len()
            && expected
                .iter()
                .all(|e| actual.iter().filter(|v| *v == e).count() == 1),
        "selected tuples missing, duplicated or unoffered",
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
    if id == "describe" {
        let result = rpc_result(record)?;
        require(
            result["claimsVersion"].is_string(),
            "claims version missing",
        )?;
        require(
            result["protocolVersions"]
                .as_array()
                .is_some_and(|a| a.contains(&json!("0.1"))),
            "legacy protocol 0.1 support missing",
        )?;
        valid_identity(&result["extension"])?;
        select(document, result)?;
        return Ok(());
    }
    let selected = selection(document, previous)?;
    let describe = observed(previous, "describe")?;
    let (base, version) = parse(id);
    let v = version.unwrap_or(selected.versions[0]);
    match base {
        "describe-immutable" => require(
            rpc_result(record)? == describe,
            "static description mutated",
        ),
        "initialize" | "model-initialize" => {
            let result = rpc_result(record)?;
            require(
                result["extension"] == describe["extension"],
                "initialized identity differs from description",
            )?;
            let mut claim = result.clone();
            claim["protocolVersions"] = json!([]);
            let negotiated = select(document, &claim)?;
            require(
                negotiated.language == selected.language
                    && negotiated.versions == selected.versions,
                "initialized capabilities differ from the description",
            )?;
            if base == "initialize" {
                return require(
                    result["protocolVersion"] == "0.1"
                        && result["capabilities"].get("modelTransport").is_none(),
                    "legacy negotiation admitted model transport",
                );
            }
            require(
                result["protocolVersion"] == MODEL_PROTOCOL,
                "wrong model protocol version",
            )?;
            let mut expected = offer(&selected);
            for (key, value) in expected["limits"].as_object_mut().unwrap() {
                let claimed = describe["capabilities"]["modelTransport"]["limits"][key]
                    .as_u64()
                    .ok_or("static model limit missing")?;
                *value = json!(value.as_u64().unwrap().min(claimed));
            }
            let chosen = &result["capabilities"]["modelTransport"];
            same_tuples(&chosen["tuples"], &expected["tuples"])?;
            require(
                chosen["limits"] == expected["limits"]
                    && chosen.get("guarantees").is_none_or(|g| g == &json!([])),
                "bilateral selected limits or guarantees differ",
            )
        }
        "compile" | "roundtrip" => {
            let result = successful_compile(record, v)?;
            require(
                same_ir(&result["ir"], &document.expected_ir_versions[v]),
                "compiled IR differs from the fixed semantic IR",
            )
        }
        "compile-model" => {
            let result = successful_compile(record, v)?;
            validate_model(document, &result["model"], v)
        }
        "generate" | "generate-independent" | "generate-model" | "generate-model-independent" => {
            validate_generated(rpc_result(record)?, &selected)
        }
        "malformed-source" => {
            let result = rpc_result(record)?;
            require(
                result["success"] == false
                    && result.get("model").is_none()
                    && result.get("ir").is_none_or(Value::is_null)
                    && result.get("artifacts").is_none_or(|a| a == &json!([])),
                "refusal returned a model, IR or artifacts",
            )?;
            failure_diagnostics(result)
        }
        "unknown-method" => expect_error(record, -32601),
        "after-shutdown" => expect_error(record, -32014),
        "bad-digest" => expect_error(record, -32602),
        "shutdown" | "model-shutdown" => rpc_result(record).map(|_| ()),
        _ => Err(format!("unknown generic guest case {id}")),
    }
}

#[cfg(test)]
#[path = "generic_tests.rs"]
mod tests;
