use std::collections::BTreeSet;
use std::io::Read;
use std::path::Path;

use serde::Deserialize;
use serde_json::Value;

use super::contract::{Format, Observation, identity, version};
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
    pub format: Format,
    pub input: Value,
    pub expected: Observation,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Document {
    format_version: String,
    cases: Vec<Case>,
}

#[derive(Debug, Clone)]
pub struct Corpus {
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
        identity(&case.id, 128)?;
        if !ids.insert(&case.id) {
            return Err(format!("duplicate case id {}", case.id));
        }
        let input_len = match case.format {
            Format::Json => serde_json::to_vec(&case.input)
                .map_err(|e| e.to_string())?
                .len(),
            Format::IonText => case
                .input
                .as_str()
                .ok_or("Ion text input must be a string")?
                .len(),
        };
        if input_len > MAX_INPUT_BYTES {
            return Err(format!("case {} input exceeds 1 MiB", case.id));
        }
        case.expected
            .validate()
            .map_err(|e| format!("case {} expected: {e}", case.id))?;
    }
    Ok(Corpus {
        cases: document.cases,
        hash: sha256_hex(&bytes),
    })
}
