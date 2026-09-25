//! Offline schema gates, separate from any implementation's IR codec.
mod catalog;
mod fences;
mod protocol;

use crate::kit::Kit;
use catalog::{Catalog, EXAMPLES, Schema, read_json};
use std::fmt;

/// Whether `node` names a node kind the schema catalog knows. The `.feature`
/// lowering refuses a `@node:` tag whose kind is not one of these.
pub fn is_node_kind(node: &str) -> bool {
    catalog::node_target(node).is_some()
}

#[derive(Debug)]
pub struct SchemaError(pub String);
impl fmt::Display for SchemaError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for SchemaError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FenceOutcome {
    Accepted,
    RejectedAsExpected,
    Failed(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FenceResult {
    pub case_id: String,
    pub index: usize,
    pub file: String,
    pub line: usize,
    pub outcome: FenceOutcome,
}

#[derive(Debug)]
pub struct SchemaReport {
    pub schema_count: usize,
    pub example_count: usize,
    pub protocol_count: usize,
    pub fences: Vec<FenceResult>,
    pub errors: Vec<String>,
}

impl SchemaReport {
    pub fn is_success(&self) -> bool {
        self.errors.is_empty()
            && self
                .fences
                .iter()
                .all(|r| !matches!(r.outcome, FenceOutcome::Failed(_)))
    }
    pub fn accepted_fences(&self) -> usize {
        self.fences
            .iter()
            .filter(|r| r.outcome == FenceOutcome::Accepted)
            .count()
    }
    pub fn rejected_fences(&self) -> usize {
        self.fences
            .iter()
            .filter(|r| r.outcome == FenceOutcome::RejectedAsExpected)
            .count()
    }
}

impl fmt::Display for SchemaReport {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        for record in &self.fences {
            write!(f, "{} fence-{}: ", record.case_id, record.index)?;
            match &record.outcome {
                FenceOutcome::Accepted => writeln!(f, "ok")?,
                FenceOutcome::RejectedAsExpected => writeln!(f, "ok (rejected as expected)")?,
                FenceOutcome::Failed(message) => {
                    writeln!(f, "FAIL {message} ({}:{})", record.file, record.line)?
                }
            }
        }
        for error in &self.errors {
            writeln!(f, "FAIL {error}")?;
        }
        let failed = self.fences.len() - self.accepted_fences() - self.rejected_fences();
        writeln!(
            f,
            "\n{} ok, {} rejected as expected, {failed} failed, 0 skipped",
            self.accepted_fences(),
            self.rejected_fences()
        )?;
        writeln!(
            f,
            "{} schemas, {} examples, {} protocol messages checked; {} schema or sequence errors",
            self.schema_count,
            self.example_count,
            self.protocol_count,
            self.errors.len()
        )
    }
}

pub fn check(kit: &Kit) -> Result<SchemaReport, SchemaError> {
    if !kit.errors.is_empty() {
        return Err(SchemaError(
            kit.errors
                .iter()
                .map(|e| format!("{}:{}: {}", e.file, e.line, e.message))
                .collect::<Vec<_>>()
                .join("\n"),
        ));
    }
    let mut catalog = Catalog::load(&kit.source)?;
    let mut errors = Vec::new();
    for &(schema, path) in EXAMPLES {
        let value = read_json(&kit.source, path)?;
        if let Err(error) = catalog.validator(schema, "")?.validate(&value) {
            errors.push(format!("{path}: {error} at {}", error.instance_path));
        }
    }
    let example = read_json(&kit.source, "spec/ir/mck/protocol.example.json")?;
    let protocol_count = protocol::check(&mut catalog, &example, &mut errors)?;
    let fences = fences::check(&mut catalog, kit)?;
    Ok(SchemaReport {
        schema_count: Schema::ALL.len(),
        example_count: EXAMPLES.len(),
        protocol_count,
        fences,
        errors,
    })
}
