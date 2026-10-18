//! Captured-call and fixture infrastructure only. Native reply bytes stay opaque;
//! the implementation adapter owns response decoding and authority correlation.

use serde_json::Value;
use std::sync::OnceLock;

pub(super) const INVALID_CODES: [&str; 6] = [
    "native.reply.limit",
    "native.reply.utf8",
    "native.reply.json",
    "native.reply.shape",
    "native.reply.operation",
    "native.reply.authority",
];

fn schema_validator(schema: &str) -> jsonschema::Validator {
    let mut options = jsonschema::options();
    options.with_retriever(super::contract::OfflineOnly);
    for text in [
        include_str!("../../../../spec/workbench/draft.16/schemas/mck-input.schema.json"),
        include_str!(
            "../../../../spec/workbench/draft.16/schemas/native-reply-projection.schema.json"
        ),
        include_str!("../../../../spec/workbench/draft.16/schemas/mck-observation.schema.json"),
        include_str!("../../../../spec/workbench/draft.16/schemas/mck-capabilities.schema.json"),
    ] {
        let value: Value = serde_json::from_str(text).expect("native reply MCK schema JSON");
        options.with_resource(
            value["$id"].as_str().expect("native reply MCK schema id"),
            jsonschema::Resource::from_contents(value.clone()).expect("schema resource"),
        );
    }
    let value: Value = serde_json::from_str(schema).expect("native reply MCK schema JSON");
    options.build(&value).expect("native reply MCK schema")
}

pub(super) fn validate_corpus_shape(value: &Value) -> Result<(), String> {
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    VALIDATOR
        .get_or_init(|| {
            schema_validator(include_str!(
                "../../../../spec/workbench/draft.16/schemas/mck-corpus.schema.json"
            ))
        })
        .validate(value)
        .map_err(|e| format!("invalid native reply corpus at {}: {e}", e.instance_path))
}

pub(super) fn validate_input(value: &Value) -> Result<(), String> {
    let mut fixture = value
        .as_object()
        .ok_or("native reply input must be an object")?
        .clone();
    fixture.remove("expectedOperation");
    fixture.remove("expectedSession");
    super::native_frames::validate_input(&Value::Object(fixture))
}

pub(super) fn projection(value: &Value) -> Result<Value, String> {
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    VALIDATOR
        .get_or_init(|| {
            schema_validator(include_str!(
                "../../../../spec/workbench/draft.16/schemas/native-reply-projection.schema.json"
            ))
        })
        .validate(value)
        .map_err(|e| {
            format!(
                "invalid native reply projection at {}: {e}",
                e.instance_path
            )
        })?;
    Ok(value.clone())
}

pub(super) fn validate_observation_shape(value: &Value) -> Result<(), String> {
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    VALIDATOR
        .get_or_init(|| {
            schema_validator(include_str!(
                "../../../../spec/workbench/draft.16/schemas/mck-observation.schema.json"
            ))
        })
        .validate(value)
        .map_err(|e| {
            format!(
                "invalid native reply observation at {}: {e}",
                e.instance_path
            )
        })
}

pub(super) fn validate_report_shape(value: &Value) -> Result<(), String> {
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    VALIDATOR
        .get_or_init(|| {
            schema_validator(include_str!(
                "../../../../spec/workbench/draft.16/schemas/mck-report.schema.json"
            ))
        })
        .validate(value)
        .map_err(|e| format!("invalid native reply report at {}: {e}", e.instance_path))
}
