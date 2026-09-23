//! Evaluation data shared by native, browser, and future extension hosts.
//!
//! This crate owns neither filesystem access nor provider runtime types. New
//! program representations can extend `Program` when an evaluator supports them.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeSet;

pub mod ir_draft;

pub const CONTRACT_VERSION: u32 = 1;

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ProviderId {
    Rego,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SourceLanguage {
    Rego,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SourceModule {
    pub path: String,
    pub source: String,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum Program {
    Source {
        language: SourceLanguage,
        modules: Vec<SourceModule>,
    },
}

/// A request validated at the serialization boundary. Private fields prevent
/// callers from changing its version, sources, or limits after validation.
#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(try_from = "RequestWire")]
pub struct EvaluationRequest {
    version: u32,
    provider: ProviderId,
    program: Program,
    entrypoints: Vec<String>,
    input: Value,
    timeout_ms: u64,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RequestWire {
    version: u32,
    provider: ProviderId,
    program: Program,
    entrypoints: Vec<String>,
    input: Value,
    timeout_ms: u64,
}

/// Request diagnostics can cross a host boundary without runtime error types.
#[derive(Clone, Debug, Deserialize, Serialize, thiserror::Error)]
#[error("{message}")]
pub struct RequestError {
    pub message: String,
}

impl RequestError {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

fn validate_names<'a>(
    names: impl Iterator<Item = &'a str>,
    label: &str,
) -> Result<(), RequestError> {
    let mut seen = BTreeSet::new();
    for name in names {
        if name.trim().is_empty() {
            return Err(RequestError::new(format!("{label} must not be empty")));
        }
        if !seen.insert(name) {
            return Err(RequestError::new(format!("duplicate {label}: {name}")));
        }
    }
    if seen.is_empty() {
        return Err(RequestError::new(format!(
            "at least one {label} is required"
        )));
    }
    Ok(())
}

impl TryFrom<RequestWire> for EvaluationRequest {
    type Error = RequestError;

    fn try_from(wire: RequestWire) -> Result<Self, Self::Error> {
        if wire.version != CONTRACT_VERSION {
            return Err(RequestError::new(format!(
                "unsupported evaluation request version: {}",
                wire.version
            )));
        }
        if !(1..=300_000).contains(&wire.timeout_ms) {
            return Err(RequestError::new("timeout_ms must be between 1 and 300000"));
        }
        let Program::Source { modules, .. } = &wire.program;
        validate_names(
            modules.iter().map(|module| module.path.as_str()),
            "source path",
        )?;
        validate_names(wire.entrypoints.iter().map(String::as_str), "entrypoint")?;
        Ok(Self {
            version: wire.version,
            provider: wire.provider,
            program: wire.program,
            entrypoints: wire.entrypoints,
            input: wire.input,
            timeout_ms: wire.timeout_ms,
        })
    }
}

impl EvaluationRequest {
    pub fn provider(&self) -> ProviderId {
        self.provider
    }
    pub fn program(&self) -> &Program {
        &self.program
    }
    pub fn entrypoints(&self) -> &[String] {
        &self.entrypoints
    }
    pub fn input(&self) -> &Value {
        &self.input
    }
    /// Cooperative execution budget per entrypoint, in milliseconds.
    /// Hosts enforce any stricter wall-clock or memory limits separately.
    pub fn timeout_ms(&self) -> u64 {
        self.timeout_ms
    }
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum EvaluationOutcome {
    Value { value: Value },
    Undefined,
    Error { message: String },
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct EvaluationResult {
    pub entrypoint: String,
    #[serde(flatten)]
    pub outcome: EvaluationOutcome,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
pub struct EvaluationReport {
    pub version: u32,
    pub provider: ProviderId,
    pub results: Vec<EvaluationResult>,
}

impl EvaluationReport {
    pub fn has_errors(&self) -> bool {
        self.results
            .iter()
            .any(|result| matches!(result.outcome, EvaluationOutcome::Error { .. }))
    }
}

/// Providers evaluate already-loaded programs. Hosts choose a provider and own
/// transport, file access, process supervision, and presentation.
pub trait Evaluator {
    fn provider(&self) -> ProviderId;
    fn evaluate(&self, request: &EvaluationRequest) -> EvaluationReport;
}
