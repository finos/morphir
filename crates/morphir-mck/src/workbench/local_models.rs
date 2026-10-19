//! Independent local-model evidence. Model bytes are opaque to this checker.
//! A production adapter owns model decoding/migration; the kit owns expected IR.
use super::contract::{OfflineOnly, Operation, encoded_size};
use crate::kit::hash::sha256_hex;
use serde_json::Value;
use std::sync::OnceLock;

pub(super) const MAX_INPUT_BYTES: usize = 3 * 1024 * 1024;
const MAX_SOURCE_BYTES: usize = 1024 * 1024;

fn bytes(hex: &str, limit: usize) -> Result<Vec<u8>, String> {
    if !hex.len().is_multiple_of(2) || hex.len() / 2 > limit {
        return Err("model byte evidence exceeds its bound or has incomplete pairs".into());
    }
    hex.as_bytes()
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| {
            let token = std::str::from_utf8(pair).map_err(|e| e.to_string())?;
            u8::from_str_radix(token, 16).map_err(|e| e.to_string())
        })
        .collect()
}

pub(super) fn validate_corpus_shape(value: &Value) -> Result<(), String> {
    check("corpus", value)
}
pub(super) fn validate_report_shape(value: &Value) -> Result<(), String> {
    check("report", value)
}
pub(super) fn validate_observation_shape(value: &Value) -> Result<(), String> {
    check("observation", value)
}

pub(super) fn validate_input(value: &Value) -> Result<(), String> {
    encoded_size(value, MAX_INPUT_BYTES)?;
    check("input", value)?;
    // One byte over the production boundary is allowed as a negative input.
    bytes(
        value["source"]["hex"].as_str().expect("schema hex"),
        MAX_SOURCE_BYTES + 1,
    )?;
    Ok(())
}

pub(super) fn projection(value: &Value, operation: Operation) -> Result<Value, String> {
    encoded_size(value, MAX_INPUT_BYTES)?;
    check("projection", value)?;
    let mut projected = value.clone();
    match operation {
        Operation::InspectModel if value.get("normalizedIr").is_some() => {
            let version = value["irVersion"].as_str().expect("schema version");
            let parsed = semver::Version::parse(version).map_err(|e| e.to_string())?;
            if parsed.to_string() != version || !parsed.pre.is_empty() || !parsed.build.is_empty() {
                return Err("model semantic version must be canonical release SemVer".into());
            }
            let normalized = crate::json::strict::parse_exact(
                value["normalizedIr"].as_str().expect("schema IR"),
            )?;
            if !normalized.is_object() {
                return Err("normalized IR evidence must be a JSON mapping".into());
            }
            // Generic strict JSON comparison only; never interpret or migrate IR.
            projected["normalizedIr"] = normalized;
        }
        Operation::ExportModelOriginal if value["kind"] == "original" => {
            let content = bytes(value["hex"].as_str().expect("schema hex"), MAX_SOURCE_BYTES)?;
            if value["byteLength"].as_u64() != Some(content.len() as u64)
                || value["sha256"] != sha256_hex(&content)
            {
                return Err("original byte length or digest differs".into());
            }
        }
        _ => return Err("model projection belongs to another operation".into()),
    }
    Ok(projected)
}

pub(super) fn validate_for_input(
    input: &Value,
    value: &Value,
    operation: Operation,
) -> Result<(), String> {
    if value["providerId"] != input["providerId"] {
        return Err("model evidence provider differs from captured input".into());
    }
    let format = if operation == Operation::InspectModel {
        &value["inputFormat"]
    } else {
        &value["format"]
    };
    if format != &input["format"] {
        return Err("model evidence format differs from captured input".into());
    }
    if operation == Operation::ExportModelOriginal && value["hex"] != input["source"]["hex"] {
        return Err("original export differs from captured source bytes".into());
    }
    Ok(())
}

fn check(name: &str, value: &Value) -> Result<(), String> {
    static VALIDATORS: OnceLock<std::collections::BTreeMap<&str, jsonschema::Validator>> =
        OnceLock::new();
    let validators = VALIDATORS.get_or_init(|| {
        let schemas = [
            (
                "input",
                include_str!("../../../../spec/workbench/draft.29/schemas/mck-input.schema.json"),
            ),
            (
                "projection",
                include_str!(
                    "../../../../spec/workbench/draft.29/schemas/mck-projection.schema.json"
                ),
            ),
            (
                "observation",
                include_str!(
                    "../../../../spec/workbench/draft.29/schemas/mck-observation.schema.json"
                ),
            ),
            (
                "capabilities",
                include_str!(
                    "../../../../spec/workbench/draft.29/schemas/mck-capabilities.schema.json"
                ),
            ),
            (
                "corpus",
                include_str!("../../../../spec/workbench/draft.29/schemas/mck-corpus.schema.json"),
            ),
            (
                "report",
                include_str!("../../../../spec/workbench/draft.29/schemas/mck-report.schema.json"),
            ),
        ]
        .map(|(name, text)| {
            (
                name,
                serde_json::from_str::<Value>(text).expect("fixed schema"),
            )
        });
        schemas
            .iter()
            .map(|(name, schema)| {
                let mut options = jsonschema::options();
                options
                    .with_draft(jsonschema::Draft::Draft202012)
                    .with_retriever(OfflineOnly);
                for (_, resource) in &schemas {
                    options.with_resource(
                        resource["$id"].as_str().expect("schema id"),
                        jsonschema::Resource::from_contents(resource.clone())
                            .expect("schema resource"),
                    );
                }
                (
                    *name,
                    options.build(schema).expect("fixed local model schema"),
                )
            })
            .collect()
    });
    validators[name]
        .validate(value)
        .map_err(|e| format!("local model {name}: {e}"))
}

#[cfg(test)]
mod tests {
    use super::super::{Testee, check_report, execute, load};
    use serde_json::{Value, json};
    struct Fixed(std::collections::VecDeque<Value>);
    impl Testee for Fixed {
        fn exchange(&mut self, request: &Value) -> Result<Value, String> {
            assert!(request.get("expected").is_none() && request.get("caseId").is_none());
            if request["op"] == "capabilities" {
                Ok(
                    json!({"suite":"workbench","contractVersion":"0.1.0-draft.29","binding":"checker-infrastructure-only","language":"rust-test","operations":["inspect-model","export-model-original"],"formats":["json"]}),
                )
            } else {
                self.0.pop_front().ok_or("missing authored control".into())
            }
        }
    }
    #[test]
    fn fixed_model_observations_pass_existing_run_and_report_paths() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../spec/workbench/mck/draft.29");
        let corpus = load(&root).unwrap();
        let mut adapter = Fixed(
            corpus
                .cases
                .iter()
                .map(|case| serde_json::to_value(&case.expected).unwrap())
                .collect(),
        );
        let report = execute(&corpus, &mut adapter);
        assert!(report.qualified);
        assert!(adapter.0.is_empty());
        check_report(&root, &report).unwrap();
    }
}
