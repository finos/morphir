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
    let mut value = crate::json::strict::parse(text)?;
    version(
        value["formatVersion"]
            .as_str()
            .ok_or("Workbench formatVersion must be a string")?,
    )?;
    let mut literal_inputs = if value["formatVersion"] == super::contract::EXECUTIONS_VERSION {
        value = crate::json::strict::parse_exact(text)?;
        super::executions::validate_corpus_shape(&value)?;
        // Negative traces can contain any literal JSON, including serde-private
        // marker maps. Move them around typed decoding without reinterpreting them.
        Some(
            value["cases"]
                .as_array_mut()
                .expect("schema-checked cases")
                .iter_mut()
                .map(|case| std::mem::replace(&mut case["input"], Value::Null))
                .collect::<Vec<_>>(),
        )
    } else {
        None
    };
    if value["formatVersion"] == super::contract::NATIVE_POLICY_BOUNDARY_VERSION {
        value = crate::json::strict::parse_exact(text)?;
        super::native_policy_boundary::validate_corpus_shape(&value)?;
    }
    if value["formatVersion"] == super::contract::NATIVE_POLICY_CLIENT_VERSION {
        value = crate::json::strict::parse_exact(text)?;
        super::native_policy_client::validate_corpus_shape(&value)?;
    }
    if value["formatVersion"] == super::contract::NATIVE_POLICY_OWNER_VERSION {
        value = crate::json::strict::parse_exact(text)?;
        super::native_policy_owner::validate_corpus_shape(&value)?;
    }
    if value["formatVersion"] == super::contract::CAPABILITY_EXECUTIONS_VERSION {
        value = crate::json::strict::parse_exact(text)?;
        super::capability_executions::validate_corpus_shape(&value)?;
    }
    if value["formatVersion"] == super::contract::CAPABILITY_POLICY_VERSION {
        value = crate::json::strict::parse_exact(text)?;
        super::capability_policy::validate_corpus_shape(&value)?;
    }
    if value["formatVersion"] == super::contract::SELECTED_SCHEME_VERSION {
        value = crate::json::strict::parse_exact(text)?;
        super::selected_scheme::validate_corpus_shape(&value)?;
    }
    if value["formatVersion"] == super::contract::NATIVE_OWNER_VERSION {
        value = crate::json::strict::parse_exact(text)?;
        super::native_owner::validate_corpus_shape(&value)?;
    }
    if value["formatVersion"] == super::contract::NATIVE_CLIENT_VERSION {
        value = crate::json::strict::parse_exact(text)?;
        super::native_client::validate_corpus_shape(&value)?;
    }
    if value["formatVersion"] == super::contract::NATIVE_REPLIES_VERSION {
        value = crate::json::strict::parse_exact(text)?;
        super::native_replies::validate_corpus_shape(&value)?;
    }
    if value["formatVersion"] == super::contract::NATIVE_FRAMES_VERSION {
        // Keep duplicate-aware infrastructure validation above, but retain exact
        // decimal tokens for compact generation counts in this new draft. The
        // historical parser's IEEE-754 normalization remains unchanged for value drafts.
        value = crate::json::strict::parse_exact(text)?;
        // Validate literal token kinds before serde's nested Value visitors can
        // interpret private arbitrary-precision/raw-value marker objects.
        super::native_frames::validate_corpus_shape(&value)?;
    }
    let http_kit = match value["formatVersion"].as_str() {
        Some(super::contract::HTTP_POLICY_BOUNDARY_VERSION) => {
            Some(super::http_policy::Kit::Boundary)
        }
        Some(super::contract::HTTP_POLICY_CLIENT_VERSION) => Some(super::http_policy::Kit::Client),
        Some(super::contract::HTTP_POLICY_PROVIDER_VERSION) => {
            Some(super::http_policy::Kit::Provider)
        }
        _ => None,
    };
    if let Some(kit) = http_kit {
        value = crate::json::strict::parse_exact(text)?;
        kit.corpus(&value)?;
        literal_inputs = Some(
            value["cases"]
                .as_array_mut()
                .expect("schema-checked cases")
                .iter_mut()
                .map(|case| std::mem::replace(&mut case["input"], Value::Null))
                .collect(),
        );
    }
    let mut document: Document = serde_json::from_value(value).map_err(|e| e.to_string())?;
    if let Some(inputs) = literal_inputs {
        for (case, input) in document.cases.iter_mut().zip(inputs) {
            case.input = input;
        }
    }
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
        case.operation().validate_format(case.format)?;
        identity(&case.id, 128)?;
        if !ids.insert(&case.id) {
            return Err(format!("duplicate case id {}", case.id));
        }
        let input_len = if let Some(kit) = http_kit {
            kit.input(&case.input)?;
            encoded_size(&case.input, MAX_INPUT_BYTES)?
        } else if case.operation() == Operation::ValidateNativePolicyBoundary {
            super::native_policy_boundary::validate_input(&case.input)?;
            encoded_size(&case.input, MAX_INPUT_BYTES)?
        } else if case.operation() == Operation::RunNativePolicyClient {
            super::native_policy_client::validate_input(&case.input)?;
            encoded_size(&case.input, MAX_INPUT_BYTES)?
        } else if case.operation() == Operation::RunNativePolicyOwner {
            super::native_policy_owner::validate_input(&case.input)?;
            encoded_size(&case.input, MAX_INPUT_BYTES)?
        } else if case.operation() == Operation::RunCapabilityExecutions {
            super::capability_executions::validate_input(&case.input)?;
            encoded_size(&case.input, MAX_INPUT_BYTES)?
        } else if case.operation() == Operation::RunCapabilityPolicy {
            super::capability_policy::validate_input(&case.input)?;
            encoded_size(&case.input, MAX_INPUT_BYTES)?
        } else if case.operation() == Operation::RunSelectedScheme {
            super::selected_scheme::validate_input(&case.input)?;
            encoded_size(&case.input, MAX_INPUT_BYTES)?
        } else if case.operation() == Operation::RunNativeOwner {
            super::native_owner::validate_input(&case.input)?;
            encoded_size(&case.input, MAX_INPUT_BYTES)?
        } else if case.operation() == Operation::RunNativeClient {
            super::native_client::validate_input(&case.input)?;
            encoded_size(&case.input, MAX_INPUT_BYTES)?
        } else if case.operation() == Operation::ValidateNativeReply {
            super::native_replies::validate_input(&case.input)?;
            encoded_size(&case.input, MAX_INPUT_BYTES)?
        } else if case.operation() == Operation::ValidateNativeFrame {
            super::native_frames::validate_input(&case.input)?;
            encoded_size(&case.input, MAX_INPUT_BYTES)?
        } else if case.operation() == Operation::ReduceExecution {
            // Negative execution traces are arbitrary JSON. The adapter owns admission;
            // the runner only bounds the compact encoded input.
            encoded_size(&case.input, MAX_INPUT_BYTES)?
        } else if case.operation() == Operation::ValidateOutcomes {
            let envelope = case
                .input
                .as_object()
                .ok_or("outcomes input must be an object")?;
            if envelope.len() != 3
                || !["suite", "manifest", "outcomes"]
                    .iter()
                    .all(|key| envelope.contains_key(*key))
            {
                return Err("outcomes input requires exactly suite, manifest and outcomes".into());
            }
            if case.format == Format::IonText && !case.input["outcomes"].is_string() {
                return Err("Ion outcomes must be a string".into());
            }
            encoded_size(&case.input, MAX_INPUT_BYTES)?
        } else if case.operation() == Operation::ValidateInvocations {
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
            .validate_expected_for(case.operation())
            .map_err(|e| format!("case {} expected: {e}", case.id))?;
    }
    Ok(Corpus {
        version: document.format_version,
        cases: document.cases,
        hash: sha256_hex(&bytes),
    })
}
