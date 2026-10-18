//! Captured-call and fixture infrastructure only. Native reply bytes stay opaque;
//! the implementation adapter owns response decoding and authority correlation.

use serde_json::Value;
use std::sync::OnceLock;

fn schema_validator(schema: &str) -> jsonschema::Validator {
    let mut options = jsonschema::options();
    options.with_retriever(super::contract::OfflineOnly);
    for text in [
        include_str!("../../../../spec/workbench/schemas/value.schema.json"),
        include_str!("../../../../spec/workbench/schemas/outcome-value.schema.json"),
        include_str!("../../../../spec/workbench/draft.5/schemas/terminal-outcomes.schema.json"),
        include_str!("../../../../spec/workbench/draft.3/schemas/value-type.schema.json"),
        include_str!("../../../../spec/workbench/draft.3/schemas/definitions.schema.json"),
        include_str!("../../../../spec/workbench/draft.3/schemas/manifest.schema.json"),
        include_str!(
            "../../../../spec/workbench/executions/0.2.0-draft.1/schemas/identity.schema.json"
        ),
        include_str!(
            "../../../../spec/workbench/execution-plan/0.2.0-draft.1/schemas/plan.schema.json"
        ),
        include_str!("../../../../spec/workbench/admission/draft.1/schemas/selection.schema.json"),
        include_str!("../../../../spec/workbench/draft.21/schemas/mck-input.schema.json"),
        include_str!(
            "../../../../spec/workbench/draft.21/schemas/native-client-projection.schema.json"
        ),
        include_str!("../../../../spec/workbench/draft.21/schemas/mck-observation.schema.json"),
        include_str!("../../../../spec/workbench/draft.21/schemas/mck-capabilities.schema.json"),
    ] {
        let value: Value = serde_json::from_str(text).expect("native client MCK schema JSON");
        options.with_resource(
            value["$id"].as_str().expect("native client MCK schema id"),
            jsonschema::Resource::from_contents(value.clone()).expect("schema resource"),
        );
    }
    let value: Value = serde_json::from_str(schema).expect("native client MCK schema JSON");
    options.build(&value).expect("native client MCK schema")
}

pub(super) fn validate_corpus_shape(value: &Value) -> Result<(), String> {
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    VALIDATOR
        .get_or_init(|| {
            schema_validator(include_str!(
                "../../../../spec/workbench/draft.21/schemas/mck-corpus.schema.json"
            ))
        })
        .validate(value)
        .map_err(|e| format!("invalid native client corpus at {}: {e}", e.instance_path))
}

pub(super) fn validate_input(value: &Value) -> Result<(), String> {
    super::contract::encoded_size(value, 491520)?;
    let mut calls = std::collections::BTreeSet::new();
    let mut held = std::collections::BTreeSet::new();
    for call in value["invocations"]
        .as_array()
        .expect("schema checked calls")
    {
        let id = call["id"].as_str().expect("schema checked id");
        if !calls.insert(id) {
            return Err("duplicate native client invocation id".into());
        }
        if call["held"] == true {
            held.insert(id);
        }
    }
    let mut attempts = std::collections::BTreeSet::new();
    let mut delivered = std::collections::BTreeSet::new();
    for action in value["actions"].as_array().expect("schema checked actions") {
        if let Some(id) = action["id"].as_str()
            && !attempts.insert(id)
        {
            return Err("duplicate native client attempt id".into());
        }
        if let Some(id) = action["call"].as_str()
            && (!held.contains(id) || !delivered.insert(id))
        {
            return Err("invalid native client delivery reference".into());
        }
    }
    if value["evaluation"]["inputs"]["format"] == "json" {
        let source = value["evaluation"]["inputs"]["source"]
            .as_str()
            .expect("schema checked source");
        if !crate::json::strict::parse(source)?.is_array() {
            return Err("native client arguments must be a JSON array".into());
        }
    }
    Ok(())
}

pub(super) fn projection(value: &Value) -> Result<Value, String> {
    super::contract::encoded_size(value, super::contract::MAX_VALUE_BYTES)?;
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    VALIDATOR
        .get_or_init(|| {
            schema_validator(include_str!(
                "../../../../spec/workbench/draft.21/schemas/native-client-projection.schema.json"
            ))
        })
        .validate(value)
        .map_err(|e| {
            format!(
                "invalid native client projection at {}: {e}",
                e.instance_path
            )
        })?;
    super::native_policy_client::validate_plans(value)?;
    Ok(value.clone())
}

pub(super) fn validate_observation_shape(value: &Value) -> Result<(), String> {
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    VALIDATOR
        .get_or_init(|| {
            schema_validator(include_str!(
                "../../../../spec/workbench/draft.21/schemas/mck-observation.schema.json"
            ))
        })
        .validate(value)
        .map_err(|e| {
            format!(
                "invalid native client observation at {}: {e}",
                e.instance_path
            )
        })
}

pub(super) fn validate_report_shape(value: &Value) -> Result<(), String> {
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    VALIDATOR
        .get_or_init(|| {
            schema_validator(include_str!(
                "../../../../spec/workbench/draft.21/schemas/mck-report.schema.json"
            ))
        })
        .validate(value)
        .map_err(|e| format!("invalid native client report at {}: {e}", e.instance_path))
}

/// These are observation infrastructure identities, not credentials or source
/// semantics. Preserve the public UTF-16 bounds after structural schema checks.
pub(super) fn validate_plans(value: &Value) -> Result<(), String> {
    let mut identities = std::collections::BTreeSet::new();
    let mut plans = std::collections::BTreeSet::new();
    for plan in value["acceptedPlans"]
        .as_array()
        .expect("schema checked accepted plans")
    {
        let fields = [
            "hostId",
            "sessionId",
            "providerId",
            "executionId",
            "snapshotId",
        ]
        .map(|field| {
            plan["identity"][field]
                .as_str()
                .expect("schema checked identity")
        });
        for field in fields {
            super::contract::identity(field, 128)?;
        }
        let plan_id = plan["planId"].as_str().expect("schema checked plan id");
        super::contract::identity(plan_id, 128)?;
        if !identities.insert((fields[0], fields[1], fields[2], fields[3]))
            || !plans.insert((fields[0], fields[1], fields[2], plan_id))
        {
            return Err("duplicate accepted execution plan observation".into());
        }
    }
    Ok(())
}
