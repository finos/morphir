//! Execute the admitted linked-metadata corpus through the shared bounded adapter transport.
use std::borrow::Cow;
use std::collections::BTreeSet;
use std::sync::OnceLock;

use base64::Engine as _;
use regex::Regex;
use semver::Version;
use serde::Serialize;
use serde_json::{Map, Value, json};

use super::{fixture_path, read};
use crate::kit::hash::sha256_hex;
use crate::kit::snapshot::collect;
use crate::kit::{Kit, KitSource, load_kit};
use crate::transport::protocol::parse_capabilities;

const PROTOCOL_SCHEMA: &str =
    include_str!("../../../../spec/ir/mck/metadata-protocol-draft.schema.json");
const CORPUS: &str = "spec/ir/mck/metadata-contract-draft.json";

pub trait MetadataTestee {
    /// The bounded transport supplies the numeric request id and checks the response id.
    fn exchange(&mut self, request: &Value) -> Result<Map<String, Value>, String>;
}

impl MetadataTestee for crate::transport::Session {
    fn exchange(&mut self, request: &Value) -> Result<Map<String, Value>, String> {
        self.exchange_serializable(request)
            .map_err(|error| error.to_string())
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MetadataRecord {
    pub case_id: String,
    pub operation: String,
    pub targets: Vec<Value>,
    pub result: String,
    pub message: Option<String>,
}

#[derive(Debug, Clone)]
pub struct MetadataRun {
    pub capabilities: Option<Value>,
    pub failure: Option<String>,
    pub records: Vec<MetadataRecord>,
}

fn validator() -> &'static jsonschema::Validator {
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    VALIDATOR.get_or_init(|| {
        let schema = serde_json::from_str(PROTOCOL_SCHEMA).expect("embedded metadata schema JSON");
        jsonschema::options()
            .build(&schema)
            .expect("embedded metadata schema")
    })
}

fn validate(value: &Value) -> Result<(), String> {
    validator()
        .validate(value)
        .map_err(|error| format!("{}: {error}", error.instance_path))
}

fn with_id(body: &Map<String, Value>, id: u64) -> Value {
    let mut value = body.clone();
    value.insert("id".into(), id.into());
    Value::Object(value)
}

fn valid_version(text: &str, ir: bool) -> bool {
    let Ok(version) = Version::parse(text) else {
        return false;
    };
    if version.to_string() != text {
        return false;
    }
    if ir {
        version.major >= 3
            && version.major <= u32::MAX as u64
            && version.minor <= u32::MAX as u64
            && version.patch <= u32::MAX as u64
            && version.pre.is_empty()
            && version.build.is_empty()
    } else {
        !version.pre.is_empty() && version.build.is_empty()
    }
}

fn negotiate(body: Map<String, Value>) -> Result<Value, String> {
    let value = with_id(&body, 1);
    if body.get("contractVersion").is_some_and(Value::is_number) {
        parse_capabilities(&Value::Object(body.clone())).map_err(|error| error.to_string())?;
        return Ok(json!({"kind":"legacy","capabilities":body}));
    }
    validate(&value)?;
    if body.get("suite") != Some(&json!("metadata")) {
        return Err("metadata capabilities required".into());
    }
    let mut claims = BTreeSet::new();
    for claim in body["claims"].as_array().expect("schema checked claims") {
        let revision = claim["irRevision"]
            .as_str()
            .expect("schema checked revision");
        if !valid_version(revision, true) {
            return Err(format!("invalid IR revision {revision}"));
        }
        if let Some(ion) = claim["ionVersion"].as_str()
            && !valid_version(ion, false)
        {
            return Err(format!("invalid Ion version {ion}"));
        }
        let key = serde_json::to_string(claim).expect("claim JSON");
        if !claims.insert(key) {
            return Err("duplicate metadata claim".into());
        }
    }
    Ok(json!({"kind":"metadata","capabilities":body}))
}

fn claimed(negotiation: &Value, case: &Value) -> bool {
    if negotiation["kind"] != "metadata" {
        return false;
    }
    let Some(claims) = negotiation["capabilities"]["claims"].as_array() else {
        return false;
    };
    case["targets"].as_array().is_some_and(|targets| {
        targets.iter().all(|target| {
            claims.iter().any(|claim| {
                claim["operation"] == case["operation"]
                    && ["profile", "layout", "irRevision", "ionVersion"]
                        .iter()
                        .all(|key| claim[*key] == target[*key])
            })
        })
    })
}

pub(super) fn claims_case(capabilities: &Value, case: &Value) -> bool {
    let kind = if capabilities["suite"] == "metadata" {
        "metadata"
    } else {
        "legacy"
    };
    claimed(&json!({"kind":kind,"capabilities":capabilities}), case)
}

pub(super) fn valid_capabilities(capabilities: &Value) -> Result<(), String> {
    let body = capabilities
        .as_object()
        .ok_or("capabilities must be an object")?
        .clone();
    negotiate(body).map(|_| ())
}

fn fixture_refs(value: &Value, paths: &mut BTreeSet<String>) {
    if let Some(relative) = value
        .as_str()
        .filter(|s| s.starts_with("metadata-fixtures/"))
    {
        paths.insert(relative.to_owned());
    }
}

fn local_context_reference(base: &str, reference: &str) -> Result<Option<String>, String> {
    if !reference.ends_with(".jsonld") {
        return Ok(None);
    }
    let candidate = if reference.starts_with("metadata-fixtures/") {
        reference.to_owned()
    } else if reference.starts_with("./") || reference.starts_with("../") {
        format!(
            "{}/{}",
            base.rsplit_once('/').map_or("", |(parent, _)| parent),
            reference
        )
    } else {
        return Ok(None);
    };
    let mut parts = Vec::new();
    for part in candidate.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                parts
                    .pop()
                    .ok_or_else(|| format!("unsafe context import {reference}"))?;
            }
            _ => parts.push(part),
        }
    }
    let normalized = parts.join("/");
    fixture_path(&normalized)?;
    Ok(Some(normalized))
}

