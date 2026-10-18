//! Offline evidence for production codec round trips and typed comparisons.
//! Input source bytes and values remain opaque: this runner never links a codec,
//! computes a comparison result or derives fixed expected values from an adapter.
use super::contract::{MAX_VALUE_BYTES, OfflineOnly, Operation, encoded_size};
use serde_json::Value;
use std::sync::OnceLock;

pub(super) fn validate_corpus_shape(value: &Value) -> Result<(), String> {
    check("mck-corpus", value)
}
pub(super) fn validate_report_shape(value: &Value) -> Result<(), String> {
    check("mck-report", value)
}
pub(super) fn validate_observation_shape(value: &Value) -> Result<(), String> {
    check("mck-observation", value)
}
pub(super) fn validate_input(value: &Value, operation: Operation) -> Result<(), String> {
    encoded_size(value, 2 * MAX_VALUE_BYTES)?;
    check("mck-input", value)?;
    match operation {
        Operation::TranscodeInvocations if value.get("sourceFormat").is_some() => {
            if value["source"]["hex"]
                .as_str()
                .is_some_and(|hex| hex.len() % 2 != 0)
            {
                return Err("binary source hex requires complete byte pairs".into());
            }
            Ok(())
        }
        Operation::CompareValues if value.get("comparison").is_some() => Ok(()),
        _ => Err("codec/comparison input belongs to another operation".into()),
    }
}
pub(super) fn projection(value: &Value, operation: Operation) -> Result<Value, String> {
    encoded_size(value, MAX_VALUE_BYTES)?;
    check("mck-projection", value)?;
    match operation {
        Operation::TranscodeInvocations if value.get("invocations").is_some() => {
            let mut projected = value.clone();
            projected["invocations"] =
                super::contract::invocation_projection(&value["invocations"])?;
            Ok(projected)
        }
        Operation::CompareValues if value.get("matches").is_some() => {
            if value["matches"] == true && !value["mismatchPath"].is_null()
                || value["matches"] == false && !value["mismatchPath"].is_string()
            {
                return Err("comparison match and mismatch path disagree".into());
            }
            if value["mismatchPath"]
                .as_str()
                .is_some_and(|s| s.encode_utf16().count() > 65536)
            {
                return Err("comparison path exceeds UTF-16 budget".into());
            }
            Ok(value.clone())
        }
        _ => Err("codec/comparison projection belongs to another operation".into()),
    }
}
fn check(name: &str, value: &Value) -> Result<(), String> {
    static VALIDATORS: OnceLock<std::collections::BTreeMap<&str, jsonschema::Validator>> =
        OnceLock::new();
    let validators = VALIDATORS.get_or_init(|| {
        let schemas = [
            include_str!("../../../../spec/workbench/schemas/value.schema.json"),
            include_str!("../../../../spec/workbench/schemas/invocations.schema.json"),
            include_str!("../../../../spec/workbench/draft.26/schemas/mck-input.schema.json"),
            include_str!("../../../../spec/workbench/draft.26/schemas/mck-projection.schema.json"),
            include_str!("../../../../spec/workbench/draft.26/schemas/mck-observation.schema.json"),
            include_str!(
                "../../../../spec/workbench/draft.26/schemas/mck-capabilities.schema.json"
            ),
            include_str!("../../../../spec/workbench/draft.26/schemas/mck-corpus.schema.json"),
            include_str!("../../../../spec/workbench/draft.26/schemas/mck-report.schema.json"),
        ]
        .map(|text| serde_json::from_str::<Value>(text).expect("codec/comparison schema JSON"));
        [
            "mck-input",
            "mck-projection",
            "mck-observation",
            "mck-capabilities",
            "mck-corpus",
            "mck-report",
        ]
        .into_iter()
        .map(|name| {
            let id = format!(
                "https://morphir.finos.org/spec/workbench/0.1.0-draft.26/{name}.schema.json"
            );
            let schema = schemas
                .iter()
                .find(|s| s["$id"] == id)
                .expect("codec/comparison schema");
            let mut options = jsonschema::options();
            options.with_retriever(OfflineOnly);
            for resource in &schemas {
                options.with_resource(
                    resource["$id"].as_str().expect("schema id"),
                    jsonschema::Resource::from_contents(resource.clone()).expect("schema resource"),
                );
            }
            (
                name,
                options.build(schema).expect("codec/comparison validator"),
            )
        })
        .collect()
    });
    validators[name].validate(value).map_err(|e| {
        format!(
            "invalid codec/comparison infrastructure at {}: {e}",
            e.instance_path
        )
    })
}
