//! Executable MEP guest qualification, through the shared MCK process boundary.
//! Fixed inputs and semantic expectations belong to the shared kit. No guest
//! implementation or IR codec participates in adjudication.

mod binary;
mod metadata;
#[cfg(test)]
mod replay_tests;

use crate::{
    kit::hash::sha256_hex,
    provenance::Driver,
    transport::{Limits, Session},
};
use base64::{Engine, engine::general_purpose::STANDARD};
use ion_rs::Element;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    ffi::OsString,
    io::Read,
    path::{Path, PathBuf},
    time::Duration,
};

pub const CONTRACT: &str = "0.1.0-draft.1";
pub const PROFILE: &str = "moonbit-model-bool-library-v1";
const COMPILE: &str = "morphir.frontend.compileModel";
const GENERATE: &str = "morphir.backend.generateModel";
const CASES: &[&str] = &[
    "describe",
    "initialize",
    "initialized-silent",
    "unknown-notification-silent",
    "compile-ion",
    "generate-retained",
    "compile-repeat",
    "generate-repeat",
    "unknown-ion-retained",
    "bad-digest",
    "recover-after-digest",
    "bad-length",
    "bad-base64",
    "bad-ion",
    "tuple-mismatch",
    "unknown-critical",
    "unknown-guarantee",
    "invalid-params",
    "malformed-source",
    "lossy-json-refused",
    "recover-after-source",
    "json-model-generate",
    "legacy-json-generate",
    "unknown-method",
    "describe-immutable",
    "shutdown",
    "after-shutdown",
    "exit",
    "legacy-initialize",
    "legacy-initialized-silent",
    "legacy-model-refused",
    "legacy-json",
    "legacy-shutdown",
    "legacy-exit",
    "narrow-initialize",
    "narrow-initialized-silent",
    "narrow-generate-refused",
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
];

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Document {
    contract_version: semver::Version,
    profile: String,
    mep_version: String,
    opaque_fixture: String,
    consumer: Consumer,
    source: Value,
    expected_ir: Value,
    plain_ir: Value,
    expected_json_artifacts: BTreeMap<String, String>,
    expected_artifacts: BTreeMap<String, String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Consumer {
    files: BTreeMap<String, String>,
    expected_stdout: String,
}

pub struct Kit {
    document: Document,
    pub digest: String,
}
impl Kit {
    pub fn profile(&self) -> &str {
        &self.document.profile
    }
    pub fn case_ids(&self) -> &[&str] {
        CASES
    }
}

pub fn load_kit(path: &Path) -> Result<Kit, String> {
    let bytes = std::fs::read(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let text = std::str::from_utf8(&bytes).map_err(|e| e.to_string())?;
    crate::json::strict::parse(text)?;
    let document: Document = serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
    if !semver::VersionReq::parse("=0.1.0-draft.1")
        .unwrap()
        .matches(&document.contract_version)
        || document.profile != PROFILE
        || document.mep_version != "0.2.0-draft.1"
        || !document.source.is_object()
        || !document.expected_ir.is_object()
        || document
            .consumer
            .files
            .keys()
            .map(String::as_str)
            .collect::<Vec<_>>()
            != ["main.mbt", "moon.mod", "moon.pkg"]
        || document.consumer.expected_stdout.is_empty()
        || document
            .expected_artifacts
            .keys()
            .map(String::as_str)
            .collect::<Vec<_>>()
            != ["library.mbt", "moon.mod", "moon.pkg"]
    {
        return Err("unsupported or incomplete MEP guest kit".into());
    }
    Ok(Kit {
        document,
        digest: sha256_hex(&bytes),
    })
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FileIdentity {
    pub path: PathBuf,
    pub sha256: String,
}
impl FileIdentity {
    pub fn read(path: &Path) -> Result<Self, String> {
        let path = path
            .canonicalize()
            .map_err(|e| format!("{}: {e}", path.display()))?;
        let bytes = std::fs::read(&path).map_err(|e| format!("{}: {e}", path.display()))?;
        Ok(Self {
            path,
            sha256: sha256_hex(&bytes),
        })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Identity {
    pub runner: Value,
    pub runner_binary: FileIdentity,
    pub host: FileIdentity,
    pub arguments: Vec<OsString>,
    pub files: Vec<FileIdentity>,
}
impl Identity {
    pub fn capture(host: &Path, args: &[OsString], files: &[PathBuf]) -> Result<Self, String> {
        if files.is_empty() {
            return Err("at least one pinned guest/host artifact is required".into());
        }
        let host = if host.components().count() == 1 {
            std::env::split_paths(&std::env::var_os("PATH").unwrap_or_default())
                .map(|p| p.join(host))
                .find(|p| p.is_file())
                .ok_or("host executable not found on PATH")?
        } else {
            host.to_owned()
        };
        Ok(Self {
            runner: serde_json::to_value(Driver::current()).unwrap(),
            runner_binary: FileIdentity::read(
                &std::env::current_exe().map_err(|e| e.to_string())?,
            )?,
            host: FileIdentity::read(&host)?,
            arguments: args.to_vec(),
            files: files
                .iter()
                .map(|p| FileIdentity::read(p))
                .collect::<Result<_, _>>()?,
        })
    }
    fn check(&self) -> Result<(), String> {
        if self.runner != serde_json::to_value(Driver::current()).unwrap() || self.files.is_empty()
        {
            return Err("runner identity differs or artifact identities are absent".into());
        }
        require(
            FileIdentity::read(&std::env::current_exe().map_err(|e| e.to_string())?)?
                == self.runner_binary,
            "report runner binary is not this checker executable",
        )?;
        for file in std::iter::once(&self.runner_binary)
            .chain(std::iter::once(&self.host))
            .chain(&self.files)
        {
            if FileIdentity::read(&file.path)? != *file {
                return Err(format!("identity changed: {}", file.path.display()));
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Record {
    pub case_id: String,
    pub request: Value,
    pub observed: Value,
}
#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Report {
    pub contract_version: String,
    pub suite: String,
    pub profile: String,
    pub corpus_sha256: String,
    pub identity: Identity,
    pub records: Vec<Record>,
    pub error: Option<String>,
    pub qualified: bool,
}

fn tuple(operation: &str, json_profile: bool) -> Value {
    json!({"operation":operation,"profile":if json_profile{"morphir-ir"}else{"morphir-model"},"codec":if json_profile{"morphir-json"}else{"ion-binary"},"envelopeVersion":"0.1.0-draft.1","irVersion":"4.0.0"})
}
fn support() -> Value {
    json!({"tuples":[tuple(COMPILE,false),tuple(GENERATE,false),tuple(COMPILE,true),tuple(GENERATE,true)],"limits":{"maxEncodedBytes":1000000,"maxDecodedBytes":750000,"maxDepth":128,"maxNodes":100000},"guarantees":[]})
}
fn compiled(records: &[Record]) -> Result<Value, String> {
    records
        .iter()
        .find(|r| r.case_id == "compile-ion")
        .and_then(|r| r.observed.pointer("/result/model"))
        .cloned()
        .ok_or("compiled model missing".into())
}
fn generated(model: Value) -> Value {
    json!({"model":model,"input":tuple(GENERATE,false),"target":"moonbit","contextDigest":"c".repeat(64)})
}
fn payload(bytes: &[u8], codec: &str) -> Value {
    json!({"codec":codec,"layout":"single-document","decodedByteLength":bytes.len(),"sha256":sha256_hex(bytes),"content":STANDARD.encode(bytes)})
}
fn json_model(kit: &Kit) -> Value {
    let bytes = serde_json::to_vec(&kit.document.plain_ir).unwrap();
    json!({"envelopeVersion":"0.1.0-draft.1","modelId":"urn:morphir:mck:bool","revision":"independent-1","irVersion":"4.0.0","profile":"morphir-ir","payload":payload(&bytes,"morphir-json")})
}
fn opaque_model(kit: &Kit, records: &[Record]) -> Result<Value, String> {
    let mut model = compiled(records)?;
    let bytes = decode_payload(&model["payload"])?;
    let element = binary::read(&bytes)?;
    metadata::validate_model(&kit.document.source, &element)?;
    let root = element.as_struct().ok_or("compiled model must be struct")?;
    let additions = Element::read_one(&kit.document.opaque_fixture).map_err(|e| e.to_string())?;
    let additions = additions
        .as_struct()
        .ok_or("opaque fixture must be struct")?;
    let mut builder = ion_rs::Struct::builder();
    for (key, value) in root.iter() {
        let extra = match key.text() {
            Some("enrichments") => Some("enrichment"),
            Some("provenance") => Some("provenance"),
            _ => None,
        };
        let value = if let Some(extra) = extra {
            Element::from(
                ion_rs::Sequence::builder()
                    .push_all(
                        value
                            .as_list()
                            .ok_or("model carrier must be list")?
                            .iter()
                            .cloned(),
                    )
                    .push(
                        additions
                            .get(extra)
                            .ok_or("opaque fixture member missing")?
                            .clone(),
                    )
                    .build_list(),
            )
        } else {
            value.clone()
        };
        builder = builder.with_field(key.clone(), value);
    }
    let altered = Element::from(
        builder
            .with_field(
                "futureBody",
                additions
                    .get("futureBody")
                    .ok_or("opaque fixture member missing")?
                    .clone(),
            )
            .build(),
    )
    .with_annotations(element.annotations().clone());
    let bytes = altered
        .encode_as(ion_rs::v1_0::Binary)
        .map_err(|e| e.to_string())?;
    model["payload"] = payload(&bytes, "ion-binary");
    model["revision"] = json!("independent-mck-opaque-revision");
    Ok(model)
}

fn request(kit: &Kit, id: &str, records: &[Record]) -> Result<Value, String> {
    let compile = || {
        let mut p = kit.document.source.clone();
        p["output"] = tuple(COMPILE, false);
        p
    };
    let model = || compiled(records);
    let (method, params) = match id {
        "describe" | "describe-immutable" => (
            "morphir.extension.describe",
            json!({"protocolVersions":["0.2.0-draft.1","0.1"]}),
        ),
        "initialize" | "narrow-initialize" | "bounded-initialize" => {
            let mut offer = support();
            if id == "narrow-initialize" {
                offer["tuples"] = json!([tuple(COMPILE, false)]);
            }
            if id == "bounded-initialize" {
                offer["limits"] =
                    json!({"maxEncodedBytes":128,"maxDecodedBytes":96,"maxDepth":2,"maxNodes":2});
            }
            (
                "morphir.initialize",
                json!({"protocolVersions":["0.2.0-draft.1"],"host":{"name":"morphir-mck","version":env!("CARGO_PKG_VERSION")},"modelTransport":offer}),
            )
        }
        "legacy-initialize" => (
            "morphir.initialize",
            json!({"protocolVersions":["0.1"],"host":{"name":"morphir-mck","version":env!("CARGO_PKG_VERSION")}}),
        ),
        "initialized-silent"
        | "legacy-initialized-silent"
        | "narrow-initialized-silent"
        | "bounded-initialized-silent" => ("morphir.initialized", json!({})),
        "unknown-notification-silent" => ("morphir.mck.unknown", json!({})),
        "compile-ion" | "compile-repeat" | "recover-after-source" | "narrow-compile" => {
            (COMPILE, compile())
        }
        "generate-retained"
        | "generate-repeat"
        | "recover-after-digest"
        | "legacy-model-refused"
        | "narrow-generate-refused" => (GENERATE, generated(model()?)),
        "unknown-ion-retained" => (GENERATE, generated(opaque_model(kit, records)?)),
        "bad-digest" | "bad-length" | "bad-base64" | "bad-ion" | "tuple-mismatch"
        | "unknown-critical" | "unknown-guarantee" => {
            let mut p = generated(model()?);
            match id {
                "bad-digest" => p["model"]["payload"]["sha256"] = json!("0".repeat(64)),
                "bad-length" => p["model"]["payload"]["decodedByteLength"] = json!(0),
                "bad-base64" => p["model"]["payload"]["content"] = json!("%%%="),
                "bad-ion" => p["model"]["payload"] = payload(b"not ion", "ion-binary"),
                "tuple-mismatch" => p["input"]["profile"] = json!("morphir-ir"),
                "unknown-critical" => p["model"]["critical"] = json!(["payload.future"]),
                "unknown-guarantee" => {
                    p["requiredGuarantees"] = json!([{"guarantee":"urn:morphir:mck:unavailable","scope":"urn:morphir:mck:package"}])
                }
                _ => unreachable!(),
            }
            (GENERATE, p)
        }
        "invalid-params" => (COMPILE, json!([])),
        "malformed-source" => {
            let mut p = compile();
            p["sources"]["documents"][0]["text"] = json!("pub fn {");
            (COMPILE, p)
        }
        "lossy-json-refused" => {
            let mut p = compile();
            p["output"] = tuple(COMPILE, true);
            (COMPILE, p)
        }
        "json-model-generate" => {
            let mut p = generated(json_model(kit));
            p["input"] = tuple(GENERATE, true);
            (GENERATE, p)
        }
        "bounded-model-refused" | "bounded-request-cannot-widen" => {
            let mut p = generated(json_model(kit));
            p["input"] = tuple(GENERATE, true);
            if id == "bounded-request-cannot-widen" {
                p["modelTransport"] = support();
            }
            (GENERATE, p)
        }
        "bounded-recovery-ping" => ("morphir.ping", json!({})),
        "legacy-json-generate" | "legacy-json" => (
            "morphir.backend.generate",
            json!({"ir":kit.document.plain_ir,"target":"moonbit"}),
        ),
        "unknown-method" => ("morphir.mck.unknown", json!({})),
        "after-shutdown" => ("morphir.ping", json!({})),
        "shutdown" | "legacy-shutdown" | "narrow-shutdown" | "bounded-shutdown" => {
            ("morphir.shutdown", json!({}))
        }
        "exit" | "legacy-exit" | "narrow-exit" | "bounded-exit" => ("morphir.exit", json!({})),
        _ => return Err("unknown guest case".into()),
    };
    Ok(json!({"method":method,"params":params}))
}

pub fn run_process(kit: &Kit, identity: Identity, limits: Limits) -> Report {
    let mut report = Report {
        contract_version: CONTRACT.into(),
        suite: "mep-guest".into(),
        profile: kit.profile().into(),
        corpus_sha256: kit.digest.clone(),
        identity,
        records: vec![],
        error: None,
        qualified: false,
    };
    let result = (|| -> Result<(), String> {
        let mut session = None;
        for id in CASES.iter().copied() {
            if session.is_none() {
                session = Some(
                    Session::spawn_mep(
                        report.identity.host.path.as_os_str(),
                        &report.identity.arguments,
                        limits,
                    )
                    .map_err(|e| e.to_string())?,
                );
            }
            let req = request(kit, id, &report.records)?;
            let method = req["method"].as_str().unwrap();
            let observed = if is_exit(id) {
                session.take().unwrap().close().map_err(|e| e.to_string())?;
                json!({"exitSuccess":true,"stdoutClosed":true})
            } else if id.ends_with("silent") {
                session
                    .as_mut()
                    .unwrap()
                    .notify_mep(method, &req["params"])
                    .map_err(|e| e.to_string())?;
                session
                    .as_mut()
                    .unwrap()
                    .assert_silence(Duration::from_millis(50))
                    .map_err(|e| e.to_string())?;
                json!({"silent":true})
            } else {
                session
                    .as_mut()
                    .unwrap()
                    .exchange_mep(method, &req["params"])
                    .map_err(|e| e.to_string())?
            };
            let record = Record {
                case_id: id.into(),
                request: req,
                observed,
            };
            let result = compare(kit, &record, &report.records);
            report.records.push(record);
            result.map_err(|e| format!("{id}: {e}"))?;
        }
        Ok(())
    })();
    report.error = result.err();
    finalize(kit, &mut report);
    report
}

fn finalize(kit: &Kit, report: &mut Report) {
    report.qualified = true;
    if report.error.is_none() {
        report.error = adjudicate(kit, report)
            .and_then(|()| report.identity.check())
            .err();
    }
    report.qualified = report.error.is_none();
}

pub fn check_report(kit: &Kit, value: &Value) -> Result<(), String> {
    let report: Report = serde_json::from_value(value.clone()).map_err(|e| e.to_string())?;
    adjudicate(kit, &report)?;
    report.identity.check()
}
pub fn check_report_file(kit: &Kit, path: &Path) -> Result<(), String> {
    let mut bytes = Vec::new();
    std::fs::File::open(path)
        .map_err(|e| e.to_string())?
        .take(32 * 1024 * 1024 + 1)
        .read_to_end(&mut bytes)
        .map_err(|e| e.to_string())?;
    require(bytes.len() <= 32 * 1024 * 1024, "MEP report exceeds 32 MiB")?;
    let text = std::str::from_utf8(&bytes).map_err(|e| e.to_string())?;
    check_report(kit, &crate::json::strict::parse(text)?)
}
fn adjudicate(kit: &Kit, report: &Report) -> Result<(), String> {
    if report.contract_version != CONTRACT
        || report.suite != "mep-guest"
        || report.profile != kit.profile()
        || report.corpus_sha256 != kit.digest
        || report.error.is_some()
        || report.records.len() != CASES.len()
    {
        return Err("incomplete report or mismatched corpus identity".into());
    }
    for (index, (id, record)) in CASES.iter().zip(&report.records).enumerate() {
        if record.case_id != *id || record.request != request(kit, id, &report.records[..index])? {
            return Err(format!("case order or request mismatch at {id}"));
        }
        compare(kit, record, &report.records[..index]).map_err(|e| format!("{id}: {e}"))?;
    }
    if !report.qualified {
        return Err("report does not claim qualification".into());
    }
    Ok(())
}

fn rpc_result(record: &Record) -> Result<&Value, String> {
    record
        .observed
        .get("result")
        .filter(|_| record.observed.get("error").is_none())
        .ok_or_else(|| format!("{} expected result", record.case_id))
}
fn expect_error(record: &Record, code: i64) -> Result<(), String> {
    if record
        .observed
        .pointer("/error/code")
        .and_then(Value::as_i64)
        == Some(code)
        && record.observed.get("result").is_none()
    {
        Ok(())
    } else {
        Err(format!("expected RPC error {code}"))
    }
}
fn is_exit(id: &str) -> bool {
    id == "exit" || id.ends_with("-exit")
}
fn diagnostic_position(value: &Value) -> Result<(u32, u32), String> {
    let component = |key: &str| {
        value[key]
            .as_u64()
            .and_then(|n| u32::try_from(n).ok())
            .ok_or("diagnostic position must contain u32 line/character".to_owned())
    };
    Ok((component("line")?, component("character")?))
}
fn diagnostic_location(value: &Value) -> Result<(), String> {
    require(value["uri"].is_string(), "diagnostic source URI missing")?;
    require(
        diagnostic_position(&value["range"]["start"])?
            <= diagnostic_position(&value["range"]["end"])?,
        "diagnostic source range reversed",
    )
}
fn failure_diagnostics(result: &Value) -> Result<(), String> {
    let diagnostics = result["diagnostics"]
        .as_array()
        .ok_or("failure diagnostics must be an array")?;
    require(!diagnostics.is_empty(), "missing refusal diagnostics")?;
    for diagnostic in diagnostics {
        require(
            diagnostic.is_object()
                && diagnostic["message"].is_string()
                && diagnostic["severity"]
                    .as_str()
                    .is_some_and(|s| matches!(s, "error" | "warning" | "info" | "hint")),
            "malformed structured diagnostic",
        )?;
        if let Some(code) = diagnostic.get("code") {
            require(code.is_string(), "diagnostic code must be a string")?;
        }
        if let Some(location) = diagnostic.get("location") {
            diagnostic_location(location)?;
        }
        if let Some(related) = diagnostic.get("related") {
            for item in related
                .as_array()
                .ok_or("related diagnostics must be an array")?
            {
                require(
                    item["message"].is_string(),
                    "related diagnostic message missing",
                )?;
                diagnostic_location(&item["location"])?;
            }
        }
    }
    require(
        diagnostics.iter().any(|d| d["severity"] == "error"),
        "refusal requires an error diagnostic",
    )
}
fn admits_ir4(capability: &Value) -> Result<(), String> {
    // The shared IR contract admits both legacy "4" and release "4.0.0".
    require(
        capability["irVersions"]
            .as_array()
            .is_some_and(|versions| versions.iter().any(|v| v == "4" || v == "4.0.0")),
        "operation capability excludes the selected IR version",
    )
}
fn compare(kit: &Kit, record: &Record, previous: &[Record]) -> Result<(), String> {
    let id = record.case_id.as_str();
    if !id.ends_with("silent") && !is_exit(id) {
        let session_start = previous
            .iter()
            .rposition(|r| is_exit(&r.case_id))
            .map_or(0, |i| i + 1);
        let expected_id = previous[session_start..]
            .iter()
            .filter(|r| !r.case_id.ends_with("silent"))
            .count()
            + 1;
        crate::transport::session::validate_mep_response(&record.observed, expected_id as u64)
            .map_err(|e| e.to_string())?;
    }
    match id {
        "initialized-silent"
        | "unknown-notification-silent"
        | "legacy-initialized-silent"
        | "narrow-initialized-silent"
        | "bounded-initialized-silent" => require(
            record.observed == json!({"silent":true}),
            "notification emitted output",
        ),
        "exit" | "legacy-exit" | "narrow-exit" | "bounded-exit" => require(
            record.observed == json!({"exitSuccess":true,"stdoutClosed":true}),
            "unclean exit",
        ),
        "describe" => {
            let result = rpc_result(record)?;
            admits_ir4(&result["capabilities"]["frontend"])?;
            admits_ir4(&result["capabilities"]["backend"])?;
            require(
                result["claimsVersion"] == "0.1.0-draft.2",
                "unsupported static claim version",
            )?;
            require(
                result["protocolVersions"].as_array().is_some_and(|v| {
                    v.contains(&json!("0.2.0-draft.1")) && v.contains(&json!("0.1"))
                }),
                "required rich and legacy protocols are not described",
            )?;
            for key in ["id", "name", "version"] {
                require(
                    result["extension"][key]
                        .as_str()
                        .is_some_and(|s| !s.is_empty()),
                    "description identity is incomplete",
                )?;
            }
            let claimed = &result["capabilities"]["modelTransport"];
            let tuples = claimed["tuples"]
                .as_array()
                .ok_or("static model tuples missing")?;
            for expected in support()["tuples"].as_array().unwrap() {
                require(
                    tuples.iter().filter(|t| *t == expected).count() == 1,
                    "required complete static tuple missing or duplicated",
                )?;
            }
            for (key, needed) in support()["limits"].as_object().unwrap() {
                require(
                    claimed["limits"][key]
                        .as_u64()
                        .is_some_and(|n| n >= needed.as_u64().unwrap() && n <= i32::MAX as u64),
                    "static model limits do not admit the fixed profile",
                )?;
            }
            require(
                result.get("extension").is_some() && result.get("capabilities").is_some(),
                "incomplete extension description",
            )
        }
        "initialize" | "narrow-initialize" | "bounded-initialize" => {
            let result = rpc_result(record)?;
            admits_ir4(&result["capabilities"]["frontend"])?;
            admits_ir4(&result["capabilities"]["backend"])?;
            require(
                result["protocolVersion"] == "0.2.0-draft.1",
                "wrong MEP version",
            )?;
            let description = previous
                .iter()
                .find(|r| r.case_id == "describe")
                .ok_or("static description missing")?;
            require(
                result["extension"] == rpc_result(description)?["extension"],
                "initialized extension identity differs from description",
            )?;
            let selected = &result["capabilities"]["modelTransport"];
            let mut expected = support();
            if id == "narrow-initialize" {
                expected["tuples"] = json!([tuple(COMPILE, false)]);
            }
            if id == "bounded-initialize" {
                expected["limits"] =
                    json!({"maxEncodedBytes":128,"maxDecodedBytes":96,"maxDepth":2,"maxNodes":2});
            }
            require(
                selected == &expected,
                "complete tuples and negotiated bounds differ from fixed offer",
            )?;
            require(
                result
                    .pointer("/capabilities/backend/targets")
                    .and_then(Value::as_array)
                    .is_some_and(|a| a.contains(&json!("moonbit"))),
                "moonbit backend missing",
            )?;
            require(
                result
                    .pointer("/capabilities/frontend/languages")
                    .and_then(Value::as_array)
                    .is_some_and(|a| a.iter().any(|v| v["id"] == "moonbit")),
                "moonbit frontend missing",
            )
        }
        "describe-immutable" => {
            let first = previous.iter().find(|r| r.case_id == "describe").unwrap();
            require(
                rpc_result(record)? == rpc_result(first)?,
                "static description mutated during session",
            )
        }
        "legacy-initialize" => {
            let result = rpc_result(record)?;
            admits_ir4(&result["capabilities"]["backend"])?;
            let description = previous
                .iter()
                .find(|r| r.case_id == "describe")
                .ok_or("static description missing")?;
            require(
                result["extension"] == rpc_result(description)?["extension"],
                "legacy extension identity differs from description",
            )?;
            require(
                result.pointer("/capabilities/backend/generate") == Some(&json!(true))
                    && result
                        .pointer("/capabilities/backend/targets")
                        .and_then(Value::as_array)
                        .is_some_and(|a| a.contains(&json!("moonbit"))),
                "legacy backend capability missing",
            )?;
            require(
                result["protocolVersion"] == "0.1"
                    && result["capabilities"].get("modelTransport").is_none(),
                "legacy negotiation admitted model transport",
            )
        }
        "legacy-model-refused" | "narrow-generate-refused" => expect_error(record, -32013),
        "compile-ion" | "compile-repeat" | "recover-after-source" | "narrow-compile" => {
            let result = rpc_result(record)?;
            require(
                result["success"] == true
                    && result["modules"] == json!(["main"])
                    && result["diagnostics"] == json!([]),
                "compile result is not a clean successful main module",
            )?;
            let model = &result["model"];
            validate_compiled(kit, model)?;
            if id == "compile-repeat" {
                require(
                    model == &compiled(previous)?,
                    "repeated compilation changed immutable model",
                )?;
            }
            Ok(())
        }
        "generate-retained" | "generate-repeat" | "recover-after-digest" => {
            validate_generated(kit, rpc_result(record)?, Some(&compiled(previous)?))
        }
        "unknown-ion-retained" => validate_generated(
            kit,
            rpc_result(record)?,
            Some(&opaque_model(kit, previous)?),
        ),
        "json-model-generate" => {
            validate_generated(kit, rpc_result(record)?, Some(&json_model(kit)))
        }
        "legacy-json-generate" | "legacy-json" => {
            validate_generated(kit, rpc_result(record)?, None)
        }
        "malformed-source" | "lossy-json-refused" => {
            let result = rpc_result(record)?;
            require(
                result["success"] == false && result.get("model").is_none(),
                "failed compilation must forbid model",
            )?;
            failure_diagnostics(result)?;
            if id == "lossy-json-refused" {
                require(
                    result["diagnostics"]
                        .as_array()
                        .unwrap()
                        .iter()
                        .any(|d| d["code"] == "data.lossy_conversion"),
                    "missing lossy conversion diagnostic",
                )?;
            }
            Ok(())
        }
        "unknown-method" => expect_error(record, -32601),
        "after-shutdown" => expect_error(record, -32014),
        "shutdown"
        | "legacy-shutdown"
        | "narrow-shutdown"
        | "bounded-shutdown"
        | "bounded-recovery-ping" => {
            rpc_result(record)?;
            Ok(())
        }
        _ => expect_error(record, -32602),
    }
}
fn require(condition: bool, message: &str) -> Result<(), String> {
    if condition {
        Ok(())
    } else {
        Err(message.into())
    }
}

fn decode_payload(value: &Value) -> Result<Vec<u8>, String> {
    require(value["layout"] == "single-document", "wrong payload layout")?;
    let encoded = value["content"].as_str().ok_or("payload content missing")?;
    require(
        encoded.len() <= 1000000,
        "encoded payload exceeds profile limit",
    )?;
    let bytes = STANDARD
        .decode(encoded)
        .map_err(|_| "invalid payload base64")?;
    require(STANDARD.encode(&bytes) == encoded, "noncanonical base64")?;
    require(
        bytes.len() <= 750000 && value["decodedByteLength"].as_u64() == Some(bytes.len() as u64),
        "payload length mismatch",
    )?;
    require(
        value["sha256"] == sha256_hex(&bytes),
        "payload digest mismatch",
    )?;
    Ok(bytes)
}
fn validate_compiled(kit: &Kit, model: &Value) -> Result<(), String> {
    require(
        model["profile"] == "morphir-model"
            && model["envelopeVersion"] == "0.1.0-draft.1"
            && model["irVersion"] == "4.0.0"
            && model["payload"]["codec"] == "ion-binary",
        "compiled envelope tuple mismatch",
    )?;
    require(
        model["modelId"].as_str().is_some_and(|s| !s.is_empty())
            && model["revision"].as_str().is_some_and(|s| !s.is_empty()),
        "missing logical model identity",
    )?;
    let bytes = decode_payload(&model["payload"])?;
    require(
        bytes.starts_with(&[0xe0, 1, 0, 0xea]),
        "missing Ion 1.0 marker",
    )?;
    let element = binary::read(&bytes)?;
    metadata::validate_model(&kit.document.source, &element)?;
    require(
        element
            .annotations()
            .iter()
            .map(|s| s.text())
            .collect::<Vec<_>>()
            == [Some("morphir_model")],
        "missing morphir_model annotation",
    )?;
    let fields = element.as_struct().ok_or("model must be Ion struct")?;
    for reserved in ["ir", "enrichments", "provenance"] {
        require(
            fields
                .iter()
                .filter(|(k, _)| k.text() == Some(reserved))
                .count()
                == 1,
            "reserved model fields must occur exactly once",
        )?;
    }
    let ir = ion_json(fields.get("ir").unwrap(), 0, &mut 0)?;
    require(
        canonical(&ir) == canonical(&kit.document.expected_ir),
        "source semantic IR differs from fixed source expectations",
    )?;
    require(
        fields
            .get("enrichments")
            .and_then(Element::as_list)
            .is_some_and(|v| !v.is_empty()),
        "source metadata enrichments missing",
    )?;
    require(
        fields
            .get("provenance")
            .and_then(Element::as_list)
            .is_some_and(|v| !v.is_empty()),
        "source provenance missing",
    )?;
    Ok(())
}

fn ion_json(element: &Element, depth: usize, nodes: &mut usize) -> Result<Value, String> {
    *nodes += 1;
    require(
        depth < 128 && *nodes <= 100000,
        "Ion structural limit exceeded",
    )?;
    if let Some(fields) = element.as_struct() {
        let mut map = serde_json::Map::new();
        for (key, value) in fields.iter() {
            let key = key.text().ok_or("unresolved Ion field")?;
            if map
                .insert(key.into(), ion_json(value, depth + 1, nodes)?)
                .is_some()
            {
                return Err("duplicate IR field".into());
            }
        }
        Ok(Value::Object(map))
    } else if let Some(values) = element.as_list() {
        values
            .iter()
            .map(|v| ion_json(v, depth + 1, nodes))
            .collect::<Result<Vec<_>, _>>()
            .map(Value::Array)
    } else if let Some(s) = element.as_string() {
        Ok(json!(s))
    } else if let Some(v) = element.as_bool() {
        Ok(json!(v))
    } else if let Some(v) = element.as_i64() {
        Ok(json!(v))
    } else if element.is_null() {
        Ok(Value::Null)
    } else {
        Err("non-JSON value in semantic IR".into())
    }
}

// Project the documented expanded IR spellings onto the fixed canonical
// semantics. Source metadata remains in its original Ion payload and sidecars.
fn canonical(value: &Value) -> Value {
    match value {
        Value::Array(values) => Value::Array(values.iter().map(canonical).collect()),
        Value::Object(fields) => {
            let mut map = fields
                .iter()
                .filter(|(k, _)| !matches!(k.as_str(), "attributes" | "doc"))
                .map(|(k, v)| (k.clone(), canonical(v)))
                .collect::<serde_json::Map<_, _>>();
            if map.contains_key("access") && (!map.contains_key("value") || map.len() == 2) {
                let access = map.remove("access").unwrap();
                let inner = map.remove("value").unwrap_or(Value::Object(map));
                return json!({access.as_str().unwrap_or("invalid"):inner});
            }
            if map.len() == 1 {
                for name in ["Variable", "Reference"] {
                    if let Some(Value::Object(body)) = map.get(name) {
                        let member = if name == "Variable" { "name" } else { "fqname" };
                        if body.contains_key(member)
                            && body
                                .keys()
                                .all(|k| k == member || k == "typeArgs" || k == "typeParams")
                            && body.get("typeArgs").is_none_or(|v| v == &json!([]))
                            && body.get("typeParams").is_none_or(|v| v == &json!([]))
                        {
                            return if name == "Reference" {
                                body[member].clone()
                            } else {
                                json!({name:body[member]})
                            };
                        }
                    }
                }
                if let Some(Value::Object(body)) = map.get("Literal")
                    && body.len() == 1
                    && let Some(literal) = body.get("literal")
                {
                    return json!({"Literal":literal});
                }
            }
            Value::Object(map)
        }
        _ => value.clone(),
    }
}

fn validate_generated(kit: &Kit, result: &Value, model: Option<&Value>) -> Result<(), String> {
    require(
        result["success"] == true && result["diagnostics"] == json!([]),
        "generation failed or diagnosed",
    )?;
    let artifacts = result["artifacts"].as_array().ok_or("missing artifacts")?;
    let mut by_path = BTreeMap::new();
    for artifact in artifacts {
        let path = artifact["path"].as_str().ok_or("artifact path missing")?;
        require(
            by_path.insert(path, artifact).is_none(),
            "duplicate artifact path",
        )?;
    }
    let mut expected = vec!["library.mbt", "moon.mod", "moon.pkg", "symbols.10n"];
    if let Some(model) = model {
        let name = if model["profile"] == "morphir-model" {
            "mep/source-model.ionb"
        } else {
            "mep/source-model.json"
        };
        expected.extend([name, "mep/source-envelope.json"]);
        let source = by_path.get(name).ok_or("retained source sidecar missing")?;
        require(
            source["binary"] == true && source["content"] == model["payload"]["content"],
            "source bytes were not retained exactly",
        )?;
        let envelope = by_path
            .get("mep/source-envelope.json")
            .ok_or("source envelope sidecar missing")?;
        require(
            envelope.get("binary").is_none_or(|b| b == false),
            "source envelope must be text",
        )?;
        let decoded = crate::json::strict::parse(
            envelope["content"]
                .as_str()
                .ok_or("envelope text missing")?,
        )?;
        require(&decoded == model, "source envelope was changed")?;
    }
    expected.sort_unstable();
    require(
        by_path.keys().copied().collect::<Vec<_>>() == expected,
        "artifact inventory mismatch",
    )?;
    let expected_artifacts = if model.is_some_and(|m| m["profile"] == "morphir-model") {
        &kit.document.expected_artifacts
    } else {
        &kit.document.expected_json_artifacts
    };
    for (name, text) in expected_artifacts {
        let artifact = by_path[name.as_str()];
        let actual = artifact["content"]
            .as_str()
            .ok_or("text artifact content missing")?;
        let content_matches = if name == "library.mbt" {
            let blocks = |source: &str| {
                let mut values = source
                    .split("\n\n")
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(str::to_owned)
                    .collect::<Vec<_>>();
                values.sort();
                values
            };
            blocks(actual) == blocks(text)
        } else {
            actual == text
        };
        require(
            artifact.get("binary").is_none_or(|b| b == false) && content_matches,
            &format!("fixed artifact content differs: {name}"),
        )?;
    }
    let symbols = by_path["symbols.10n"];
    require(symbols["binary"] == true, "symbol metadata must be binary")?;
    let bytes = STANDARD
        .decode(
            symbols["content"]
                .as_str()
                .ok_or("symbol content missing")?,
        )
        .map_err(|e| e.to_string())?;
    require(
        bytes.starts_with(&[0xe0, 1, 0, 0xea]),
        "symbol metadata must be Ion binary",
    )?;
    require(
        STANDARD.encode(&bytes) == symbols["content"].as_str().unwrap(),
        "symbol metadata base64 is not canonical",
    )?;
    let symbols = binary::read(&bytes)?;
    let source_root = if let Some(model) = model.filter(|m| m["profile"] == "morphir-model") {
        Some(binary::read(&decode_payload(&model["payload"])?)?)
    } else {
        None
    };
    metadata::validate_symbols(&kit.document.source, &symbols, source_root.as_ref())?;
    let ir_text = symbols
        .as_struct()
        .and_then(|s| s.get("source_ir_json"))
        .and_then(Element::as_string)
        .ok_or("symbol source IR missing")?;
    let ir = crate::json::strict::parse(ir_text)?;
    let expected_ir = if source_root.is_some() {
        &kit.document.expected_ir
    } else {
        &kit.document.plain_ir
    };
    require(
        canonical(&ir) == canonical(expected_ir),
        "symbol source IR differs from independent semantics",
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn malformed_expanded_ir_cannot_drop_semantic_members() {
        assert_ne!(
            canonical(&json!({"access":"Public","value":{},"extra":false})),
            json!({"Public":{}})
        );
        assert_ne!(
            canonical(&json!({"Literal":{"literal":{"BoolLiteral":true},"extra":false}})),
            json!({"Literal":{"BoolLiteral":true}})
        );
    }
    #[test]
    fn fixed_identity_semantics_reject_constant_body() {
        assert_ne!(
            canonical(&json!({"Variable":{"attributes":{},"name":"flag-value"}})),
            canonical(&json!({"Literal":{"literal":{"BoolLiteral":true}}}))
        );
    }
    #[test]
    fn payload_integrity_checks_exact_canonical_bytes() {
        let valid = payload(b"hello", "morphir-json");
        assert_eq!(decode_payload(&valid).unwrap(), b"hello");
        for (key, bad) in [
            ("content", json!("aGVsbG8")),
            ("decodedByteLength", json!(4)),
            ("sha256", json!("0".repeat(64))),
        ] {
            let mut invalid = valid.clone();
            invalid[key] = bad;
            assert!(decode_payload(&invalid).is_err(), "{key}");
        }
    }
}