fn imported_contexts(base: &str, value: &Value) -> Result<Vec<String>, String> {
    let entries = value["@context"]
        .as_array()
        .map_or_else(|| vec![&value["@context"]], |items| items.iter().collect());
    entries
        .into_iter()
        .filter_map(Value::as_str)
        .map(|reference| local_context_reference(base, reference))
        .collect::<Result<Vec<_>, _>>()
        .map(|paths| paths.into_iter().flatten().collect())
}

fn selected_fixtures(kit: &Kit, case: &Value, closure: &str) -> Result<Vec<Value>, String> {
    let mut paths = BTreeSet::from([closure.to_owned()]);
    let given = &case["given"];
    for field in [
        "acceptedResource",
        "resourceFile",
        "contextFile",
        "providerFile",
        "baseFile",
        "import",
    ] {
        fixture_refs(&given[field], &mut paths);
    }
    for field in ["imports", "context"] {
        if let Some(values) = given[field].as_array() {
            for value in values {
                fixture_refs(value, &mut paths);
            }
        }
    }
    if let Some(fixtures) = given["fixtures"].as_object() {
        for value in fixtures.values() {
            fixture_refs(value, &mut paths);
        }
    }
    let mut scanned = BTreeSet::new();
    let mut result = Vec::new();
    while let Some(relative) = paths.iter().find(|p| !scanned.contains(*p)).cloned() {
        scanned.insert(relative.clone());
        let path = fixture_path(&relative)?;
        // Missing inputs are intentionally absent for negative resource cases.
        let Some(bytes) = kit.source.read(&path).map_err(|error| error.to_string())? else {
            continue;
        };
        if relative.ends_with(".jsonld")
            && let Ok(context) = serde_json::from_slice::<Value>(&bytes)
        {
            paths.extend(imported_contexts(&relative, &context)?);
        }
        result.push(json!({"path":relative,"sha256":sha256_hex(&bytes),
            "contentBase64":base64::engine::general_purpose::STANDARD.encode(&bytes)}));
    }
    if !result.iter().any(|f| f["path"] == closure) {
        return Err("metadata schema closure is missing".into());
    }
    result.sort_by(|a, b| a["path"].as_str().cmp(&b["path"].as_str()));
    Ok(result)
}

fn observation_matches(expected: &Value, observed: &Value) -> Result<(), String> {
    fn canonical_json(value: &Value) -> Value {
        match value {
            Value::Object(object) => Value::Object(
                object
                    .iter()
                    .map(|(key, value)| (key.clone(), canonical_json(value)))
                    .collect::<std::collections::BTreeMap<_, _>>()
                    .into_iter()
                    .collect(),
            ),
            Value::Array(items) => Value::Array(items.iter().map(canonical_json).collect()),
            other => other.clone(),
        }
    }
    let mut expected = expected.clone();
    let mut observed = observed.clone();
    for (value, is_observed) in [(&mut expected, false), (&mut observed, true)] {
        if let Some(facts) = value["facts"].as_array_mut() {
            let mut sorted = facts
                .iter()
                .map(|fact| serde_json::to_string(&canonical_json(fact)).expect("fact JSON"))
                .collect::<Vec<_>>();
            sorted.sort();
            if is_observed && sorted.windows(2).any(|pair| pair[0] == pair[1]) {
                return Err("duplicate observed fact".into());
            }
            *facts = sorted.into_iter().map(Value::String).collect();
        }
    }
    if expected == observed {
        Ok(())
    } else {
        Err("observation differs from literal expected result".into())
    }
}

fn record(case: &Value, result: &str, message: Option<String>) -> MetadataRecord {
    MetadataRecord {
        case_id: case["id"].as_str().unwrap_or_default().to_owned(),
        operation: case["operation"].as_str().unwrap_or_default().to_owned(),
        targets: case["targets"].as_array().cloned().unwrap_or_default(),
        result: result.to_owned(),
        message,
    }
}

