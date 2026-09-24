//! Fixed V3/V4 node-address cases executed through a versioned adapter suite.
//! The runner treats IR bytes as opaque and never links an implementation codec.

use crate::transport::{Limits, Session};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};
use std::collections::HashSet;
use std::ffi::OsString;
use std::path::{Component, Path};

pub const CONTRACT: &str = "0.1.0-draft.1";

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Corpus {
    contract_version: String,
    cases: Vec<WireCase>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct WireCase {
    id: String,
    input: String,
    uri: String,
    expected: Expected,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Expected {
    outcome: String,
    kind: Option<String>,
    node: Option<Value>,
}

pub struct Case {
    id: String,
    input: String,
    uri: String,
    expected: Expected,
}

pub struct Kit {
    pub cases: Vec<Case>,
}

pub fn load_kit(path: &Path) -> Result<Kit, String> {
    let text =
        std::fs::read_to_string(path).map_err(|error| format!("{}: {error}", path.display()))?;
    let corpus: Corpus =
        serde_json::from_str(&text).map_err(|error| format!("{}: {error}", path.display()))?;
    if corpus.contract_version != CONTRACT || corpus.cases.is_empty() {
        return Err(format!(
            "node-address corpus must use {CONTRACT} and contain cases"
        ));
    }
    let root = path.parent().unwrap_or_else(|| Path::new("."));
    let mut ids = HashSet::new();
    let mut cases = Vec::with_capacity(corpus.cases.len());
    for case in corpus.cases {
        if case.id.is_empty() || !ids.insert(case.id.clone()) {
            return Err(format!(
                "duplicate or empty node-address case id {:?}",
                case.id
            ));
        }
        let relative = Path::new(&case.input);
        if relative.as_os_str().is_empty()
            || relative
                .components()
                .any(|part| !matches!(part, Component::Normal(_)))
        {
            return Err(format!(
                "case {} input must be a confined relative path",
                case.id
            ));
        }
        if !matches!(
            case.expected.outcome.as_str(),
            "resolved"
                | "invalid_node_uri"
                | "invalid_artifact"
                | "artifact_mismatch"
                | "ambiguous_artifact"
                | "revision_unavailable"
                | "revision_mismatch"
                | "format_version_mismatch"
                | "stale_target"
                | "ambiguous_target"
        ) {
            return Err(format!("case {} has unknown outcome", case.id));
        }
        if (case.expected.outcome == "resolved") != case.expected.kind.is_some()
            || (case.expected.outcome == "resolved") != case.expected.node.is_some()
        {
            return Err(format!(
                "case {} needs kind and semantic node exactly when resolved",
                case.id
            ));
        }
        let input_path = root.join(relative);
        let input = std::fs::read_to_string(&input_path)
            .map_err(|error| format!("{}: {error}", input_path.display()))?;
        cases.push(Case {
            id: case.id,
            input,
            uri: case.uri,
            expected: case.expected,
        });
    }
    Ok(Kit { cases })
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ResultKind {
    Pass,
    Fail,
    Error,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Record {
    pub case_id: String,
    pub result: ResultKind,
    pub message: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Report {
    pub contract_version: &'static str,
    pub records: Vec<Record>,
    pub error: Option<String>,
}

impl Report {
    pub fn passed(&self) -> bool {
        self.error.is_none()
            && self
                .records
                .iter()
                .all(|record| matches!(record.result, ResultKind::Pass))
            && !self.records.is_empty()
    }
}

trait Exchange {
    fn exchange(&mut self, request: &Value) -> Result<Map<String, Value>, String>;
}

impl Exchange for Session {
    fn exchange(&mut self, request: &Value) -> Result<Map<String, Value>, String> {
        self.exchange_serializable(request)
            .map_err(|error| error.to_string())
    }
}

fn run_with(kit: &Kit, testee: &mut impl Exchange) -> Report {
    let mut report = Report {
        contract_version: CONTRACT,
        records: Vec::new(),
        error: None,
    };
    let capabilities = testee.exchange(&json!({"op":"capabilities"}));
    match capabilities.and_then(validate_capabilities) {
        Ok(()) => {}
        Err(error) => {
            report.error = Some(error);
            return report;
        }
    }
    for case in &kit.cases {
        let response = testee.exchange(&json!({"op":"resolve","input":case.input,"uri":case.uri}));
        let result = response.and_then(|body| compare(case, &body));
        report.records.push(match result {
            Ok(()) => Record {
                case_id: case.id.clone(),
                result: ResultKind::Pass,
                message: None,
            },
            Err(message) => Record {
                case_id: case.id.clone(),
                result: ResultKind::Fail,
                message: Some(message),
            },
        });
    }
    report
}

fn validate_capabilities(body: Map<String, Value>) -> Result<(), String> {
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase", deny_unknown_fields)]
    struct Capabilities {
        suite: String,
        contract_version: String,
        implementation: String,
        implementation_version: String,
        operations: Vec<String>,
    }
    let caps: Capabilities =
        serde_json::from_value(Value::Object(body)).map_err(|error| error.to_string())?;
    if caps.suite != "node-address"
        || caps.contract_version != CONTRACT
        || caps.implementation.is_empty()
        || caps.implementation_version.is_empty()
        || caps.operations != ["resolve"]
    {
        return Err("adapter lacks node-address draft resolve capability".into());
    }
    Ok(())
}

fn compare(case: &Case, body: &Map<String, Value>) -> Result<(), String> {
    let outcome = body
        .get("outcome")
        .and_then(Value::as_str)
        .ok_or("response outcome is missing")?;
    let ok = body
        .get("ok")
        .and_then(Value::as_bool)
        .ok_or("response ok is missing")?;
    if outcome == "resolved" {
        if !ok
            || body.len() != 5
            || body.get("kind").and_then(Value::as_str).is_none()
            || body.get("canonicalUri").and_then(Value::as_str) != Some(case.uri.as_str())
            || !body.contains_key("node")
        {
            return Err("malformed resolved response".into());
        }
    } else if ok || body.len() != 2 {
        return Err("malformed failure response".into());
    }
    if outcome != case.expected.outcome
        || (outcome == "resolved"
            && (body.get("kind").and_then(Value::as_str) != case.expected.kind.as_deref()
                || body.get("node") != case.expected.node.as_ref()))
    {
        return Err(format!(
            "expected {:?}/{:?} with fixed semantic node, got {outcome}/{:?} with {:?}",
            case.expected.outcome,
            case.expected.kind,
            body.get("kind"),
            body.get("node")
        ));
    }
    Ok(())
}

pub fn run_process(kit: &Kit, program: &OsString, args: &[OsString], limits: Limits) -> Report {
    let mut session = match Session::spawn(program, args, limits) {
        Ok(session) => session,
        Err(error) => {
            return Report {
                contract_version: CONTRACT,
                records: Vec::new(),
                error: Some(error.to_string()),
            };
        }
    };
    let mut report = run_with(kit, &mut session);
    if let Err(error) = session.close() {
        report.error = Some(error.to_string());
    }
    report
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn checked_in_corpus_has_distinct_fixed_cases() {
        let path =
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/ir/mck/node-address-draft.json");
        let kit = load_kit(&path).unwrap();
        assert!(kit.cases.len() >= 9);
        assert!(
            kit.cases
                .iter()
                .any(|case| case.expected.outcome == "resolved")
        );
        assert!(
            kit.cases
                .iter()
                .any(|case| case.expected.outcome == "stale_target")
        );
    }

    #[test]
    fn draft_protocol_schema_accepts_only_closed_wire_shapes() {
        let schema: Value = serde_json::from_str(include_str!(
            "../../../spec/ir/mck/node-address-protocol.schema.json"
        ))
        .unwrap();
        let validator = jsonschema::validator_for(&schema).unwrap();
        assert!(validator.is_valid(&json!({"id":1,"op":"resolve","input":"{}","uri":"morphir://ir/pkg/a?format=4.0.0#/distribution"})));
        assert!(validator.is_valid(&json!({"id":2,"ok":false,"outcome":"stale_target"})));
        assert!(
            !validator
                .is_valid(&json!({"id":1,"op":"resolve","input":"{}","uri":"x","unexpected":true}))
        );
        assert!(!validator.is_valid(&json!({"id":2,"ok":false,"outcome":"resolved"})));
    }

    #[test]
    fn resolved_case_rejects_wrong_semantic_node() {
        let case = Case {
            id: "semantic-node".into(),
            input: String::new(),
            uri: "morphir://ir/pkg/example/v4-test?format=4.0.0#/module/domain/type/user-id".into(),
            expected: Expected {
                outcome: "resolved".into(),
                kind: Some("TypeDefinition".into()),
                node: Some(
                    json!({"TypeAliasDefinition":{"typeParams":[],"typeExp":{"Reference":{"fqname":"morphir/SDK:string#string"}}}}),
                ),
            },
        };
        let body = json!({"ok":true,"outcome":"resolved","kind":"TypeDefinition","canonicalUri":case.uri,"node":null});
        assert!(compare(&case, body.as_object().unwrap()).is_err());
    }
}
