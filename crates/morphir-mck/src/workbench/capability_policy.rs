//! Closed selected-plan fixture infrastructure. Model, arguments, and captured
//! boundary and completion text stay opaque; the production adapter owns validation/execution.
use serde_json::Value;
use std::sync::OnceLock;

fn schema_validator(schema: &str) -> jsonschema::Validator {
    let mut options = jsonschema::options();
    options.with_retriever(super::contract::OfflineOnly);
    for source in [
        include_str!("../../../../spec/workbench/schemas/value.schema.json"),
        include_str!("../../../../spec/workbench/schemas/outcome-value.schema.json"),
        include_str!("../../../../spec/workbench/draft.5/schemas/terminal-outcomes.schema.json"),
        include_str!("../../../../spec/workbench/admission/draft.1/schemas/selection.schema.json"),
        include_str!("../../../../spec/workbench/draft.12/schemas/mck-input.schema.json"),
        include_str!(
            "../../../../spec/workbench/draft.12/schemas/capability-policy-projection.schema.json"
        ),
        include_str!("../../../../spec/workbench/draft.12/schemas/mck-observation.schema.json"),
        include_str!("../../../../spec/workbench/draft.12/schemas/mck-capabilities.schema.json"),
    ] {
        let value: Value = serde_json::from_str(source).expect("capability policy schema JSON");
        options.with_resource(
            value["$id"].as_str().expect("capability policy schema id"),
            jsonschema::Resource::from_contents(value.clone())
                .expect("capability policy schema resource"),
        );
    }
    options
        .build(&serde_json::from_str(schema).expect("capability policy schema JSON"))
        .expect("capability policy schema")
}

macro_rules! shape_validator {
    ($name:ident, $schema:literal) => {
        pub(super) fn $name(value: &Value) -> Result<(), String> {
            static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
            VALIDATOR
                .get_or_init(|| schema_validator(include_str!($schema)))
                .validate(value)
                .map_err(|e| {
                    format!(
                        "invalid capability policy {} at {}: {e}",
                        stringify!($name),
                        e.instance_path
                    )
                })
        }
    };
}
shape_validator!(
    validate_corpus_shape,
    "../../../../spec/workbench/draft.12/schemas/mck-corpus.schema.json"
);
shape_validator!(
    validate_observation_shape,
    "../../../../spec/workbench/draft.12/schemas/mck-observation.schema.json"
);
shape_validator!(
    validate_report_shape,
    "../../../../spec/workbench/draft.12/schemas/mck-report.schema.json"
);
shape_validator!(
    validate_projection_shape,
    "../../../../spec/workbench/draft.12/schemas/capability-policy-projection.schema.json"
);

pub(super) fn validate_input(value: &Value) -> Result<(), String> {
    super::contract::encoded_size(value, 1048576)?;
    Ok(())
}

pub(super) fn projection(value: &Value) -> Result<Value, String> {
    super::contract::encoded_size(value, super::contract::MAX_VALUE_BYTES)?;
    validate_projection_shape(value)?;
    if let Some(code) = value["failure"]["code"].as_str() {
        super::contract::identity(code, 128)?;
    }
    let mut projected = value.clone();
    if !projected["outcomes"].is_null() {
        projected["outcomes"] = super::outcomes::projection(&projected["outcomes"])?;
    }
    Ok(projected)
}