pub fn run_kit(kit: &Kit, testee: &mut dyn MetadataTestee, filter: Option<&Regex>) -> MetadataRun {
    let corpus = read(&kit.source, CORPUS)
        .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).map_err(|e| e.to_string()));
    let Ok(corpus) = corpus else {
        return MetadataRun {
            capabilities: None,
            failure: Some(corpus.unwrap_err()),
            records: vec![],
        };
    };
    let cases = corpus["cases"].as_array().map(|all| {
        all.iter()
            .filter(|case| {
                filter.is_none_or(|f| f.is_match(case["id"].as_str().unwrap_or_default()))
            })
            .collect::<Vec<_>>()
    });
    let preflight = if kit.errors.is_empty() {
        collect(kit).map_err(|e| e.to_string())
    } else {
        Err(kit
            .errors
            .iter()
            .map(|e| format!("{}:{}: {}", e.file, e.line, e.message))
            .collect::<Vec<_>>()
            .join("; "))
    };
    let snapshot = match preflight {
        Ok(snapshot) => snapshot,
        Err(message) => {
            return MetadataRun {
                capabilities: None,
                failure: Some(message.clone()),
                records: cases
                    .as_deref()
                    .unwrap_or_default()
                    .iter()
                    .map(|case| record(case, "kit-error", Some(message.clone())))
                    .collect(),
            };
        }
    };
    let Some(cases) = cases else {
        return MetadataRun {
            capabilities: None,
            failure: Some("invalid metadata corpus: cases must be an array".into()),
            records: vec![],
        };
    };
    let files = snapshot
        .files
        .into_iter()
        .map(|(path, bytes)| (path, Cow::Owned(bytes)))
        .collect();
    let frozen =
        load_kit(KitSource::map("metadata run snapshot", files)).expect("snapshot map loads");
    if !frozen.errors.is_empty()
        || read(&frozen.source, CORPUS)
            .ok()
            .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
            != Some(corpus.clone())
    {
        let message = "metadata kit changed between admission and snapshot".to_owned();
        return MetadataRun {
            capabilities: None,
            failure: Some(message.clone()),
            records: cases
                .iter()
                .map(|case| record(case, "kit-error", Some(message.clone())))
                .collect(),
        };
    }
    let negotiation = testee
        .exchange(&json!({"op":"capabilities"}))
        .and_then(negotiate);
    let Ok(negotiation) = negotiation else {
        let message = negotiation.unwrap_err();
        return MetadataRun {
            capabilities: None,
            failure: Some(message.clone()),
            records: cases
                .iter()
                .map(|case| record(case, "kit-error", Some(message.clone())))
                .collect(),
        };
    };
    let mut records = Vec::new();
    let mut failure: Option<String> = None;
    let mut next_id = 2_u64;
    for case in cases {
        if let Some(message) = &failure {
            records.push(record(case, "kit-error", Some(message.clone())));
            continue;
        }
        if !claimed(&negotiation, case) {
            records.push(record(
                case,
                "skipped",
                Some("unsupported metadata target tuple".into()),
            ));
            continue;
        }
        let closure = corpus["schemaClosure"].as_str().expect("admitted closure");
        let request = selected_fixtures(&frozen, case, closure).map(|fixtures| {
            json!({
                "op":"run", "caseId":case["id"], "operation":case["operation"],
                "targets":case["targets"], "given":case["given"], "schemaClosure":closure,
                "fixtures":fixtures,
            })
        });
        let outcome = request.and_then(|request| {
            let mut wire = request.clone();
            wire["id"] = json!(next_id);
            validate(&wire)?;
            let body = testee.exchange(&request)?;
            next_id += 1;
            let response = with_id(&body, next_id - 1);
            validate(&response)?;
            match body.get("ok").and_then(Value::as_bool) {
                Some(false) => Err(format!(
                    "adapter exchange error: {}",
                    body.get("error")
                        .and_then(|error| error.get("code"))
                        .and_then(Value::as_str)
                        .ok_or("run failure response missing error code")?
                )),
                Some(true) => observation_matches(
                    &case["expected"],
                    body.get("observation")
                        .ok_or("run success response missing observation")?,
                ),
                None => Err("adapter exchange error: run response required".into()),
            }
        });
        match outcome {
            Ok(()) => records.push(record(case, "pass", None)),
            Err(message)
                if message == "observation differs from literal expected result"
                    || message == "duplicate observed fact" =>
            {
                records.push(record(case, "fail", Some(message)))
            }
            Err(message) => {
                failure = Some(message.clone());
                records.push(record(case, "kit-error", Some(message)));
            }
        }
    }
    MetadataRun {
        capabilities: Some(negotiation),
        failure,
        records,
    }
}
