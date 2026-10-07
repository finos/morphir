use std::collections::BTreeSet;
use std::io::Read;
use std::path::Path;

use serde::Deserialize;
use serde_json::Value;

use super::contract::{Format, Observation, Operation, VERSION, encoded_size, identity, version};
use crate::kit::hash::sha256_hex;

const MAX_CORPUS_BYTES: u64 = 16 * 1024 * 1024;
const MAX_INPUT_BYTES: usize = 1024 * 1024;
const MAX_CASES: usize = 1024;

pub(super) fn read_bounded(reader: impl Read, limit: usize) -> Result<Vec<u8>, String> {
    let mut bytes = Vec::new();
    reader
        .take(limit as u64 + 1)
        .read_to_end(&mut bytes)
        .map_err(|e| e.to_string())?;
    if bytes.len() > limit {
        return Err("cases.json exceeds its byte budget".into());
    }
    Ok(bytes)
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Case {
    pub id: String,
    #[serde(default, deserialize_with = "super::contract::present_operation")]
    pub operation: Option<Operation>,
    pub format: Format,
    pub input: Value,
    pub expected: Observation,
}

impl Case {
    pub(super) fn operation(&self) -> Operation {
        self.operation.unwrap_or(Operation::DecodeValue)
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Document {
    format_version: String,
    cases: Vec<Case>,
}

#[derive(Debug, Clone)]
pub struct Corpus {
    pub(super) version: String,
    pub(super) cases: Vec<Case>,
    pub(super) hash: String,
}

impl Corpus {
    pub fn case_count(&self) -> usize {
        self.cases.len()
    }
    pub fn corpus_hash(&self) -> &str {
        &self.hash
    }
}

/// Admit a frozen corpus before starting an adapter. All bytes and expected
/// projections are parent-owned; inputs are not interpreted by this loader.
pub fn load(root: &Path) -> Result<Corpus, String> {
    let path = root.join("cases.json");
    let metadata = std::fs::symlink_metadata(&path).map_err(|e| e.to_string())?;
    if !metadata.is_file() || metadata.len() > MAX_CORPUS_BYTES {
        return Err("cases.json must be a regular file no larger than 16 MiB".into());
    }
    let file = std::fs::File::open(&path).map_err(|e| e.to_string())?;
    if !file.metadata().map_err(|e| e.to_string())?.is_file() {
        return Err("cases.json must be a regular file".into());
    }
    let bytes = read_bounded(file, MAX_CORPUS_BYTES as usize)?;
    let text = std::str::from_utf8(&bytes).map_err(|e| e.to_string())?;
    let value = crate::json::strict::parse(text)?;
    let document: Document = serde_json::from_value(value).map_err(|e| e.to_string())?;
    version(&document.format_version)?;
    if document.cases.is_empty() || document.cases.len() > MAX_CASES {
        return Err("corpus must contain 1 to 1024 cases".into());
    }
    let mut ids = BTreeSet::new();
    for case in &document.cases {
        if (document.format_version == VERSION) != case.operation.is_none() {
            return Err(
                "case operation must be absent in draft.1 and present in later drafts".into(),
            );
        }
        case.operation()
            .validate_version(&document.format_version)?;
        identity(&case.id, 128)?;
        if !ids.insert(&case.id) {
            return Err(format!("duplicate case id {}", case.id));
        }
        let input_len = if case.operation() == Operation::ValidateInvocations {
            let envelope = case
                .input
                .as_object()
                .ok_or("invocation input must be an object")?;
            if envelope.len() != 2
                || !["suite", "manifest"]
                    .iter()
                    .all(|key| envelope.contains_key(*key))
            {
                return Err("invocation input requires exactly suite and manifest".into());
            }
            if case.format == Format::IonText && !case.input["suite"].is_string() {
                return Err("Ion invocation suite must be a string".into());
            }
            encoded_size(&case.input, MAX_INPUT_BYTES)?
        } else if matches!(
            case.operation(),
            Operation::ValidateValue | Operation::ValidateOutput
        ) {
            let envelope = case
                .input
                .as_object()
                .ok_or("admission input must be an object")?;
            if envelope.len() != 3
                || !["value", "type", "definitions"]
                    .iter()
                    .all(|key| envelope.contains_key(*key))
            {
                return Err("admission input requires exactly value, type and definitions".into());
            }
            if case.format == Format::IonText && !case.input["value"].is_string() {
                return Err("Ion admission value must be a string".into());
            }
            serde_json::to_vec(&case.input)
                .map_err(|e| e.to_string())?
                .len()
        } else {
            match case.format {
                Format::Json => serde_json::to_vec(&case.input)
                    .map_err(|e| e.to_string())?
                    .len(),
                Format::IonText => {
                    let text = case
                        .input
                        .as_str()
                        .ok_or("Ion text input must be a string")?;
                    if document.format_version == VERSION {
                        text.len()
                    } else {
                        encoded_size(&case.input, MAX_INPUT_BYTES)?
                    }
                }
            }
        };
        if input_len > MAX_INPUT_BYTES {
            return Err(format!("case {} input exceeds 1 MiB", case.id));
        }
        case.expected
            .validate_for(case.operation())
            .map_err(|e| format!("case {} expected: {e}", case.id))?;
    }
    Ok(Corpus {
        version: document.format_version,
        cases: document.cases,
        hash: sha256_hex(&bytes),
    })
}
